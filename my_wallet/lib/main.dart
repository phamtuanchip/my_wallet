import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:my_wallet/utils/file_transfer_utils.dart';

// Card background color palette (matches Apple Wallet Business Card design)
const List<Color> kCardColors = [
  Color(0xFFE05252), // Coral Red
  Color(0xFFE8677A), // Pink
  Color(0xFFE5844A), // Orange
  Color(0xFFD4A837), // Amber
  Color(0xFF4CAF7D), // Green
  Color(0xFF4A90D9), // Blue
  Color(0xFF7B68D9), // Purple
  Color(0xFF2C2C2E), // Dark (default)
];

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      themeMode: ThemeMode.system,
      home: const NFCScannerScreen(),
    );
  }
}

class NFCScannerScreen extends StatefulWidget {
  const NFCScannerScreen({super.key});

  @override
  State<NFCScannerScreen> createState() => _NFCScannerScreenState();
}

class _NFCScannerScreenState extends State<NFCScannerScreen>
    with TickerProviderStateMixin {
  final logger = Logger();
  String _scanResult = 'Tap card to scan';
  bool _isScanning = false;
  List<NFCCard> _savedCards = [];
  Database? _database;
  NFCCard? _emulatingCard;
  bool _isEmulating = false;
  bool _isSendingCard = false;
  NFCCard? _cardToSend;
  String? _expandedCardId;
  int _currentIndex = 0;
  int _selectedTabIndex = 0;

  // File selection state
  PlatformFile? _selectedFile;
  bool _isSendingFile = false;
  double _fileSendProgress = 0.0;
  String _fileSendStatus = '';
  bool _isReceivingFile = false;
  double _fileReceiveProgress = 0.0;
  String _fileReceiveStatus = '';
  bool _isFileReceiveDialogOpen = false;

  static const platform = MethodChannel('com.example.my_wallet/hce');

  // Animation controller for NFC scan pulse
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initDatabase();
    _checkNFCAvailability();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'nfc_wallet.db');

    _database = await openDatabase(
      path,
      version: 2,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE cards (
            id TEXT PRIMARY KEY,
            uid TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            tagType TEXT NOT NULL,
            content TEXT,
            timestamp INTEGER NOT NULL,
            color INTEGER NOT NULL DEFAULT 7
          )
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE cards ADD COLUMN color INTEGER NOT NULL DEFAULT 7');
        }
      },
    );

    await _loadSavedCards();
  }

  Future<void> _loadSavedCards() async {
    if (_database == null) return;

    final List<Map<String, dynamic>> maps =
        await _database!.query('cards', orderBy: 'timestamp DESC');
    setState(() {
      _savedCards = List.generate(maps.length, (i) {
        return NFCCard.fromMap(maps[i]);
      });
    });
  }

  Future<void> _saveCard(String uid, String tagType, String content) async {
    if (_database == null) return;

    final existingCards = await _database!.query(
      'cards',
      where: 'uid = ?',
      whereArgs: [uid],
    );

    if (existingCards.isNotEmpty) {
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
      final nextNumber = _savedCards.length + 1;
      final cardName = 'Card $nextNumber';
      final colorIndex = _savedCards.length % kCardColors.length;

      await _database!.insert(
        'cards',
        {
          'id': const Uuid().v4(),
          'uid': uid,
          'name': cardName,
          'tagType': tagType,
          'content': content,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'color': colorIndex,
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
    if (_expandedCardId == uid) {
      setState(() {
        _expandedCardId = null;
      });
    }
    logger.i('Deleted card with UID: $uid');
  }

  Future<void> _editCardName(NFCCard card) async {
    final controller = TextEditingController(text: card.name);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Edit Card Name'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Card name',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  _updateCardName(card, newName);
                }
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateCardName(NFCCard card, String newName) async {
    if (_database == null) return;
    await _database!.update(
      'cards',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [card.id],
    );
    await _loadSavedCards();
  }

  Future<void> _updateCardColor(NFCCard card, int colorIndex) async {
    if (_database == null) return;
    await _database!.update(
      'cards',
      {'color': colorIndex},
      where: 'id = ?',
      whereArgs: [card.id],
    );
    await _loadSavedCards();
  }

  Future<void> _startCardEmulation(NFCCard card) async {
    try {
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

      logger.i('Started emulating card: ${card.name}, result: $result');
    } on PlatformException catch (e) {
      logger.e('Platform exception starting card emulation: ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Failed to start card emulation: ${e.message}')),
        );
      }
    } catch (e) {
      logger.e('Error starting card emulation: $e');
    }
  }

  Future<void> _stopCardEmulation() async {
    try {
      await platform.invokeMethod('stopCardEmulation');
    } on PlatformException catch (e) {
      logger.e('Platform exception stopping card emulation: ${e.message}');
    } catch (e) {
      logger.e('Error stopping card emulation: $e');
    } finally {
      setState(() {
        _emulatingCard = null;
        _isEmulating = false;
      });
    }
  }

  Future<void> _sendCardViaNFC(NFCCard card) async {
    if (_isSendingCard) return;

    setState(() {
      _isSendingCard = true;
      _cardToSend = card;
    });

    try {
      final cardData = {
        'id': card.id,
        'uid': card.uid,
        'name': card.name,
        'tagType': card.tagType,
        'content': card.content,
        'timestamp': card.timestamp.millisecondsSinceEpoch,
        'type': 'nfc_wallet_card',
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

      await _startP2PSession(ndefMessage);
    } catch (e) {
      logger.e('Error preparing card for P2P: $e');
      await _stopSendingCard();
    }
  }

  Future<void> _startP2PSession(NdefMessage message) async {
    try {
      logger.i('Starting P2P card transfer session');
      
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          logger.i('Device/tag discovered during card transfer');
          final ndefTag = Ndef.from(tag);
          if (ndefTag != null && ndefTag.isWritable) {
            try {
              logger.i('Writing card to writable NDEF tag');
              await ndefTag.write(message);
              await NfcManager.instance.stopSession();
              logger.i('Card transfer completed successfully');
              
              setState(() {
                _isSendingCard = false;
                _cardToSend = null;
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Card shared successfully!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            } catch (e) {
              logger.e('Error writing to peer device: $e');
              setState(() {
                _isSendingCard = false;
                _cardToSend = null;
              });
            }
          } else {
            logger.i('Discovered tag is not writable NDEF, attempting to read as normal tag');
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
    } catch (_) {}
    setState(() {
      _isSendingCard = false;
      _cardToSend = null;
    });
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg', 'jpeg', 'png', 'gif', 'pdf', 'txt', 'doc', 'docx'
        ],
        allowMultiple: false,
      );

      if (result != null) {
        setState(() {
          _selectedFile = result.files.first;
          _fileSendStatus = 'File selected: ${_selectedFile!.name}';
        });
      }
    } catch (e) {
      logger.e('Error picking file: $e');
    }
  }

  Future<void> _sendFileViaNFC() async {
    if (_selectedFile == null) return;

    try {
      setState(() {
        _isSendingFile = true;
        _fileSendStatus = 'Preparing file for sending...';
      });

      Uint8List fileData;
      if (_selectedFile!.bytes != null) {
        fileData = _selectedFile!.bytes!;
      } else if (_selectedFile!.path != null) {
        fileData = await File(_selectedFile!.path!).readAsBytes();
      } else {
        throw Exception('Unable to read file data');
      }

      final fileMetadata = {
        'name': _selectedFile!.name,
        'size': _selectedFile!.size,
        'extension': _selectedFile!.extension,
        'type': 'nfc_wallet_file',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final ndefMessage = NdefMessage([
        NdefRecord(
          typeNameFormat: NdefTypeNameFormat.media,
          type: Uint8List.fromList('application/json'.codeUnits),
          identifier: Uint8List(0),
          payload: Uint8List.fromList(jsonEncode(fileMetadata).codeUnits),
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
        _fileSendStatus = 'Error: $e';
      });
    }
  }

  Future<void> _startFileP2PSession(NdefMessage message) async {
    try {
      setState(() {
        _fileSendStatus =
            'Starting file transfer... Receiver must tap Receive and confirm';
        _fileSendProgress = 0.1;
      });

      logger.i('Starting P2P file transfer session');
      bool fileTransferred = false;
      
      // Use multiple polling options for better P2P device discovery
      // iso14443: For Type A/B cards and general NFC
      // Using iso14443 for P2P device-to-device communication
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
        },
        onDiscovered: (NfcTag tag) async {
          if (fileTransferred) return;
          
          try {
            setState(() => _fileSendProgress = 0.3);
            logger.i('Device discovered, attempting file transfer');
            
            try {
              final ndefTag = Ndef.from(tag);
              if (ndefTag != null && ndefTag.isWritable) {
                setState(() {
                  _fileSendProgress = 0.5;
                  _fileSendStatus = 'Transferring file...';
                });
                logger.i('Writing file to peer device');
                
                await ndefTag.write(message);
                fileTransferred = true;
                
                await NfcManager.instance.stopSession();
                final name = _selectedFile?.name;
                
                setState(() {
                  _fileSendStatus = 'File sent successfully: $name';
                  _isSendingFile = false;
                  _selectedFile = null;
                  _fileSendProgress = 1.0;
                });
                
                logger.i('File transfer completed: $name');
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('File "$name" sent successfully!'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } else {
                logger.w('Tag is not NDEF writable or is null');
                if (ndefTag != null) {
                  logger.i('Tag type: ${ndefTag.runtimeType}, Writable: ${ndefTag.isWritable}');
                }
              }
            } catch (tagError) {
              logger.w('Error processing tag during file transfer: $tagError');
            }
          } catch (e) {
            logger.e('Error writing file to peer device: $e');
            setState(() {
              _fileSendStatus = 'Error transferring file: $e';
              _isSendingFile = false;
              _fileSendProgress = 0.0;
            });
          }
        },
      );
    } catch (e) {
      logger.e('Error starting file P2P session: $e');
      setState(() {
        _isSendingFile = false;
        _fileSendStatus = 'Error starting transfer: $e. Make sure both phones have NFC enabled and are close together.';
        _fileSendProgress = 0.0;
      });
    }
  }

  Future<void> _stopFileSending() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    setState(() {
      _isSendingFile = false;
      _fileSendStatus = 'File sending cancelled';
      _fileSendProgress = 0.0;
    });
  }

  Future<void> _startFileReception() async {
    try {
      final canSave = await _ensureFileSavePermission();
      if (!canSave) {
        setState(() {
          _isReceivingFile = false;
          _fileReceiveProgress = 0.0;
          _fileReceiveStatus =
              'Storage permission denied. Cannot receive files.';
        });
        return;
      }

      setState(() {
        _isReceivingFile = true;
        _fileReceiveProgress = 0.05;
        _fileReceiveStatus =
            'Waiting for file transfer... Touch sender device to receive';
      });

      logger.i('Starting file reception session');
      
      // Use same polling options as sender for proper P2P discovery
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          logger.i('Tag discovered during file reception');
          setState(() {
            _fileReceiveProgress = 0.2;
            _fileReceiveStatus = 'Sender detected. Reading data...';
          });
          await _handleFileReception(tag);
        },
      );
    } catch (e) {
      logger.e('Error starting file reception: $e');
      setState(() {
        _isReceivingFile = false;
        _fileReceiveProgress = 0.0;
        _fileReceiveStatus = 'Error starting reception: $e. Make sure NFC is enabled.';
      });
    }
  }

  Future<void> _stopFileReception() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}

    setState(() {
      _isReceivingFile = false;
      _fileReceiveProgress = 0.0;
      _fileReceiveStatus = 'File reception cancelled';
    });
  }

  Future<bool> _ensureFileSavePermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final status = await Permission.storage.status;
      if (status.isGranted) return true;

      final requested = await Permission.storage.request();
      if (requested.isGranted) return true;

      final manage = await Permission.manageExternalStorage.request();
      return manage.isGranted;
    } catch (e) {
      logger.w('Permission request failed, fallback to app storage only: $e');
      return true;
    }
  }

  Future<bool> _confirmIncomingFile(Map<String, dynamic> metadata) async {
    if (!mounted || _isFileReceiveDialogOpen) return false;

    _isFileReceiveDialogOpen = true;
    final fileName = metadata['name']?.toString() ?? 'unknown';
    final fileSize = metadata['size'] is int ? metadata['size'] as int : 0;
    final fileExt = metadata['extension']?.toString() ?? 'unknown';

    final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              title: const Text('Incoming NFC File'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Name: $fileName'),
                  const SizedBox(height: 6),
                  Text('Type: .$fileExt'),
                  const SizedBox(height: 6),
                  Text('Size: ${formatFileSize(fileSize)}'),
                  const SizedBox(height: 12),
                  const Text('Do you want to receive this file?'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Decline'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Accept'),
                ),
              ],
            );
          },
        ) ??
        false;

    _isFileReceiveDialogOpen = false;
    return accepted;
  }

  Future<void> _handleFileReception(NfcTag tag,
      {bool autoStopSession = true}) async {
    try {
      if (!_isReceivingFile) {
        logger.i('Ignoring file transfer because receive mode is not active');
        return;
      }

      logger.i('Processing received tag for file content');
      final ndefTag = Ndef.from(tag);
      
      if (ndefTag == null) {
        logger.w('Tag is not NDEF formatted');
        setState(() {
          _fileReceiveProgress = 0.0;
          _fileReceiveStatus = 'Received tag is not NDEF formatted';
          _isReceivingFile = false;
        });
        return;
      }
      
      if (ndefTag.cachedMessage == null) {
        logger.w('NDEF tag has no cached message');
        setState(() {
          _fileReceiveProgress = 0.0;
          _fileReceiveStatus = 'Received NDEF tag is empty';
          _isReceivingFile = false;
        });
        return;
      }

      final records = ndefTag.cachedMessage!.records;
      logger.i('Received NDEF message with ${records.length} records');
      
      if (records.isEmpty) {
        logger.w('Received empty NDEF message');
        setState(() {
          _fileReceiveProgress = 0.0;
          _fileReceiveStatus = 'Received empty NDEF message';
          _isReceivingFile = false;
        });
        return;
      }
      
      if (records.length < 2) {
        logger.w('Incomplete NDEF records: ${records.length} records');
        setState(() {
          _fileReceiveProgress = 0.0;
          _fileReceiveStatus = 'Incomplete file data received';
          _isReceivingFile = false;
        });
        return;
      }

      final metadataRecord = records[0];
      logger.i('Processing metadata record: ${metadataRecord.typeNameFormat}');
      
      if (metadataRecord.typeNameFormat == NdefTypeNameFormat.media &&
          String.fromCharCodes(metadataRecord.type) == 'application/json') {
        try {
          setState(() {
            _fileReceiveProgress = 0.35;
          });
          final metadataJson = String.fromCharCodes(metadataRecord.payload);
          logger.i('File metadata: $metadataJson');
          
          final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
          
          if (metadata['type'] == 'nfc_wallet_file') {
            logger.i('File transfer detected: ${metadata['name']}');
            final fileData = records[1].payload;

            setState(() {
              _fileReceiveProgress = 0.5;
              _fileReceiveStatus =
                  'Incoming file detected: ${metadata['name']} (waiting for confirmation)';
            });

            final shouldReceive = await _confirmIncomingFile(metadata);
            if (!shouldReceive) {
              setState(() {
                _fileReceiveProgress = 0.0;
                _fileReceiveStatus =
                    'File transfer declined: ${metadata['name']}';
                _isReceivingFile = false;
              });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Incoming file declined'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }

              if (autoStopSession) {
                await NfcManager.instance.stopSession();
              }
              return;
            }
            
            setState(() {
              _fileReceiveProgress = 0.75;
              _fileReceiveStatus = 'Saving file: ${metadata['name']}';
            });
            
            final savedPath = await _saveReceivedFile(metadata, fileData);
            
            setState(() {
              _fileReceiveProgress = 1.0;
              _fileReceiveStatus = 'File received successfully: ${metadata['name']}';
              _isReceivingFile = false;
            });
            
            logger.i('File received and saved: ${metadata['name']} at $savedPath');
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('File "${metadata['name']}" saved to $savedPath'),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          } else {
            logger.w('Received NDEF message is not a file transfer');
            setState(() {
              _fileReceiveProgress = 0.0;
              _fileReceiveStatus = 'Received data is not a file transfer';
              _isReceivingFile = false;
            });
          }
        } catch (e) {
          logger.e('Error parsing file metadata: $e');
          rethrow;
        }
      } else {
        logger.w('First record is not JSON metadata');
        setState(() {
          _fileReceiveProgress = 0.0;
          _fileReceiveStatus = 'Invalid file transfer format';
          _isReceivingFile = false;
        });
      }

      if (autoStopSession) {
        try {
          await NfcManager.instance.stopSession();
          logger.i('NFC session stopped');
        } catch (e) {
          logger.w('Error stopping NFC session: $e');
        }
      }
    } catch (e) {
      logger.e('Error processing received file: $e');
      setState(() {
        _fileReceiveProgress = 0.0;
        _fileReceiveStatus = 'Error processing file: $e';
        _isReceivingFile = false;
      });
    }
  }

  Future<String> _saveReceivedFile(
      Map<String, dynamic> metadata, Uint8List fileData) async {
    final directory = await _resolveReceiveDirectory();

    final originalName = metadata['name'] as String;
    final extension = metadata['extension'] as String? ?? '';
    final fileName = await buildUniqueFileName(directory.path, originalName,
        fallbackExtension: extension.isNotEmpty ? extension : 'bin');

    final filePath = p.join(directory.path, fileName);
    await File(filePath).writeAsBytes(fileData, flush: true);
    logger.i('File saved: $filePath');
    return filePath;
  }

  Future<Directory> _resolveReceiveDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        await downloads.create(recursive: true);
        return downloads;
      }
    } catch (e) {
      logger.w('Downloads directory unavailable: $e');
    }

    if (Platform.isAndroid) {
      try {
        final external = await getExternalStorageDirectory();
        if (external != null) {
          final receivedDir = Directory(p.join(external.path, 'ReceivedFiles'));
          await receivedDir.create(recursive: true);
          return receivedDir;
        }
      } catch (e) {
        logger.w('External storage fallback unavailable: $e');
      }
    }

    final docs = await getApplicationDocumentsDirectory();
    final fallback = Directory(p.join(docs.path, 'ReceivedFiles'));
    await fallback.create(recursive: true);
    return fallback;
  }

  Future<void> _receiveCardViaNFC(NfcTag tag) async {
    try {
      final ndefTag = Ndef.from(tag);
      if (ndefTag == null || ndefTag.cachedMessage == null) return;

      for (final record in ndefTag.cachedMessage!.records) {
        try {
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
      final cardData = jsonDecode(jsonString) as Map<String, dynamic>;
      final uid = cardData['uid']?.toString() ??
          const Uuid().v4().substring(0, 8);
      final tagType =
          cardData['tagType']?.toString() ?? 'Received via NFC';
      final content = cardData['content']?.toString() ?? '';
      await _saveCard(uid, tagType, content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Card "${cardData['name']}" received and saved!')),
        );
      }
    } catch (e) {
      logger.e('Error processing received card data: $e');
    }
  }

  Future<void> _checkNFCAvailability() async {
    try {
      final isAvailable = await NfcManager.instance.isAvailable();
      setState(() {
        _scanResult = isAvailable
            ? 'NFC Ready — tap + to scan'
            : 'NFC not available on this device';
      });
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
      _scanResult = 'Scanning... Bring card or device close';
    });

    try {
      logger.i('Starting NFC scan session');
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          logger.i('Tag discovered during NFC scan');
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

      if (_isReceivingFile) {
        await _handleFileReception(tag, autoStopSession: false);
        return;
      }

      await _receiveCardViaNFC(tag);

      final ndefTag = Ndef.from(tag);
      final tagData = tag.data;

      String uid = '';
      String tagType = 'Unknown';
      String content = '';

      if (tagData.containsKey('nfca')) {
        final nfcaData = tagData['nfca'] as Map<dynamic, dynamic>? ?? {};
        uid = _bytesToHex(nfcaData['identifier'] as List<int>? ?? []);
        tagType = 'NFC Type A';
        final sak = nfcaData['sak'] as int? ?? 0;
        if (sak == 0x08) {
          tagType = 'Mifare Classic 1K';
        } else if (sak == 0x18) {
          tagType = 'Mifare Classic 4K';
        } else if (sak == 0x04) {
          tagType = 'Mifare Ultralight';
        } else if (sak == 0x09) {
          tagType = 'Mifare Mini';
        }
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

      if (ndefTag != null && ndefTag.cachedMessage != null) {
        tagType += ' (NDEF)';
        for (var record in ndefTag.cachedMessage!.records) {
          try {
            final recordType = _parseString(record.type);
            final payload = _bytesToHex(record.payload);
            content +=
                '$recordType: ${payload.substring(0, payload.length < 40 ? payload.length : 40)}\n';
          } catch (e) {
            logger.w('Error parsing record: $e');
          }
        }
      }

      if (uid.isNotEmpty) {
        await _saveCard(uid, tagType, content);
        setState(() {
          _scanResult = 'Card saved!\nUID: $uid\nType: $tagType';
        });
      } else {
        setState(() {
          _scanResult = 'Scanned — no UID\nType: $tagType';
        });
      }

      setState(() => _isScanning = false);
    } catch (e) {
      logger.e('Error handling tag: $e');
      setState(() {
        _scanResult = 'Error: $e';
        _isScanning = false;
      });
    }
  }

  String _bytesToHex(List<int> bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('')
        .toUpperCase();
  }

  String _parseString(List<int> bytes) {
    try {
      return String.fromCharCodes(bytes);
    } catch (e) {
      return _bytesToHex(bytes);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // UI BUILD METHODS — Apple Wallet–inspired design
  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? Colors.black : const Color(0xFFF2F2F7),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: _buildBottomNav(isDark),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.wallet_outlined, Icons.wallet, 'Wallet', isDark),
              _navItem(
                  1, Icons.credit_card_outlined, Icons.credit_card, 'Cards', isDark),
              _navItem(
                  2, Icons.settings_outlined, Icons.settings, 'Settings', isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon,
      String label, bool isDark) {
    final isActive = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive
                  ? const Color(0xFF007AFF)
                  : (isDark ? Colors.white38 : Colors.black38),
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive
                    ? const Color(0xFF007AFF)
                    : (isDark ? Colors.white38 : Colors.black38),
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildWalletView();
      case 1:
        return _buildCardsView();
      case 2:
        return _buildSettingsView();
      default:
        return _buildWalletView();
    }
  }

  // ── WALLET TAB ──────────────────────────────────────────────────

  Widget _buildWalletView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Wallet',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                GestureDetector(
                  onTap: (_isScanning ||
                          _isEmulating ||
                          _isSendingCard ||
                          _isSendingFile ||
                          _isReceivingFile)
                      ? null
                      : _startNFCSession,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: (_isScanning || _isEmulating || _isSendingCard)
                          ? Colors.grey.shade400
                          : const Color(0xFF007AFF),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      _isScanning ? Icons.sensors : Icons.add,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Emulation banner
        if (_isEmulating && _emulatingCard != null)
          SliverToBoxAdapter(
            child: _buildEmulationBanner(isDark),
          ),

        // Scanning banner
        if (_isScanning)
          SliverToBoxAdapter(
            child: _buildScanningBanner(isDark),
          ),

        // Sending card banner
        if (_isSendingCard && _cardToSend != null)
          SliverToBoxAdapter(
            child: _buildSendingCardBanner(isDark),
          ),

        // Cards stack or empty state
        if (_savedCards.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildWalletStack(isDark),
          )
        else
          SliverFillRemaining(
            child: _buildEmptyState(isDark),
          ),

        // Scan button (only when cards exist)
        if (_savedCards.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: _buildScanButton(),
            ),
          ),
      ],
    );
  }

  Widget _buildEmulationBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF34C759).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF34C759).withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: const Icon(Icons.nfc,
                color: Color(0xFF34C759), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Card Emulation Active',
                  style: TextStyle(
                    color: Color(0xFF34C759),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  _emulatingCard!.name,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _stopCardEmulation,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Stop',
                style: TextStyle(
                  color: Color(0xFFFF3B30),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF007AFF).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF007AFF).withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: const Icon(Icons.nfc,
                color: Color(0xFF007AFF), size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Hold NFC card near device…',
              style: TextStyle(
                color: Color(0xFF007AFF),
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              try {
                await NfcManager.instance.stopSession();
              } catch (_) {}
              setState(() => _isScanning = false);
            },
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFFFF3B30),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendingCardBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF5856D6).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF5856D6).withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: const Icon(Icons.ios_share,
                color: Color(0xFF5856D6), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sharing Card…',
                  style: TextStyle(
                    color: Color(0xFF5856D6),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Hold devices together — ${_cardToSend!.name}',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _stopSendingCard,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFFFF3B30),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletStack(bool isDark) {
    final cards = _savedCards;
    const double cardHeight = 200.0;
    const double stackOffset = 28.0;
    final totalHeight =
        cardHeight + (cards.length - 1) * stackOffset + 32.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: SizedBox(
        height: totalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: List.generate(cards.length, (i) {
            final card = cards[cards.length - 1 - i];
            final topOffset = i * stackOffset;
            final isTop = i == cards.length - 1;
            return Positioned(
              top: topOffset,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  if (isTop) {
                    _showCardBottomSheet(card);
                  } else {
                    setState(() {
                      _savedCards.remove(card);
                      _savedCards.insert(0, card);
                    });
                  }
                },
                child: _buildWalletCard(card, isTop: isTop),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildWalletCard(NFCCard card, {bool isTop = false}) {
    final cardColor =
        kCardColors[card.colorIndex % kCardColors.length];
    final darkerColor = HSLColor.fromColor(cardColor)
        .withLightness(
            (HSLColor.fromColor(cardColor).lightness - 0.12)
                .clamp(0.0, 1.0))
        .toColor();

    final initials = card.name.trim().isEmpty
        ? '?'
        : card.name
            .trim()
            .split(' ')
            .map((w) => w.isNotEmpty ? w[0] : '')
            .take(2)
            .join()
            .toUpperCase();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [cardColor, darkerColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: isTop
            ? [
                BoxShadow(
                  color: cardColor.withValues(alpha: 0.45),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar circle
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.nfc,
                    color: Colors.white60, size: 22),
              ],
            ),
            const Spacer(),
            Text(
              card.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              card.tagType,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.wallet_outlined,
          size: 72,
          color: isDark ? Colors.white24 : Colors.black12,
        ),
        const SizedBox(height: 16),
        Text(
          'No Cards Yet',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap the + button to scan an NFC card\nand add it to your wallet',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white54 : Colors.black45,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 36),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: _buildScanButton(),
        ),
      ],
    );
  }

  Widget _buildScanButton() {
    final busy = _isScanning || _isEmulating || _isSendingCard;
    return GestureDetector(
      onTap: busy ? null : _startNFCSession,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: busy ? Colors.grey.shade400 : const Color(0xFF007AFF),
          borderRadius: BorderRadius.circular(16),
          boxShadow: busy
              ? []
              : [
                  BoxShadow(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isScanning ? Icons.sensors : Icons.nfc,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              _isScanning ? 'Scanning…' : 'Scan NFC Card',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── CARD DETAIL BOTTOM SHEET ────────────────────────────────────

  void _showCardBottomSheet(NFCCard card) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CardBottomSheet(
        card: card,
        isEmulating: _isEmulating,
        emulatingCard: _emulatingCard,
        onEmulate: () {
          Navigator.pop(context);
          if (_isEmulating && _emulatingCard?.id == card.id) {
            _stopCardEmulation();
          } else {
            _startCardEmulation(card);
          }
        },
        onShare: () {
          Navigator.pop(context);
          _sendCardViaNFC(card);
        },
        onEdit: () async {
          Navigator.pop(context);
          await _editCardName(card);
        },
        onColorChange: (colorIndex) {
          _updateCardColor(card, colorIndex);
        },
        onDelete: () {
          Navigator.pop(context);
          _showDeleteConfirmation(card);
        },
      ),
    );
  }

  void _showDeleteConfirmation(NFCCard card) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Card',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Delete "${card.name}" from your wallet?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _deleteCard(card.uid);
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF3B30)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── CARDS TAB ────────────────────────────────────────────────────

  Widget _buildCardsView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_savedCards.isEmpty) {
      return Center(
        child: Text(
          'No cards yet.\nScan an NFC card to add it.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: isDark ? Colors.white54 : Colors.black45,
            height: 1.6,
          ),
        ),
      );
    }

    final safeIndex = _currentIndex.clamp(0, _savedCards.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Text(
            'Cards',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            itemCount: _savedCards.length,
            controller: PageController(
              initialPage: safeIndex,
              viewportFraction: 0.88,
            ),
            onPageChanged: (index) =>
                setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              final card = _savedCards[index];
              final isSelected = index == safeIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: isSelected ? 12 : 28,
                ),
                child: GestureDetector(
                  onTap: () => _showCardBottomSheet(card),
                  child: _buildWalletCard(card, isTop: isSelected),
                ),
              );
            },
          ),
        ),
        _buildCardDetailsPanel(_savedCards[safeIndex], isDark),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCardDetailsPanel(NFCCard card, bool isDark) {
    final isThisEmulating =
        _isEmulating && _emulatingCard?.id == card.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              card.tagType,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'UID: ${card.uid}',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Courier',
                color: isDark ? Colors.white30 : Colors.black26,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _actionChip(
                  icon: isThisEmulating ? Icons.nfc : Icons.contactless,
                  label: isThisEmulating ? 'Stop' : 'Emulate',
                  color: isThisEmulating
                      ? const Color(0xFF34C759)
                      : const Color(0xFF007AFF),
                  onTap: () {
                    if (isThisEmulating) {
                      _stopCardEmulation();
                    } else {
                      _startCardEmulation(card);
                    }
                  },
                  isDark: isDark,
                ),
                const SizedBox(width: 10),
                _actionChip(
                  icon: Icons.ios_share,
                  label: 'Share',
                  color: const Color(0xFF007AFF),
                  onTap: () => _sendCardViaNFC(card),
                  isDark: isDark,
                ),
                const SizedBox(width: 10),
                _actionChip(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: const Color(0xFFFF3B30),
                  onTap: () => _showDeleteConfirmation(card),
                  isDark: isDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── SETTINGS TAB ─────────────────────────────────────────────────

  Widget _buildSettingsView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Text(
          'Settings',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 28),

        _settingsSection(
          title: 'NFC',
          isDark: isDark,
          children: [
            _settingsRow(
              icon: Icons.nfc,
              iconColor: const Color(0xFF007AFF),
              title: 'Scan NFC Card',
              subtitle: _scanResult,
              isDark: isDark,
              trailing: GestureDetector(
                onTap: (_isScanning || _isEmulating)
                    ? null
                    : _startNFCSession,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: (_isScanning || _isEmulating)
                        ? Colors.grey.withValues(alpha: 0.2)
                        : const Color(0xFF007AFF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _isScanning ? 'Scanning…' : 'Scan',
                    style: TextStyle(
                      color: (_isScanning || _isEmulating)
                          ? Colors.grey
                          : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        _settingsSection(
          title: 'File Transfer',
          isDark: isDark,
          children: [
            _settingsRow(
              icon: Icons.upload_file,
              iconColor: const Color(0xFFFF9500),
              title: 'Send File via NFC',
              subtitle: _isSendingFile
                  ? _fileSendStatus
                  : (_selectedFile != null ? _selectedFile!.name : 'No file selected'),
              isDark: isDark,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedFile != null)
                    GestureDetector(
                      onTap: _isSendingFile
                          ? _stopFileSending
                          : _sendFileViaNFC,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: _isSendingFile
                              ? const Color(0xFFFF3B30).withValues(alpha: 0.15)
                              : const Color(0xFF007AFF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _isSendingFile ? 'Cancel' : 'Send',
                          style: TextStyle(
                            color: _isSendingFile
                                ? const Color(0xFFFF3B30)
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: _pickFile,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFFFF9500).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Pick',
                        style: TextStyle(
                          color: Color(0xFFFF9500),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isSendingFile)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: LinearProgressIndicator(
                  value: _fileSendProgress,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor:
                      isDark ? Colors.white12 : Colors.black12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF9500)),
                ),
              ),
            _settingsRow(
              icon: Icons.download,
              iconColor: const Color(0xFF34C759),
              title: 'Receive File via NFC',
              subtitle: _isReceivingFile
                  ? _fileReceiveStatus
                  : 'Tap to start receiving',
              isDark: isDark,
              trailing: GestureDetector(
                onTap: _isReceivingFile ? _stopFileReception : _startFileReception,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _isReceivingFile
                        ? const Color(0xFF34C759).withValues(alpha: 0.15)
                        : const Color(0xFF34C759),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _isReceivingFile ? 'Cancel' : 'Receive',
                    style: TextStyle(
                      color: _isReceivingFile
                          ? const Color(0xFF34C759)
                          : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
            if (_isReceivingFile)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: LinearProgressIndicator(
                  value: _fileReceiveProgress,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor:
                      isDark ? Colors.white12 : Colors.black12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF34C759)),
                ),
              ),
          ],
        ),

        const SizedBox(height: 20),

        _settingsSection(
          title: 'About',
          isDark: isDark,
          children: [
            _settingsRow(
              icon: Icons.info_outline,
              iconColor: const Color(0xFF007AFF),
              title: 'My Wallet',
              subtitle: 'NFC Business Card Wallet v1.0',
              isDark: isDark,
            ),
            _settingsRow(
              icon: Icons.credit_card,
              iconColor: const Color(0xFF5856D6),
              title: 'Cards Stored',
              subtitle:
                  '${_savedCards.length} card${_savedCards.length == 1 ? '' : 's'}',
              isDark: isDark,
            ),
          ],
        ),
      ],
    );
  }

  Widget _settingsSection({
    required String title,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white38 : Colors.black38,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    indent: 56,
                    endIndent: 16,
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isDark,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing,
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// CARD BOTTOM SHEET  (Apple Wallet "Add to Wallet" style)
// ─────────────────────────────────────────────────────────────────

class _CardBottomSheet extends StatefulWidget {
  final NFCCard card;
  final bool isEmulating;
  final NFCCard? emulatingCard;
  final VoidCallback onEmulate;
  final VoidCallback onShare;
  final VoidCallback onEdit;
  final ValueChanged<int> onColorChange;
  final VoidCallback onDelete;

  const _CardBottomSheet({
    required this.card,
    required this.isEmulating,
    required this.emulatingCard,
    required this.onEmulate,
    required this.onShare,
    required this.onEdit,
    required this.onColorChange,
    required this.onDelete,
  });

  @override
  State<_CardBottomSheet> createState() => _CardBottomSheetState();
}

class _CardBottomSheetState extends State<_CardBottomSheet> {
  late int _selectedColorIndex;

  @override
  void initState() {
    super.initState();
    _selectedColorIndex = widget.card.colorIndex % kCardColors.length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = kCardColors[_selectedColorIndex];
    final darkerColor = HSLColor.fromColor(cardColor)
        .withLightness(
            (HSLColor.fromColor(cardColor).lightness - 0.12).clamp(0.0, 1.0))
        .toColor();
    final isThisEmulating =
        widget.isEmulating && widget.emulatingCard?.id == widget.card.id;

    final initials = widget.card.name.trim().isEmpty
        ? '?'
        : widget.card.name
            .trim()
            .split(' ')
            .map((w) => w.isNotEmpty ? w[0] : '')
            .take(2)
            .join()
            .toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Cancel / Add to Wallet header (Apple Wallet style)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Color(0xFFFF3B30),
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              GestureDetector(
                onTap: widget.onEmulate,
                child: Text(
                  isThisEmulating ? 'Stop' : 'Hold Near Reader',
                  style: const TextStyle(
                    color: Color(0xFF007AFF),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Card preview
          Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [cardColor, darkerColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: cardColor.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.nfc,
                        color: Colors.white60, size: 22),
                  ],
                ),
                const Spacer(),
                Text(
                  widget.card.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Background color section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Background',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: kCardColors.length,
              itemBuilder: (context, i) {
                final isSelected = i == _selectedColorIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedColorIndex = i);
                    widget.onColorChange(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: kCardColors[i],
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color:
                                  isDark ? Colors.white : Colors.black87,
                              width: 2.5)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: kCardColors[i].withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: isSelected
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 20)
                        : null,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons row
          Row(
            children: [
              Expanded(
                child: _SheetButton(
                  icon: Icons.ios_share,
                  label: 'Share',
                  backgroundColor: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFF2F2F7),
                  textColor: isDark ? Colors.white : Colors.black,
                  onTap: widget.onShare,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit Name',
                  backgroundColor: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFF2F2F7),
                  textColor: isDark ? Colors.white : Colors.black,
                  onTap: widget.onEdit,
                ),
              ),
              const SizedBox(width: 10),
              _SheetButton(
                icon: Icons.delete_outline,
                label: '',
                backgroundColor:
                    const Color(0xFFFF3B30).withValues(alpha: 0.12),
                textColor: const Color(0xFFFF3B30),
                onTap: widget.onDelete,
                iconOnly: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onTap;
  final bool iconOnly;

  const _SheetButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
    this.iconOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        width: iconOnly ? 52 : null,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: 20),
            if (!iconOnly && label.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// NFC CARD MODEL
// ─────────────────────────────────────────────────────────────────

class NFCCard {
  final String id;
  final String uid;
  final String name;
  final String tagType;
  final String? content;
  final DateTime timestamp;
  final int colorIndex;

  NFCCard({
    required this.id,
    required this.uid,
    required this.name,
    required this.tagType,
    this.content,
    required this.timestamp,
    this.colorIndex = 7,
  });

  factory NFCCard.fromMap(Map<String, dynamic> map) {
    return NFCCard(
      id: map['id'] as String,
      uid: map['uid'] as String,
      name: map['name'] as String,
      tagType: map['tagType'] as String,
      content: map['content'] as String?,
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      colorIndex: (map['color'] as int?) ?? 7,
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
      'color': colorIndex,
    };
  }
}
