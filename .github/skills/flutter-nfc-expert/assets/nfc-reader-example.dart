import 'package:nfc_manager/nfc_manager.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:logger/logger.dart';

final logger = Logger();

/// Comprehensive NFC tag reader for Mifare and NDEF formats
class NFCReaderService {
  static final NFCReaderService _instance = NFCReaderService._internal();
  
  NFCReaderService._internal();
  
  factory NFCReaderService() {
    return _instance;
  }
  
  StreamController<NFCTagData>? _tagController;
  NfcTag? _currentTag;
  
  /// Check if device supports NFC and is enabled
  Future<bool> isNFCAvailable() async {
    try {
      return await NfcManager.instance.isAvailable();
    } catch (e) {
      logger.e("NFC availability check failed: $e");
      return false;
    }
  }
  
  /// Start NFC scanning session
  /// Returns a stream of detected tags
  Stream<NFCTagData> startScanning({
    Duration timeout = const Duration(seconds: 30),
    void Function(String)? onError,
  }) {
    _tagController = StreamController<NFCTagData>();
    
    _performScan(timeout, onError);
    
    return _tagController!.stream;
  }
  
  Future<void> _performScan(
    Duration timeout,
    void Function(String)? onError,
  ) async {
    try {
      bool isAvailable = await isNFCAvailable();
      if (!isAvailable) {
        _tagController?.addError("NFC is not available on this device");
        return;
      }
      
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          _currentTag = tag;
          logger.i("Tag discovered: ${tag.type}");
          
          try {
            final tagData = await _parseTag(tag);
            _tagController?.add(tagData);
            logger.i("Tag parsed successfully: UID=${tagData.uid}");
          } catch (e) {
            logger.e("Error parsing tag: $e");
            _tagController?.addError("Failed to parse tag: $e");
          }
        },
        pollingOptions: {
          // ISO14443 Type A (Mifare, NDEF)
          NfcPollingOption.iso14443a,
          // ISO14443 Type B
          NfcPollingOption.iso14443b,
          // NFC-F (FeliCa)
          NfcPollingOption.nfcf,
          // NFC-V (ISO15693)
          NfcPollingOption.nfcv,
        },
      );
    } catch (e) {
      logger.e("Scan session error: $e");
      _tagController?.addError("Scan failed: $e");
      onError?.call("$e");
    }
  }
  
  /// Parse NFC tag and extract data based on type
  Future<NFCTagData> _parseTag(NfcTag tag) async {
    final ndef = Ndef.from(tag);
    final iso14443a = NfcA.from(tag);
    final iso14443b = NfcB.from(tag);
    
    String uid = "";
    String tagType = tag.type.toString();
    List<NDEFRecord> records = [];
    Map<String, dynamic> rawData = {};
    
    // Extract UID (hardware identifier)
    if (iso14443a != null) {
      uid = _bytesToHex(iso14443a.identifier);
      tagType = "ISO14443A";
      
      // Attempt to detect Mifare type
      String mifareType = _detectMifareType(iso14443a);
      rawData['mifare_type'] = mifareType;
      
      logger.i("NFC-A detected - UID: $uid, Mifare Type: $mifareType");
      
      // Read Mifare data if Classic
      if (mifareType.contains("Classic")) {
        rawData['mifare_data'] = await _readMifareClassic(iso14443a);
      }
    } else if (iso14443b != null) {
      uid = _bytesToHex(iso14443b.identifier);
      tagType = "ISO14443B";
      logger.i("NFC-B detected - UID: $uid");
    }
    
    // Parse NDEF if available
    if (ndef != null && ndef.cachedMessage != null) {
      records = _parseNDEF(ndef.cachedMessage!);
      logger.i("NDEF message found with ${records.length} records");
    }
    
    return NFCTagData(
      uid: uid,
      tagType: tagType,
      ndefRecords: records,
      timestamp: DateTime.now(),
      rawData: rawData,
    );
  }
  
  /// Detect Mifare card type from ATQ (Answer To Query)
  String _detectMifareType(NfcA iso14443a) {
    final atq = iso14443a.atqa;
    final sak = iso14443a.sak;
    
    // SAK byte determines card type
    // 0x08 = Mifare Classic 1K
    // 0x18 = Mifare Classic 4K
    // 0x04 = Mifare Ultralight
    // 0x09 = Mifare Mini
    
    if (sak == 0x08) return "Mifare Classic 1K";
    if (sak == 0x18) return "Mifare Classic 4K";
    if (sak == 0x04) return "Mifare Ultralight";
    if (sak == 0x09) return "Mifare Mini";
    
    return "Unknown (SAK: ${_bytesToHex([sak])})";
  }
  
  /// Attempt to read Mifare Classic blocks (requires authentication)
  /// This is a simplified example - production code should handle sector authentication
  Future<Map<String, dynamic>> _readMifareClassic(NfcA iso14443a) async {
    try {
      final result = await iso14443a.transceive(
        data: Uint8List.fromList([
          0x30, 0x00, // READ block 0
        ]),
      );
      
      logger.i("Mifare read response: ${_bytesToHex(result)}");
      
      return {
        'block_0': _bytesToHex(result),
        'status': 'success',
      };
    } catch (e) {
      logger.w("Failed to read Mifare block: $e");
      return {'status': 'failed', 'error': '$e'};
    }
  }
  
  /// Parse NDEF message and extract records
  List<NDEFRecord> _parseNDEF(NdefMessage message) {
    final records = <NDEFRecord>[];
    
    for (final record in message.records) {
      try {
        final type = _bytesToHex(record.type);
        final payload = _bytesToHex(record.payload);
        
        NDEFRecord parsed = NDEFRecord(
          type: type,
          payload: payload,
          recordType: _identifyRecordType(record),
        );
        
        // Parse specific record types
        if (parsed.recordType == RecordType.uri) {
          parsed.decodedContent = _parseURIRecord(record.payload);
        } else if (parsed.recordType == RecordType.text) {
          parsed.decodedContent = _parseTextRecord(record.payload);
        } else if (record.typeNameFormat.index == 2) {
          // MIME type
          parsed.decodedContent = _parseString(record.payload);
          parsed.mimeType = _parseString(record.type);
        }
        
        records.add(parsed);
      } catch (e) {
        logger.w("Error parsing NDEF record: $e");
      }
    }
    
    return records;
  }
  
  /// Identify NDEF record type
  RecordType _identifyRecordType(NdefRecord record) {
    if (record.typeNameFormat.index == 1) {
      // Well-known type
      final typeStr = _parseString(record.type);
      if (typeStr == "U") return RecordType.uri;
      if (typeStr == "T") return RecordType.text;
      if (typeStr == "Sp") return RecordType.smartPoster;
    }
    return RecordType.unknown;
  }
  
  /// Parse URI record (type "U")
  /// Payload: [prefix byte] [URI string]
  String _parseURIRecord(Uint8List payload) {
    if (payload.isEmpty) return "";
    
    const uriPrefixes = [
      "",
      "http://www.",
      "https://www.",
      "http://",
      "https://",
      "tel:",
      "mailto:",
      "ftp://anonymous:anonymous@",
      "ftp://ftp.",
      "ftps://",
      "sftp://",
      "smb://",
      "nfs://",
      "ftp://",
      "urn:nfc:",
    ];
    
    int prefixIdx = payload[0] & 0xFF;
    String prefix = prefixIdx < uriPrefixes.length ? uriPrefixes[prefixIdx] : "";
    
    String uri = prefix + _parseString(payload.sublist(1));
    return uri;
  }
  
  /// Parse Text record (type "T")
  /// Payload: [status byte] [language code] [text]
  String _parseTextRecord(Uint8List payload) {
    if (payload.isEmpty) return "";
    
    int status = payload[0];
    int langLength = status & 0x3F; // Bits 0-5
    bool isUtf16 = (status & 0x80) != 0; // Bit 7
    
    String langCode = _parseString(payload.sublist(1, 1 + langLength));
    String text = _parseString(
      payload.sublist(1 + langLength),
      isUtf16: isUtf16,
    );
    
    return "$langCode: $text";
  }
  
  /// Convert bytes to hex string
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }
  
  /// Parse bytes as UTF-8 or UTF-16 string
  String _parseString(Uint8List bytes, {bool isUtf16 = false}) {
    if (isUtf16) {
      return String.fromCharCodes(
        List.generate(
          bytes.length ~/ 2,
          (i) => bytes[i * 2] | (bytes[i * 2 + 1] << 8),
        ),
      );
    }
    return String.fromCharCodes(bytes);
  }
  
  /// Stop NFC scanning session
  Future<void> stopScanning() async {
    try {
      await NfcManager.instance.stopSession();
      await _tagController?.close();
      _tagController = null;
      _currentTag = null;
      logger.i("NFC scanning stopped");
    } catch (e) {
      logger.e("Error stopping scan: $e");
    }
  }
}

// ============== Data Models ==============

/// Detected NFC tag data with parsed content
class NFCTagData {
  final String uid;
  final String tagType;
  final List<NDEFRecord> ndefRecords;
  final DateTime timestamp;
  final Map<String, dynamic> rawData;
  
  NFCTagData({
    required this.uid,
    required this.tagType,
    required this.ndefRecords,
    required this.timestamp,
    this.rawData = const {},
  });
  
  Map<String, dynamic> toJson() => {
    'uid': uid,
    'tagType': tagType,
    'ndefRecords': ndefRecords.map((r) => r.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
    'rawData': rawData,
  };
}

/// Individual NDEF record
class NDEFRecord {
  final String type;
  final String payload;
  RecordType recordType;
  String? decodedContent;
  String? mimeType;
  
  NDEFRecord({
    required this.type,
    required this.payload,
    this.recordType = RecordType.unknown,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'payload': payload,
    'recordType': recordType.toString(),
    'decodedContent': decodedContent,
    'mimeType': mimeType,
  };
}

/// NDEF record type classification
enum RecordType {
  uri,
  text,
  smartPoster,
  mimeType,
  unknown,
}
