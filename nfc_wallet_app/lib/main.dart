import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';

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

      final ndefTag = Ndef.from(tag);
      final tagData = tag.data;

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
                onPressed: (_isScanning || _isEmulating) ? null : _startNFCSession,
                icon: const Icon(Icons.nfc),
                label: Text(_isEmulating ? 'Emulation Active' : _isScanning ? 'Scanning...' : 'Tap to Scan NFC Card'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _isEmulating ? Colors.grey : Colors.blue,
                  disabledBackgroundColor: Colors.grey,
                ),
              ),
              const SizedBox(height: 24),

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
                                    // Emulate Button
                                    IconButton(
                                      onPressed: _isEmulating ? null : () => _startCardEmulation(card),
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
