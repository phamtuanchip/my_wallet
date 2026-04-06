import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'card_storage.dart';

final logger = Logger();

/// Android HCE Card Emulation Service
/// This demonstrates how to implement HOST_APDU_SERVICE for card emulation.
/// 
/// To use: Extend this logic in your Kotlin/Java code with processCommandApdu()
/// See references/hce-guide.md for complete Android service implementation
class CardEmulationService {
  static final CardEmulationService _instance = CardEmulationService._internal();
  
  factory CardEmulationService() {
    return _instance;
  }
  
  CardEmulationService._internal();
  
  // Your app's AID (Application Identifier) for card emulation
  // Format: F2 followed by your identifier (7-8 bytes total)
  static final Uint8List APP_AID = Uint8List.fromList([
    0xF2, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, // 7 bytes
  ]);
  
  // Virtual card state
  String? _activeCardId;
  ScannedCard? _currentCard;
  final CardStorageService _storage = CardStorageService();
  
  /// Process APDU command from NFC reader
  /// 
  /// This method would be called from HostApduService.processCommandApdu()
  /// in your Android native code.
  /// 
  /// Example Kotlin call:
  /// ```kotlin
  /// override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray {
  ///   return CardEmulationService().processCommand(Uint8List.fromList(commandApdu ?? byteArrayOf()));
  /// }
  /// ```
  Future<Uint8List> processCommand(Uint8List commandApdu) async {
    try {
      logger.i("APDU received: ${_bytesToHex(commandApdu)}");
      
      // Parse APDU header
      if (commandApdu.length < 4) {
        return _statusResponse(0x67, 0x00); // Wrong length
      }
      
      final cla = commandApdu[0];
      final ins = commandApdu[1];
      final p1 = commandApdu[2];
      final p2 = commandApdu[3];
      
      // Handle SELECT command (card activation)
      if (ins == 0xA4) {
        return _handleSelect(cla, p1, p2, commandApdu);
      }
      
      // Handle business logic commands (only after SELECT)
      if (_activeCardId != null) {
        return await _handleTransaction(ins, p1, p2, commandApdu);
      }
      
      return _statusResponse(0x69, 0x85); // Conditions not satisfied
    } catch (e) {
      logger.e("APDU processing error: $e");
      return _statusResponse(0x6F, 0x00); // Unknown error
    }
  }
  
  /// Handle SELECT AID command (card activation)
  /// 
  /// Structure: 00 A4 04 00 [Len] [AID]
  /// Response: [Data] [Status: Success=90 00, Error=6A 82]
  Future<Uint8List> _handleSelect(
    int cla,
    int p1,
    int p2,
    Uint8List apdu,
  ) async {
    if (cla != 0x00 || p1 != 0x04 || p2 != 0x00) {
      return _statusResponse(0x6E, 0x00); // Class not supported
    }
    
    if (apdu.length < 5) {
      return _statusResponse(0x67, 0x00); // Wrong length
    }
    
    int lenField = apdu[4];
    if (apdu.length < 5 + lenField) {
      return _statusResponse(0x67, 0x00); // Wrong length
    }
    
    final aidReceived = apdu.sublist(5, 5 + lenField);
    
    // Check if requested AID matches ours
    if (aidReceived.length == APP_AID.length && 
        listsEqual(aidReceived, APP_AID)) {
      
      logger.i("SELECT success - AID matched");
      
      // Initialize card emulation with most recent card
      final cards = await _storage.getAllCards(limit: 1);
      if (cards.isNotEmpty) {
        _activeCardId = cards.first.id;
        _currentCard = cards.first;
        
        // Log transaction
        await _storage.recordTransaction(
          cardId: _activeCardId!,
          transactionType: 'emulation_activated',
          status: 'success',
          description: 'Card emulation session started',
        );
        
        // Return: FCI (File Control Information) + Success status
        return _buildFCIResponse(cards.first) + _statusResponse(0x90, 0x00);
      } else {
        logger.w("No cards available for emulation");
        return _statusResponse(0x69, 0x85); // Conditions not satisfied
      }
    }
    
    logger.w("SELECT failed - AID not found: ${_bytesToHex(aidReceived)}");
    return _statusResponse(0x6A, 0x82); // File not found (AID not found)
  }
  
