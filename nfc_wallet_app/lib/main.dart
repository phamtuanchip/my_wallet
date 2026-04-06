import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NFC Wallet App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const NFCScannerScreen(),
    );
  }
}

class NFCScannerScreen extends StatefulWidget {
  const NFCScannerScreen({Key? key}) : super(key: key);

  @override
  State<NFCScannerScreen> createState() => _NFCScannerScreenState();
}

class _NFCScannerScreenState extends State<NFCScannerScreen> {
  final logger = Logger();
  String _scanResult = 'Tap card to scan';
  bool _isScanning = false;
  List<NFCCard> _savedCards = [];
  Database? _database;
  NFCCard? _emulatingCard;
  bool _isEmulating = false;
  bool _isSendingCard = false;
  NFCCard? _cardToSend;
  
  // File selection state
  PlatformFile? _selectedFile;
  bool _isSendingFile = false;
  String _fileSendStatus = '';
  bool _isReceivingFile = false;
  String _fileReceiveStatus = '';
  double _fileSendProgress = 0.0; // Progress from 0.0 to 1.0
  
  static const platform = MethodChannel('com.example.nfc_wallet_app/hce');

  @override
  void initState() {
    super.initState();
    _initDatabase();
    _checkNFCAvailability();
  }

  Future<void> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'nfc_wallet.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE cards (
            id TEXT PRIMARY KEY,
            uid TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            tagType TEXT NOT NULL,
            content TEXT,
            timestamp INTEGER NOT NULL
          )
        ''');
      },
    );

    await _loadSavedCards();
  }

  Future<void> _loadSavedCards() async {
    if (_database == null) return;

    final List<Map<String, dynamic>> maps = await _database!.query('cards', orderBy: 'timestamp DESC');
    setState(() {
      _savedCards = List.generate(maps.length, (i) {
        return NFCCard.fromMap(maps[i]);
      });
    });
  }

  Future<void> _saveCard(String uid, String tagType, String content) async {
    if (_database == null) return;

    // Check if card with this UID already exists
    final existingCards = await _database!.query(
      'cards',
      where: 'uid = ?',
      whereArgs: [uid],
    );

    if (existingCards.isNotEmpty) {
      // Update existing card
      await _database!.update(
        'cards',
        {
          'content': content,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'uid = ?',
        whereArgs: [uid],
      );
      logger.i('Updated existing card with UID: $uid');
    } else {
      // Create new card with serializable name
      final nextNumber = _savedCards.length + 1;
      final cardName = 'nfc_$nextNumber';

      await _database!.insert(
        'cards',
        {
          'id': const Uuid().v4(),
          'uid': uid,
          'name': cardName,
          'tagType': tagType,
          'content': content,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
      logger.i('Saved new card: $cardName with UID: $uid');
    }

    await _loadSavedCards();
  }

  Future<void> _deleteCard(String uid) async {
    if (_database == null) return;

    await _database!.delete(
      'cards',
      where: 'uid = ?',
      whereArgs: [uid],
    );

    await _loadSavedCards();
    logger.i('Deleted card with UID: $uid');
  }

  // Card Emulation Methods
  Future<void> _startCardEmulation(NFCCard card) async {
    try {
      // Communicate with native Android code to start HCE
      final result = await platform.invokeMethod('startCardEmulation', {
        'cardId': card.id,
        'cardName': card.name,
        'cardUid': card.uid,
        'cardData': card.content ?? '',
      });

      setState(() {
        _emulatingCard = card;
        _isEmulating = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Emulating card: ${card.name}')),
      );

      logger.i('Started emulating card: ${card.name}, result: $result');
    } on PlatformException catch (e) {
      logger.e('Platform exception starting card emulation: ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start card emulation: ${e.message}')),
      );
    } catch (e) {
      logger.e('Error starting card emulation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start card emulation')),
      );
    }
  }

  Future<void> _stopCardEmulation() async {
    try {
      // Communicate with native Android code to stop HCE
      final result = await platform.invokeMethod('stopCardEmulation');

      setState(() {
        _emulatingCard = null;
        _isEmulating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card emulation stopped')),
      );

      logger.i('Stopped card emulation, result: $result');
    } on PlatformException catch (e) {
      logger.e('Platform exception stopping card emulation: ${e.message}');
      // Still update UI even if native call fails
      setState(() {
        _emulatingCard = null;
        _isEmulating = false;
      });
    } catch (e) {
      logger.e('Error stopping card emulation: $e');
      // Still update UI
      setState(() {
        _emulatingCard = null;
        _isEmulating = false;
      });
    }
  }

  // P2P NFC Communication Methods
  Future<void> _sendCardViaNFC(NFCCard card) async {
    if (_isSendingCard) return;

    setState(() {
      _isSendingCard = true;
      _cardToSend = card;
      _scanResult = 'Ready to send card: ${card.name}\nBring devices close together';
    });

    try {
      // For P2P sending, we'll use a different approach
      // Create NDEF message with card data
      final cardData = {
        'id': card.id,
        'uid': card.uid,
        'name': card.name,
        'tagType': card.tagType,
        'content': card.content,
        'timestamp': card.timestamp.millisecondsSinceEpoch,
        'type': 'nfc_wallet_card' // Identifier for our app
      };

      final jsonString = jsonEncode(cardData);
      final ndefMessage = NdefMessage([
        NdefRecord(
          typeNameFormat: NdefTypeNameFormat.media,
          type: Uint8List.fromList('application/json'.codeUnits),
          identifier: Uint8List(0),
          payload: Uint8List.fromList(jsonString.codeUnits),
        ),
      ]);

      // Note: P2P sending requires both devices to be in NFC discovery mode
      // We'll use a polling approach - start NFC session and wait for peer device
      await _startP2PSession(ndefMessage);

      logger.i('Prepared card for P2P sending: ${card.name}');
    } catch (e) {
      logger.e('Error preparing card for P2P: $e');
      await _stopSendingCard();
      setState(() {
        _scanResult = 'Error preparing card for sending: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to prepare card for sending')),
      );
    }
  }

  Future<void> _startP2PSession(NdefMessage message) async {
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
        },
        onDiscovered: (NfcTag tag) async {
          // Check if this is a peer device ready for P2P
          final ndefTag = Ndef.from(tag);
          if (ndefTag != null && ndefTag.isWritable) {
            // This might be a peer device - try to write our message
            try {
              await ndefTag.write(message);
              await NfcManager.instance.stopSession();

              setState(() {
                _scanResult = 'Card sent successfully!\n${_cardToSend?.name}';
                _isSendingCard = false;
                _cardToSend = null;
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Card "${_cardToSend?.name}" sent successfully!')),
              );

              logger.i('Card sent via P2P: ${_cardToSend?.name}');
            } catch (e) {
              logger.e('Error writing to peer device: $e');
              setState(() {
                _scanResult = 'Failed to send to peer device: $e';
              });
            }
          } else {
            // This is a regular tag, handle normally
            await _handleTagDiscovered(tag);
          }
        },
      );
    } catch (e) {
      logger.e('Error starting P2P session: $e');
      await _stopSendingCard();
    }
  }

  Future<void> _stopSendingCard() async {
    try {
      await NfcManager.instance.stopSession();
      setState(() {
        _isSendingCard = false;
        _cardToSend = null;
        _scanResult = 'Card sending cancelled';
      });
      logger.i('Stopped P2P session');
    } catch (e) {
      logger.e('Error stopping P2P session: $e');
    }
  }

  // File selection and sending methods
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'pdf', 'txt', 'doc', 'docx'],
        allowMultiple: false,
      );

      if (result != null) {
        setState(() {
          _selectedFile = result.files.first;
          _fileSendStatus = 'File selected: ${_selectedFile!.name}';
        });
        
        logger.i('File selected: ${_selectedFile!.name}, size: ${_selectedFile!.size} bytes');
      }
    } catch (e) {
      logger.e('Error picking file: $e');
      setState(() {
        _fileSendStatus = 'Error selecting file: $e';
      });
    }
  }

  Future<void> _sendFileViaNFC() async {
    if (_selectedFile == null) {
      setState(() {
        _fileSendStatus = 'No file selected';
      });
      return;
    }

    try {
      setState(() {
        _isSendingFile = true;
        _fileSendStatus = 'Preparing file for sending...';
      });

      // Read file data
      Uint8List fileData;
      if (_selectedFile!.bytes != null) {
        fileData = _selectedFile!.bytes!;
      } else if (_selectedFile!.path != null) {
        // If bytes are not available, try reading from path
        final file = File(_selectedFile!.path!);
        fileData = await file.readAsBytes();
      } else {
        throw Exception('Unable to read file data');
      }

      // Create file metadata
      final fileMetadata = {
        'name': _selectedFile!.name,
        'size': _selectedFile!.size,
        'extension': _selectedFile!.extension,
        'type': 'nfc_wallet_file',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final metadataJson = jsonEncode(fileMetadata);
      
      // Create NDEF message with file metadata and data
      final ndefMessage = NdefMessage([
        NdefRecord(
          typeNameFormat: NdefTypeNameFormat.media,
          type: Uint8List.fromList('application/json'.codeUnits),
          identifier: Uint8List(0),
          payload: Uint8List.fromList(metadataJson.codeUnits),
        ),
        NdefRecord(
          typeNameFormat: NdefTypeNameFormat.media,
          type: Uint8List.fromList('application/octet-stream'.codeUnits),
          identifier: Uint8List(0),
          payload: fileData,
        ),
      ]);

      await _startFileP2PSession(ndefMessage);

    } catch (e) {
      logger.e('Error preparing file for sending: $e');
      setState(() {
        _isSendingFile = false;
        _fileSendStatus = 'Error preparing file: $e';
      });
    }
  }

  Future<void> _startFileP2PSession(NdefMessage message) async {
    try {
      setState(() {
        _fileSendStatus = 'Starting file transfer...';
        _fileSendProgress = 0.1;
      });

      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
        },
        onDiscovered: (NfcTag tag) async {
          try {
            setState(() {
              _fileSendProgress = 0.5;
            });
            
            final ndefTag = Ndef.from(tag);
            if (ndefTag != null && ndefTag.isWritable) {
              setState(() {
                _fileSendProgress = 0.8;
              });
              
              await ndefTag.write(message);
              await NfcManager.instance.stopSession();

              setState(() {
                _fileSendStatus = 'File sent successfully!\n${_selectedFile?.name}';
                _isSendingFile = false;
                _selectedFile = null;
                _fileSendProgress = 1.0;
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('File "${_selectedFile?.name}" sent successfully!')),
              );

              logger.i('File sent via P2P: ${_selectedFile?.name}');
            } else {
              setState(() {
                _fileSendStatus = 'Error: Device does not support file transfer';
                _isSendingFile = false;
                _fileSendProgress = 0.0;
              });
            }
          } catch (e) {
            setState(() {
              _fileSendStatus = 'Error sending file: $e';
              _isSendingFile = false;
              _fileSendProgress = 0.0;
            });
            logger.e('Error writing file to peer device: $e');
          }
        },
      );
    } catch (e) {
      logger.e('Error starting file P2P session: $e');
      setState(() {
        _isSendingFile = false;
        _fileSendStatus = 'Error starting file transfer: $e';
        _fileSendProgress = 0.0;
      });
    }
  }

  Future<void> _stopFileSending() async {
    try {
      await NfcManager.instance.stopSession();
      setState(() {
        _isSendingFile = false;
        _fileSendStatus = 'File sending cancelled';
        _fileSendProgress = 0.0;
      });
      logger.i('File sending stopped by user');
    } catch (e) {
      logger.e('Error stopping file sending: $e');
    }
  }

  // File reception methods
  Future<void> _startFileReception() async {
    try {
      setState(() {
        _isReceivingFile = true;
        _fileReceiveStatus = 'Waiting for file transfer...';
      });

      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
        },
        onDiscovered: (NfcTag tag) async {
          await _handleFileReception(tag);
        },
      );
    } catch (e) {
      logger.e('Error starting file reception: $e');
      setState(() {
        _isReceivingFile = false;
        _fileReceiveStatus = 'Error starting file reception: $e';
      });
    }
  }

  Future<void> _handleFileReception(NfcTag tag, {bool autoStopSession = true}) async {
    try {
      final ndefTag = Ndef.from(tag);
      if (ndefTag == null || ndefTag.cachedMessage == null) {
        logger.w('Received tag is not NDEF formatted');
        setState(() {
          _fileReceiveStatus = 'Received invalid data format';
          _isReceivingFile = false;
        });
        return;
      }

      final records = ndefTag.cachedMessage!.records;
      if (records.length < 2) {
        setState(() {
          _fileReceiveStatus = 'Incomplete file data received';
          _isReceivingFile = false;
        });
        return;
      }

      // Process file metadata (first record)
      final metadataRecord = records[0];
      if (metadataRecord.typeNameFormat == NdefTypeNameFormat.media &&
          String.fromCharCodes(metadataRecord.type) == 'application/json') {
        
        final metadataJson = String.fromCharCodes(metadataRecord.payload);
        final metadata = jsonDecode(metadataJson);
        
        if (metadata['type'] == 'nfc_wallet_file') {
          // Process file data (second record)
          final fileRecord = records[1];
          final fileData = fileRecord.payload;
          
          await _saveReceivedFile(metadata, fileData);
          
          setState(() {
            _fileReceiveStatus = 'File received successfully!\n${metadata['name']}';
            _isReceivingFile = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File "${metadata['name']}" received and saved!')),
          );

          logger.i('File received via NFC: ${metadata['name']}');
        } else {
          setState(() {
            _fileReceiveStatus = 'Received data is not a file';
            _isReceivingFile = false;
          });
        }
      } else {
        setState(() {
          _fileReceiveStatus = 'Invalid file metadata format';
          _isReceivingFile = false;
        });
      }

      if (autoStopSession) {
        await NfcManager.instance.stopSession();
      }
    } catch (e) {
      logger.e('Error processing received file: $e');
      setState(() {
        _fileReceiveStatus = 'Error processing received file: $e';
        _isReceivingFile = false;
      });
    }
  }

  Future<void> _saveReceivedFile(Map<String, dynamic> metadata, Uint8List fileData) async {
    try {
      // Get the downloads directory
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        throw Exception('Unable to access downloads directory');
      }

      final downloadsPath = directory.path;

      // Create unique filename if file already exists
      final originalName = metadata['name'] as String;
      final extension = metadata['extension'] as String? ?? '';
      final baseName = extension.isNotEmpty ? originalName.replaceAll('.$extension', '') : originalName;
      
      String fileName = originalName;
      int counter = 1;
      
      while (await File('$downloadsPath/$fileName').exists()) {
        fileName = '$baseName ($counter).${extension.isNotEmpty ? extension : 'bin'}';
        counter++;
      }

      final filePath = '$downloadsPath/$fileName';
      final file = File(filePath);
      
      await file.writeAsBytes(fileData);
      
      logger.i('File saved to: $filePath, size: ${fileData.length} bytes');
    } catch (e) {
      logger.e('Error saving received file: $e');
      rethrow;
    }
  }

  Future<void> _receiveCardViaNFC(NfcTag tag) async {
    try {
      final ndefTag = Ndef.from(tag);
      if (ndefTag == null || ndefTag.cachedMessage == null) {
        logger.w('Received tag is not NDEF formatted');
        return;
      }

      final records = ndefTag.cachedMessage!.records;
      for (final record in records) {
        try {
          // Check if it's our card data (MIME type record with JSON)
          if (record.typeNameFormat == NdefTypeNameFormat.media &&
              String.fromCharCodes(record.type) == 'application/json') {
            final jsonString = String.fromCharCodes(record.payload);
            if (jsonString.contains('nfc_wallet_card')) {
              await _processReceivedCardData(jsonString);
              break;
            }
          }
        } catch (e) {
          logger.w('Error processing NDEF record: $e');
        }
      }
    } catch (e) {
      logger.e('Error processing received NFC data: $e');
    }
  }

  Future<void> _processReceivedCardData(String jsonString) async {
    try {
      // Parse the JSON data (simplified parsing)
      final cardData = _parseCardJson(jsonString);
      if (cardData != null) {
        // Save the received card
        await _saveReceivedCard(cardData);

        setState(() {
          _scanResult = 'Card received successfully!\n${cardData['name']}';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Card "${cardData['name']}" received and saved!')),
        );

        logger.i('Successfully processed received card: ${cardData['name']}');
      }
    } catch (e) {
      logger.e('Error processing received card data: $e');
      setState(() {
        _scanResult = 'Error processing received card: $e';
      });
    }
  }

  Map<String, dynamic>? _parseCardJson(String jsonString) {
    try {
      // Simple JSON parsing (in production, use json.decode)
      final data = <String, dynamic>{};

      // Extract key-value pairs (simplified parsing)
      final pairs = jsonString.replaceAll('{', '').replaceAll('}', '').split(',');
      for (final pair in pairs) {
        final keyValue = pair.split(':');
        if (keyValue.length == 2) {
          final key = keyValue[0].replaceAll('"', '').trim();
          final value = keyValue[1].replaceAll('"', '').trim();
          data[key] = value;
        }
      }

      return data;
    } catch (e) {
      logger.e('Error parsing card JSON: $e');
      return null;
    }
  }

  Future<void> _saveReceivedCard(Map<String, dynamic> cardData) async {
    if (_database == null) return;

    try {
      final cardName = cardData['name']?.toString() ?? 'Received Card';
      final uid = cardData['uid']?.toString() ?? const Uuid().v4().substring(0, 8);
      final tagType = cardData['tagType']?.toString() ?? 'Received via NFC';
      final content = cardData['content']?.toString();

      await _saveCard(uid, tagType, content ?? '');
      logger.i('Saved received card: $cardName');
    } catch (e) {
      logger.e('Error saving received card: $e');
    }
  }

  Future<void> _checkNFCAvailability() async {
    try {
      bool isAvailable = await NfcManager.instance.isAvailable();
      setState(() {
        _scanResult =
            isAvailable ? 'NFC Ready - Tap card to scan' : 'NFC not available';
      });
      logger.i('NFC Available: $isAvailable');
    } catch (e) {
      logger.e('Error checking NFC: $e');
      setState(() {
        _scanResult = 'Error: $e';
      });
    }
  }

  Future<void> _startNFCSession() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _scanResult = 'Scanning...';
    });

    try {
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
        },
        onDiscovered: (NfcTag tag) async {
          await _handleTagDiscovered(tag);
        },
      );
    } catch (e) {
      logger.e('Failed to start NFC session: $e');
      setState(() {
        _scanResult = 'Failed to start scan: $e';
        _isScanning = false;
      });
    }
  }

  Future<void> _handleTagDiscovered(NfcTag tag) async {
    try {
      await NfcManager.instance.stopSession();

      // Check if this is a received card or file via P2P
      await _receiveCardViaNFC(tag);
      await _handleFileReception(tag, autoStopSession: false);

      final ndefTag = Ndef.from(tag);
      final tagData = tag.data as Map<String, dynamic>;

      String uid = '';
      String tagType = 'Unknown';
      String content = '';

      // Extract tag type and UID from tag data
      if (tagData.containsKey('nfca')) {
        final nfcaData = tagData['nfca'] as Map<dynamic, dynamic>? ?? {};
        uid = _bytesToHex(nfcaData['identifier'] as List<int>? ?? []);
        tagType = 'NFC Type A';

        final atqa = nfcaData['atqa'] as List<int>? ?? [];
        final sak = nfcaData['sak'] as int? ?? 0;

        if (sak == 0x08) tagType = 'Mifare Classic 1K';
        else if (sak == 0x18) tagType = 'Mifare Classic 4K';
        else if (sak == 0x04) tagType = 'Mifare Ultralight';
        else if (sak == 0x09) tagType = 'Mifare Mini';
      } else if (tagData.containsKey('nfcb')) {
        final nfcbData = tagData['nfcb'] as Map<dynamic, dynamic>? ?? {};
        uid = _bytesToHex(nfcbData['identifier'] as List<int>? ?? []);
        tagType = 'NFC Type B';
      } else if (tagData.containsKey('nfcf')) {
        final nfcfData = tagData['nfcf'] as Map<dynamic, dynamic>? ?? {};
        uid = _bytesToHex(nfcfData['identifier'] as List<int>? ?? []);
        tagType = 'NFC Type F (FeliCa)';
      } else if (tagData.containsKey('nfcv')) {
        final nfcvData = tagData['nfcv'] as Map<dynamic, dynamic>? ?? {};
        uid = _bytesToHex(nfcvData['identifier'] as List<int>? ?? []);
        tagType = 'NFC Type V';
      }

      // Parse NDEF if available
      if (ndefTag != null && ndefTag.cachedMessage != null) {
        tagType += ' (NDEF)';
        final records = ndefTag.cachedMessage!.records;
        for (var record in records) {
          try {
            String recordType = _parseString(record.type);
            String payload = _bytesToHex(record.payload);
            content += 'Record: $recordType, Payload: ${payload.substring(0, (payload.length < 40 ? payload.length : 40))}\n';
          } catch (e) {
            logger.w('Error parsing record: $e');
          }
        }
      }

      final cardInfo = 'UID: $uid\nType: $tagType\n${content.isNotEmpty ? 'Content:\n$content' : 'No NDEF'}';

      logger.i('Tag discovered: $cardInfo');

      // Auto-save the card
      if (uid.isNotEmpty) {
        await _saveCard(uid, tagType, content);
        setState(() {
          _scanResult = 'Card saved successfully!\n\n$cardInfo';
        });
      } else {
        setState(() {
          _scanResult = 'Card scanned but no UID found\n\n$cardInfo';
        });
      }

      setState(() {
        _isScanning = false;
      });
    } catch (e) {
      logger.e('Error handling tag: $e');
      setState(() {
        _scanResult = 'Error processing tag: $e';
        _isScanning = false;
      });
    }
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
  }

  String _parseString(List<int> bytes) {
    try {
      return String.fromCharCodes(bytes);
    } catch (e) {
      return _bytesToHex(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC Wallet Scanner'),
        elevation: 0,
        actions: [
          // File Send Action
          IconButton(
            onPressed: (_isScanning || _isEmulating || _isSendingCard || _isSendingFile || _isReceivingFile) ? null : _pickFile,
            icon: Icon(
              _isSendingFile ? Icons.file_upload : Icons.file_upload_outlined,
              color: _isSendingFile ? Colors.orange : Colors.white,
            ),
            tooltip: _isSendingFile ? 'Sending File...' : 'Send File via NFC',
          ),
          // File Receive Action
          IconButton(
            onPressed: (_isScanning || _isEmulating || _isSendingCard || _isSendingFile || _isReceivingFile) ? null : _startFileReception,
            icon: Icon(
              _isReceivingFile ? Icons.file_download : Icons.file_download_outlined,
              color: _isReceivingFile ? Colors.green : Colors.white,
            ),
            tooltip: _isReceivingFile ? 'Receiving File...' : 'Receive File via NFC',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status Card
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Scan Result',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          _scanResult,
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 12,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Emulation Status Card
              if (_isEmulating && _emulatingCard != null)
                Card(
                  elevation: 4,
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.nfc, color: Colors.green[700]),
                            const SizedBox(width: 8),
                            const Text(
                              'Card Emulation Active',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Emulating: ${_emulatingCard!.name}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.green[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _stopCardEmulation,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop Emulation'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_isEmulating && _emulatingCard != null)
                const SizedBox(height: 16),

              // Scan Button
              ElevatedButton.icon(
                onPressed: (_isScanning || _isEmulating || _isSendingCard) ? null : _startNFCSession,
                icon: const Icon(Icons.nfc),
                label: Text(_isEmulating ? 'Emulation Active' : _isSendingCard ? 'Sending Card...' : _isScanning ? 'Scanning...' : 'Tap to Scan NFC Card'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _isEmulating ? Colors.grey : _isSendingCard ? Colors.orange : Colors.blue,
                  disabledBackgroundColor: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),

              // P2P Status Indicator
              if (_isSendingCard && _cardToSend != null)
                Card(
                  elevation: 4,
                  color: Colors.orange[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.send, color: Colors.orange[700]),
                            const SizedBox(width: 8),
                            const Text(
                              'Sending Card via NFC',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sending: ${_cardToSend!.name}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.orange[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Bring devices close together to transfer',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFEF6C00), // Orange 600
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _stopSendingCard,
                          icon: const Icon(Icons.cancel),
                          label: const Text('Cancel Sending'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_isSendingCard && _cardToSend != null)
                const SizedBox(height: 16),

              // File Selection and Sending Section
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'File Transfer via NFC',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // File status (sending or receiving)
                      if (_selectedFile != null || _fileSendStatus.isNotEmpty || _fileReceiveStatus.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isReceivingFile ? Colors.green[50] : _isSendingFile ? Colors.orange[50] : Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _isReceivingFile ? Colors.green[200]! : _isSendingFile ? Colors.orange[200]! : Colors.blue[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _fileReceiveStatus.isNotEmpty 
                                  ? _fileReceiveStatus
                                  : _selectedFile != null 
                                    ? 'Selected: ${_selectedFile!.name} (${(_selectedFile!.size / 1024).round()} KB)'
                                    : _fileSendStatus,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _isReceivingFile ? Colors.green[800] : _isSendingFile ? Colors.orange[800] : Colors.blue[800],
                                ),
                              ),
                              if (_isSendingFile && _fileSendProgress > 0) ...[
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: _fileSendProgress,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${(_fileSendProgress * 100).round()}% complete',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      
                      if (_selectedFile != null || _fileSendStatus.isNotEmpty || _fileReceiveStatus.isNotEmpty)
                        const SizedBox(height: 12),
                      
                      // File action buttons
                      if (_isReceivingFile)
                        // Cancel reception button
                        ElevatedButton.icon(
                          onPressed: () async {
                            await NfcManager.instance.stopSession();
                            setState(() {
                              _isReceivingFile = false;
                              _fileReceiveStatus = 'File reception cancelled';
                            });
                          },
                          icon: const Icon(Icons.cancel),
                          label: const Text('Cancel Reception'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        )
                      else if (_isSendingFile)
                        // Stop sending button
                        ElevatedButton.icon(
                          onPressed: _stopFileSending,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop Sending'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: (_isScanning || _isEmulating || _isSendingCard || _isSendingFile) ? null : _pickFile,
                                icon: const Icon(Icons.file_open),
                                label: const Text('Select File'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: (_selectedFile == null || _isScanning || _isEmulating || _isSendingCard || _isSendingFile) ? null : _sendFileViaNFC,
                                icon: Icon(_isSendingFile ? Icons.send : Icons.send_outlined),
                                label: Text(_isSendingFile ? 'Sending...' : 'Send via NFC'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isSendingFile ? Colors.orange : Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      
                      const SizedBox(height: 8),
                      
                      // View received files button
                      if (!_isReceivingFile && !_isSendingFile)
                        ElevatedButton.icon(
                          onPressed: () async {
                            // Open the Downloads folder
                            try {
                              final directory = await getDownloadsDirectory();
                              if (directory != null) {
                                // On Android, we can't directly open the file manager
                                // But we can show a message with the path
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Files saved to: ${directory.path}'),
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Unable to access Downloads folder')),
                              );
                            }
                          },
                          icon: const Icon(Icons.folder_open),
                          label: const Text('View Received Files'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      const Text(
                        'Supported: Images (JPG, PNG), Documents (PDF, DOC), Text files',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Saved Cards Section
              if (_savedCards.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Saved Cards',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_savedCards.length} cards',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _savedCards.length,
                      itemBuilder: (context, index) {
                        final card = _savedCards[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                // Card Icon
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.blue[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.credit_card,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Card Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        card.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'UID: ${card.uid}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                          fontFamily: 'Courier',
                                        ),
                                      ),
                                      Text(
                                        card.tagType,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Action Buttons
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Send via NFC Button
                                    IconButton(
                                      onPressed: _isEmulating || _isSendingCard ? null : () => _sendCardViaNFC(card),
                                      icon: Icon(
                                        _isSendingCard && _cardToSend?.id == card.id
                                            ? Icons.send
                                            : Icons.send_outlined,
                                        color: _isSendingCard && _cardToSend?.id == card.id
                                            ? Colors.orange
                                            : Colors.green,
                                      ),
                                      tooltip: _isSendingCard && _cardToSend?.id == card.id
                                          ? 'Sending...'
                                          : 'Send via NFC',
                                    ),
                                    // Emulate Button
                                    IconButton(
                                      onPressed: _isEmulating || _isSendingCard ? null : () => _startCardEmulation(card),
                                      icon: Icon(
                                        _isEmulating && _emulatingCard?.id == card.id
                                            ? Icons.stop
                                            : Icons.play_arrow,
                                        color: _isEmulating && _emulatingCard?.id == card.id
                                            ? Colors.red
                                            : Colors.blue,
                                      ),
                                      tooltip: _isEmulating && _emulatingCard?.id == card.id
                                          ? 'Stop Emulating'
                                          : 'Emulate Card',
                                    ),
                                    // Delete Button
                                    IconButton(
                                      onPressed: () => _showDeleteDialog(context, card),
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      tooltip: 'Delete card',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, NFCCard card) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Card'),
          content: Text('Are you sure you want to delete "${card.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _deleteCard(card.uid);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${card.name} deleted')),
                );
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }
}

// NFC Card Model
class NFCCard {
  final String id;
  final String uid;
  final String name;
  final String tagType;
  final String? content;
  final DateTime timestamp;

  NFCCard({
    required this.id,
    required this.uid,
    required this.name,
    required this.tagType,
    this.content,
    required this.timestamp,
  });

  factory NFCCard.fromMap(Map<String, dynamic> map) {
    return NFCCard(
      id: map['id'],
      uid: map['uid'],
      name: map['name'],
      tagType: map['tagType'],
      content: map['content'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uid': uid,
      'name': name,
      'tagType': tagType,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}