  /// Handle transaction commands after card activation
  /// 
  /// Custom commands defined by your app:
  /// - 0xB0: READ (get balance/data)
  /// - 0xD0: WRITE (update balance/state)
  /// - 0xCB: AUTHENTICATE (optional)
  /// - 0xCA: GET RESPONSE (get more data)
  Future<Uint8List> _handleTransaction(
    int ins,
    int p1,
    int p2,
    Uint8List apdu,
  ) async {
    if (_currentCard == null) {
      return _statusResponse(0x69, 0x85);
    }
    
    switch (ins) {
      case 0xB0: // READ command
        return _handleRead(p1, p2, apdu);
      
      case 0xD0: // WRITE command
        return await _handleWrite(p1, p2, apdu);
      
      case 0xCB: // AUTHENTICATE
        return _handleAuthenticate(p1, p2, apdu);
      
      case 0xCA: // GET RESPONSE
        return _handleGetResponse(p1, p2);
      
      default:
        logger.w("Unknown instruction: 0x${ins.toRadixString(16)}");
        return _statusResponse(0x6D, 0x00); // Instruction not supported
    }
  }
  
  /// READ command: return card data
  /// 
  /// Request: B0 P1 P2 [Le]
  ///   P1 = data offset MSB
  ///   P2 = data offset LSB
  ///   Le = length to read
  /// Response: [Data] [Status]
  Uint8List _handleRead(int p1, int p2, Uint8List apdu) {
    if (_currentCard == null) {
      return _statusResponse(0x69, 0x85);
    }
    
    // Build response: wallet balance (4 bytes) + card type (1 byte)
    Uint8List responseData = Uint8List(5);
    
    // Encode balance as big-endian 32-bit integer (cents)
    int balanceCents = ((_currentCard!.balance ?? 0) * 100).toInt();
    responseData[0] = (balanceCents >> 24) & 0xFF;
    responseData[1] = (balanceCents >> 16) & 0xFF;
    responseData[2] = (balanceCents >> 8) & 0xFF;
    responseData[3] = balanceCents & 0xFF;
    responseData[4] = _encodeCardType(_currentCard!.cardType);
    
    logger.i("READ response: balance=${_currentCard!.balance}, type=${_currentCard!.cardType}");
    
    // Record transaction
    _storage.recordTransaction(
      cardId: _currentCard!.id,
      transactionType: 'emulation_read',
      status: 'success',
      description: 'Card data read via emulation',
    );
    
    return responseData + _statusResponse(0x90, 0x00);
  }
  
  /// WRITE command: update card balance/state
  /// 
  /// Request: D0 P1 P2 [Lc] [Data]
  ///   Data format: [Amount/4 bytes] [Operation/1 byte]
  ///   Operation: 0x01=ADD, 0x02=SUBTRACT, 0x03=SET
  /// Response: [New Balance/4 bytes] [Status]
  Future<Uint8List> _handleWrite(int p1, int p2, Uint8List apdu) async {
    if (_currentCard == null || apdu.length < 6) {
      return _statusResponse(0x67, 0x00); // Wrong length
    }
    
    int lcField = apdu[4];
    if (apdu.length < 5 + lcField) {
      return _statusResponse(0x67, 0x00);
    }
    
    final writeData = apdu.sublist(5, 5 + lcField);
    
    if (writeData.length < 5) {
      return _statusResponse(0x67, 0x00);
    }
    
    // Parse amount (4 bytes big-endian, in cents)
    int amountCents = 
      ((writeData[0] & 0xFF) << 24) |
      ((writeData[1] & 0xFF) << 16) |
      ((writeData[2] & 0xFF) << 8) |
      (writeData[3] & 0xFF);
    
    double amount = amountCents / 100.0;
    int operation = writeData[4];
    
    // Calculate new balance
    double newBalance = _currentCard!.balance ?? 0;
    switch (operation) {
      case 0x01: // ADD
        newBalance += amount;
        break;
      case 0x02: // SUBTRACT
        newBalance -= amount;
        break;
      case 0x03: // SET
        newBalance = amount;
        break;
      default:
        return _statusResponse(0x67, 0x00); // Invalid operation
    }
    
    // Update database
    await _storage.updateCard(
      cardId: _currentCard!.id,
      balance: newBalance,
    );
    
    _currentCard!.balance = newBalance;
    
    // Record transaction
    await _storage.recordTransaction(
      cardId: _currentCard!.id,
      transactionType: 'emulation_write',
      status: 'success',
      description: 'Balance updated via emulation',
      amount: amount,
    );
    
    logger.i("WRITE success: new balance=$newBalance");
    
    // Response: new balance (4 bytes) + status
    Uint8List response = Uint8List(4);
    int newBalanceCents = (newBalance * 100).toInt();
    response[0] = (newBalanceCents >> 24) & 0xFF;
    response[1] = (newBalanceCents >> 16) & 0xFF;
    response[2] = (newBalanceCents >> 8) & 0xFF;
    response[3] = newBalanceCents & 0xFF;
    
    return response + _statusResponse(0x90, 0x00);
  }
  
  /// AUTHENTICATE command: verify card credentials
  /// 
  /// Request: CB P1 P2 [Lc] [Challenge/8 bytes]
  /// Response: [Response/8 bytes] [Status]
  Uint8List _handleAuthenticate(int p1, int p2, Uint8List apdu) {
    if (apdu.length < 13) {
      return _statusResponse(0x67, 0x00);
    }
    
    final challenge = apdu.sublist(5, 13); // 8 bytes
    
    // Implement your authentication logic here
    // Example: XOR challenge with card UID
    final uid = _currentCard!.uid;
    final uidBytes = _hexToBytes(uid);
    
    final response = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      response[i] = challenge[i] ^ (uidBytes.isNotEmpty ? uidBytes[i % uidBytes.length] : 0);
    }
    
    logger.i("AUTHENTICATE success");
    
    return response + _statusResponse(0x90, 0x00);
  }
  
  /// GET RESPONSE: retrieve more data if previous response was truncated
  Uint8List _handleGetResponse(int p1, int p2) {
    // This would be called if a previous response indicated more data available (0x61 XX)
    // For now, return empty response
    return _statusResponse(0x90, 0x00);
  }
  
  /// Encode card type for response
  int _encodeCardType(String cardType) {
    if (cardType.contains("Classic 1K")) return 0x01;
    if (cardType.contains("Classic 4K")) return 0x04;
    if (cardType.contains("Ultralight")) return 0x02;
    if (cardType.contains("Plus")) return 0x03;
    return 0x00; // Unknown
  }
  
  /// Build FCI (File Control Information) response
  Uint8List _buildFCIResponse(ScannedCard card) {
    // FCI template: [Tag] [Length] [Data]
    // Tag 84 = Dedicated File Name (AID)
    // Tag A5 = Proprietary template
    
    List<int> fci = [
      0x6F,        // FCI template tag
      0x05,        // Length
      0x84, 0x07,  // DF Name tag, length
    ];
    fci.addAll(APP_AID);
    
    return Uint8List.fromList(fci);
  }
  
  // ============== Helper Methods ==============
  
  /// Create status response
  Uint8List _statusResponse(int sw1, int sw2) {
    return Uint8List.fromList([sw1, sw2]);
  }
  
  /// Convert bytes to hex string
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');
  }
  
  /// Convert hex string to bytes
  Uint8List _hexToBytes(String hex) {
    List<int> bytes = [];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }
  
  /// Check if two lists are equal
  bool listsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  
  /// Deactivate card emulation session
  void deactivateCard(int reason) {
    logger.i("Card deactivated. Reason: $reason");
    
    // Record deactivation
    if (_currentCard != null && _activeCardId != null) {
      _storage.recordTransaction(
        cardId: _activeCardId!,
        transactionType: 'emulation_deactivated',
        status: 'success',
        description: 'Card emulation session ended (reason: $reason)',
      );
    }
    
    _activeCardId = null;
    _currentCard = null;
  }
}
