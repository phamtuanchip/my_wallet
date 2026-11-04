import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'package:logger/logger.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:my_wallet/utils/file_transfer_utils.dart';
import 'package:my_wallet/card/card_color.dart';
import 'package:my_wallet/card/card_details_screen.dart';
import 'package:my_wallet/card/card_info.dart';
import 'package:my_wallet/access/nfc_tag_info.dart';
import 'package:my_wallet/document/document_screen.dart';
import 'package:my_wallet/document/document_store.dart';
import 'package:my_wallet/document/documents_view.dart';
import 'package:my_wallet/document/id_document.dart';
import 'package:my_wallet/nfc/emrtd/emrtd_reader.dart';
import 'package:my_wallet/nfc/emv/emv_reader.dart';
import 'package:my_wallet/security/app_auth.dart';
import 'package:my_wallet/security/vault_crypto.dart';
import 'package:my_wallet/widgets/wallet_card_face.dart';
import 'package:my_wallet/widgets/wallet_card_stack.dart';
import 'package:my_wallet/widgets/zodiac_mark.dart';
import 'package:my_wallet/card/card_theme_art.dart';
import 'package:my_wallet/card/zodiac.dart';

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final VaultCrypto _vault = VaultCrypto(SecureVaultKeyStore());

  /// Ignores tag discoveries that arrive while one is still being handled
  /// (Android keeps reporting the card while it stays on the phone).
  bool _handlingTag = false;

  /// Card ids whose "add details" prompt was shown recently, to avoid repeats.
  final Map<String, DateTime> _promptedAt = {};

  final logger = Logger();
  String _scanResult = 'Tap card to scan';
  bool _isScanning = false;
  List<NFCCard> _savedCards = [];
  Database? _database;

  /// Personal documents (CCCD, passport, licences…), DB v5.
  DocumentStore? _docStore;
  List<IdDocument> _documents = [];
  bool _documentsLoading = true;
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
    WidgetsBinding.instance.addObserver(this);
    ZodiacGlyphs.preload(); // card faces draw their gold sign from the first frame
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      AppAuth.lock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'nfc_wallet.db');

    _database = await openDatabase(
      path,
      version: 5,
      onCreate: (Database db, int version) async {
        await db.execute(kDocumentsTableSql);
        await db.execute('''
          CREATE TABLE cards (
            id TEXT PRIMARY KEY,
            uid TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            tagType TEXT NOT NULL,
            content TEXT,
            timestamp INTEGER NOT NULL,
            color INTEGER NOT NULL DEFAULT 7,
            ${[...kCardDetailColumns, ...kCardV4Columns].join(',\n            ')}
          )
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE cards ADD COLUMN color INTEGER NOT NULL DEFAULT 7');
        }
        if (oldVersion < 3) {
          // v1.2.0: payment details. Additive only, existing cards keep their data.
          for (final column in kCardDetailColumns) {
            await db.execute('ALTER TABLE cards ADD COLUMN $column');
          }
        }
        if (oldVersion < 4) {
          for (final column in kCardV4Columns) {
            await db.execute('ALTER TABLE cards ADD COLUMN $column');
          }
        }
        if (oldVersion < 5) {
          // v1.4.0: personal documents in their own table.
          await db.execute(kDocumentsTableSql);
        }
      },
    );

    _docStore = DocumentStore(_database!, _vault);
    await _loadSavedCards();
    await _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    final store = _docStore;
    if (store == null) return;
    try {
      final docs = await store.list();
      if (mounted) setState(() => _documents = docs);
    } catch (e) {
      logger.e('Could not load documents: ${e.runtimeType}');
    } finally {
      if (mounted) setState(() => _documentsLoading = false);
    }
  }

  /// "+" on the Wallet tab: NFC scan (auto-detects the card type) or a document.
  Future<void> _showAddSheet() async {
    final kind = await showDocumentKindPicker(
      context,
      title: 'Add to wallet',
      onNfcScan: _startNFCSession,
    );
    if (kind != null) await _addDocument(kind);
  }

  Future<void> _addDocument(DocumentKind kind, {bool chipDetected = false, Map<String, String>? fields}) async {
    final store = _docStore;
    if (store == null || !mounted) return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => DocumentScreen(
        store: store,
        initial: DocumentContent(kind: kind, fields: {...?fields}),
        chipDetected: chipDetected,
      ),
    ));
    if (changed == true) {
      await _loadDocuments();
      if (mounted) setState(() => _selectedTabIndex = 3);
    }
  }

  Future<void> _openDocument(IdDocument doc) async {
    final store = _docStore;
    if (store == null) return;
    final outcome = await AppAuth.unlock('Unlock to view ${doc.title}');
    if (!mounted) return;
    if (outcome != AuthOutcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(outcome == AuthOutcome.unavailable
            ? 'Set a screen lock (PIN, pattern or fingerprint) in Android settings to view saved documents.'
            : 'Not unlocked. The document stays hidden.'),
      ));
      return;
    }
    final DocumentContent content;
    try {
      content = await store.open(doc);
    } catch (e) {
      logger.e('Could not decrypt document: ${e.runtimeType}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This document could not be decrypted on this device.'),
      ));
      return;
    }
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => DocumentScreen(store: store, initial: content, existing: doc),
    ));
    if (changed == true) await _loadDocuments();
  }

  /// A tapped card has the ICAO eMRTD application: ask which document it is.
  Future<void> _onChipDocumentDetected() async {
    setState(() {
      _isScanning = false;
      _scanResult = 'Chip ID document detected';
    });
    HapticFeedback.mediumImpact();
    final kind = await showDocumentKindPicker(
      context,
      title: 'Chip document detected',
      message: 'This is not a bank card. Which document is it?',
      kinds: const [DocumentKind.cccd, DocumentKind.passport],
    );
    if (kind != null) await _addDocument(kind, chipDetected: true);
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

  /// Saves or refreshes a scanned card. Returns the card id and whether it is new.
  Future<({String id, bool isNew})?> _saveCard(
      String uid, String tagType, String content) async {
    if (_database == null) return null;

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
      await _loadSavedCards();
      return (id: existingCards.first['id'] as String, isNew: false);
    } else {
      final nextNumber = _savedCards.length + 1;
      final cardName = 'Card $nextNumber';
      // A random colour no other card uses (hue kept far from existing ones).
      final colorValue =
          pickDistinctCardColor(_savedCards.map((c) => c.colorValue));
      final id = const Uuid().v4();

      await _database!.insert(
        'cards',
        {
          'id': id,
          'uid': uid,
          'name': cardName,
          'tagType': tagType,
          'content': content,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'color': colorValue,
        },
      );
      logger.i('Saved new card: $cardName with UID: $uid');
      await _loadSavedCards();
      return (id: id, isNew: true);
    }
  }

  /// Opens the payment-details editor. Existing secrets need fingerprint/passcode.
  Future<void> _openCardDetails(NFCCard card, {bool scanOnOpen = false}) async {
    var initial = CardDetails(
      holder: card.holder ?? '',
      scheme: CardScheme.fromName(card.scheme),
      product: CardProduct.fromName(card.product),
      issuer: card.issuer ?? '',
      expiry: card.expiry ?? '',
    );
    if (card.panEnc != null || card.cvvEnc != null) {
      final outcome = await AppAuth.unlock('Unlock to view ${card.name}');
      if (!mounted) return;
      if (outcome != AuthOutcome.success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(outcome == AuthOutcome.unavailable
              ? 'Set a screen lock (PIN, pattern or fingerprint) in Android settings to view saved card numbers.'
              : 'Not unlocked. Card details stay hidden.'),
        ));
        return;
      }
      try {
        initial = CardDetails(
          number: card.panEnc == null ? '' : await _vault.decrypt(card.panEnc!),
          cvv: card.cvvEnc == null ? '' : await _vault.decrypt(card.cvvEnc!),
          holder: initial.holder,
          scheme: initial.scheme,
          product: initial.product,
          issuer: initial.issuer,
          expiry: initial.expiry,
        );
      } catch (e) {
        logger.e('Could not decrypt card details: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Saved card number could not be decrypted on this device. Enter it again.'),
        ));
      }
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push<CardDetails>(MaterialPageRoute(
      builder: (_) => CardDetailsScreen(
        cardName: card.name,
        color: cardColorFromValue(card.colorValue),
        gradientColors: cardGradientFromValue(card.colorValue)?.colors,
        themeArt: cardThemeFromValue(card.colorValue),
        initial: initial,
        scanOnOpen: scanOnOpen,
      ),
    ));
    if (result == null) return;
    await _saveCardDetails(card, result);
  }

  Future<void> _saveCardDetails(NFCCard card, CardDetails d) async {
    if (_database == null) return;
    String? orNull(String v) => v.trim().isEmpty ? null : v.trim();
    await _database!.update(
      'cards',
      {
        'pan_enc': d.number.isEmpty ? null : await _vault.encrypt(d.number),
        'last4': d.number.isEmpty ? null : last4Of(d.number),
        'cvv_enc': d.cvv.isEmpty ? null : await _vault.encrypt(d.cvv),
        'holder': orNull(d.holder),
        'scheme': d.scheme == CardScheme.unknown ? null : d.scheme.name,
        'product': d.product == CardProduct.unknown ? null : d.product.name,
        'issuer': orNull(d.issuer),
        'expiry': orNull(d.expiry),
        'pan_fp': d.number.isEmpty ? null : await _vault.fingerprint(d.number),
        'details_updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [card.id],
    );
    await _loadSavedCards();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${card.name}: card details saved')),
      );
    }
  }

  /// One prompt per card: clears queued snackbars (a swiped one must not be
  /// replaced by a queued duplicate), auto-hides after 8 s, has a close button,
  /// and is not shown again for the same card within 60 s.
  void _showCardPrompt(NFCCard card, String message,
      {required String actionLabel, required VoidCallback onAction}) {
    if (!mounted) return;
    final last = _promptedAt[card.id];
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 60)) {
      return;
    }
    _promptedAt[card.id] = DateTime.now();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        // Flutter keeps snackbars with an action on screen unless persist is false.
        persist: false,
        showCloseIcon: true,
        dismissDirection: DismissDirection.horizontal,
        content: Text(message),
        action: SnackBarAction(label: actionLabel, onPressed: onAction),
      ));
  }

  /// Finds a saved card with this number: by fingerprint, or (cards saved
  /// before v1.3.0) by last 4 + decrypting the stored number.
  Future<NFCCard?> _findCardByPan(String pan, String fp) async {
    for (final c in _savedCards) {
      if (c.panFp == fp) return c;
    }
    final last4 = last4Of(pan);
    for (final c in _savedCards) {
      if (c.panFp != null || c.panEnc == null || c.last4 != last4) continue;
      try {
        if (await _vault.decrypt(c.panEnc!) == pan) return c;
      } catch (_) {}
    }
    return null;
  }

  /// Saves what the chip revealed. Bank cards send a random UID on each tap,
  /// so the card is identified by its number fingerprint instead.
  Future<void> _saveEmvCard(EmvCardData emv) async {
    if (_database == null) return;
    final fp = await _vault.fingerprint(emv.pan);
    final existing = await _findCardByPan(emv.pan, fp);
    final now = DateTime.now().millisecondsSinceEpoch;
    final scheme = emv.scheme == CardScheme.unknown ? null : emv.scheme.name;
    final issuer = emv.issuer;
    final productName = emv.product?.name;
    final String cardId;
    final bool isNew = existing == null;

    if (existing != null) {
      cardId = existing.id;
      await _database!.update(
        'cards',
        {
          // The chip is authoritative for number + expiry (e.g. after a renewal);
          // keep what the user typed for the other fields.
          'pan_enc': await _vault.encrypt(emv.pan),
          'last4': last4Of(emv.pan),
          'pan_fp': fp,
          if (emv.expiry != null) 'expiry': emv.expiry,
          if (existing.scheme == null && scheme != null) 'scheme': scheme,
          if (existing.product == null && productName != null) 'product': productName,
          if (existing.issuer == null && issuer != null) 'issuer': issuer,
          if (existing.holder == null && emv.holder != null) 'holder': emv.holder,
          'timestamp': now,
          'details_updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [existing.id],
      );
    } else {
      cardId = const Uuid().v4();
      final label = emv.appLabel ?? emv.scheme.label;
      final name = issuer != null && !label.toUpperCase().contains(issuer.toUpperCase())
          ? '$issuer $label'
          : label;
      await _database!.insert('cards', {
        'id': cardId,
        // Stable, non-reversible id for the UNIQUE uid column.
        'uid': 'emv-${fp.substring(0, 16)}',
        'name': name,
        'tagType': 'EMV contactless · ${emv.scheme.label}',
        'content': '',
        'timestamp': now,
        'color': pickDistinctCardColor(_savedCards.map((c) => c.colorValue)),
        'pan_enc': await _vault.encrypt(emv.pan),
        'last4': last4Of(emv.pan),
        'pan_fp': fp,
        'expiry': emv.expiry,
        'scheme': scheme,
        'product': productName,
        'issuer': issuer,
        'holder': emv.holder,
        'details_updated_at': now,
      });
    }
    await _loadSavedCards();
    if (!mounted) return;
    final card = _savedCards.where((c) => c.id == cardId).firstOrNull;
    if (card == null) return;
    final summary = [
      emv.scheme.label,
      '•• ${last4Of(emv.pan)}',
      if (emv.expiry != null) 'exp ${emv.expiry}',
    ].join(' · ');
    setState(() => _scanResult = isNew ? 'Card added from chip\n$summary' : 'Card updated from chip\n$summary');
    final missing = [
      if (card.holder == null) 'name',
      if (card.cvvEnc == null) 'CVV',
    ];
    _showCardPrompt(
      card,
      missing.isEmpty
          ? '${card.name} ${isNew ? 'added' : 'updated'} from the chip: $summary'
          : 'Read from the chip: $summary. Add ${missing.join(' and ')}?',
      actionLabel: missing.isEmpty ? 'View' : 'Add',
      onAction: () => _openCardDetails(card, scanOnOpen: card.holder == null),
    );
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
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: [
          'jpg', 'jpeg', 'png', 'gif', 'pdf', 'txt', 'doc', 'docx'
        ],
      );

      if (picked != null) {
        setState(() {
          _selectedFile = picked;
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

      // file_picker 13: content is read through the XFile, not a bytes field.
      final Uint8List fileData = await _selectedFile!.xFile.readAsBytes();

      final fileMetadata = {
        'name': _selectedFile!.name,
        'size': fileData.length,
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
    if (_handlingTag) return;
    _handlingTag = true;
    try {
      // Payment cards: read number + expiry from the chip while the card is
      // still in the field (must happen before stopSession).
      EmvCardData? emv;
      final isoDep = _isReceivingFile ? null : IsoDep.from(tag);
      if (isoDep != null) {
        setState(() => _scanResult = 'Reading card chip… keep the card still');
        try {
          emv = await EmvReader((apdu) => isoDep.transceive(data: apdu))
              .read()
              .timeout(const Duration(seconds: 8));
        } catch (e) {
          // Never log card data, only the failure kind.
          logger.w('EMV read failed: ${e.runtimeType}');
        }
      }

      // Not a bank card: is it a chip CCCD / passport (ICAO eMRTD applet)?
      final isChipDocument = emv == null &&
          isoDep != null &&
          await EmrtdReader.probe((apdu) => isoDep.transceive(data: apdu));

      // Anything else (MIFARE, NTAG, DESFire…) is likely an access card: read
      // its type and key check while it is still in the field.
      NfcTagInfo? accessInfo;
      if (emv == null && !isChipDocument && !_isReceivingFile) {
        try {
          accessInfo = await readNfcTagInfo(tag).timeout(const Duration(seconds: 6));
        } catch (e) {
          logger.w('Tag info read failed: ${e.runtimeType}');
        }
      }

      await NfcManager.instance.stopSession();

      if (emv != null) {
        HapticFeedback.mediumImpact();
        await _saveEmvCard(emv);
        setState(() => _isScanning = false);
        return;
      }

      if (isChipDocument) {
        await _onChipDocumentDetected();
        return;
      }

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
        final saved = await _saveCard(uid, tagType, content);
        setState(() {
          _scanResult = 'Card saved!\nUID: $uid\nType: $tagType';
        });
        if (saved != null && mounted) {
          final card = _savedCards.where((c) => c.id == saved.id).firstOrNull;
          if (card != null && accessInfo != null && !card.hasPaymentDetails) {
            final info = accessInfo;
            _showCardPrompt(
              card,
              '${info.chipType} · UID ${info.uid}. Elevator, door or parking card? Save it to Documents.',
              actionLabel: 'Save',
              onAction: () => _addDocument(DocumentKind.accessCard, fields: info.toFields()),
            );
          } else if (card != null && !card.hasPaymentDetails) {
            _showCardPrompt(
              card,
              saved.isNew
                  ? '${card.name} saved. Add the card number, expiry and CVV?'
                  : '${card.name} updated. Add its card details?',
              actionLabel: 'Scan card',
              onAction: () => _openCardDetails(card, scanOnOpen: true),
            );
          }
        }
      } else {
        setState(() {
          _scanResult = 'Scanned — no UID\nType: $tagType';
        });
      }

      setState(() => _isScanning = false);
    } catch (e) {
      logger.e('Error handling tag: ${e.runtimeType}');
      setState(() {
        _scanResult = 'Error: $e';
        _isScanning = false;
      });
    } finally {
      _handlingTag = false;
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
              _navItem(0, LucideIcons.wallet, LucideIcons.walletCards, 'Wallet', isDark),
              _navItem(
                  1, LucideIcons.creditCard, LucideIcons.creditCard, 'Cards', isDark),
              // Index 3 sits before Settings visually; Settings keeps index 2.
              _navItem(3, LucideIcons.idCard, LucideIcons.idCard, 'Documents', isDark),
              _navItem(
                  2, LucideIcons.settings, LucideIcons.settings, 'Settings', isDark),
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
        width: 76,
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
      case 3:
        return DocumentsView(
          documents: _documents,
          loading: _documentsLoading,
          onAdd: () async {
            final kind = await showDocumentKindPicker(context);
            if (kind != null) await _addDocument(kind);
          },
          onOpen: _openDocument,
        );
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
                      : _showAddSheet,
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
                      _isScanning ? LucideIcons.radioTower : LucideIcons.plus,
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
            child: const Icon(LucideIcons.nfc,
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
            child: const Icon(LucideIcons.nfc,
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
            child: const Icon(LucideIcons.share,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: WalletCardStack<NFCCard>(
        items: _savedCards,
        idOf: (c) => c.id,
        peek: WalletCardFace.headerHeight,
        faceBuilder: (context, card, focused) =>
            _buildWalletCard(card, isTop: focused),
        onOpen: _showCardBottomSheet,
      ),
    );
  }

  Widget _buildWalletCard(NFCCard card, {bool isTop = false}) {
    return WalletCardFace(
      title: card.name,
      subtitle: card.issuer ??
          (card.product != null
              ? CardProduct.fromName(card.product).label
              : null),
      color: cardColorFromValue(card.colorValue),
      gradientColors: cardGradientFromValue(card.colorValue)?.colors,
      themeArt: cardThemeFromValue(card.colorValue),
      last4: card.last4,
      holder: card.holder,
      expiry: card.expiry,
      scheme: card.scheme == null ? null : CardScheme.fromName(card.scheme),
      footnote: card.tagType,
      elevated: isTop,
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          LucideIcons.wallet,
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
              _isScanning ? LucideIcons.radioTower : LucideIcons.nfc,
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
        onDetails: () {
          Navigator.pop(context);
          _openCardDetails(card);
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
            if (card.hasPaymentDetails) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (card.issuer != null) card.issuer!,
                  if (card.scheme != null) CardScheme.fromName(card.scheme).label,
                  if (card.product != null) CardProduct.fromName(card.product).label,
                  if (card.last4 != null) '•• ${card.last4}',
                  if (card.expiry != null) 'exp ${card.expiry}',
                ].join('  ·  '),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
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
                  icon: isThisEmulating ? LucideIcons.nfc : LucideIcons.nfc,
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
                  icon: LucideIcons.creditCard,
                  label: 'Details',
                  color: const Color(0xFF5856D6),
                  onTap: () => _openCardDetails(card),
                  isDark: isDark,
                ),
                const SizedBox(width: 10),
                _actionChip(
                  icon: LucideIcons.share,
                  label: 'Share',
                  color: const Color(0xFF007AFF),
                  onTap: () => _sendCardViaNFC(card),
                  isDark: isDark,
                ),
                const SizedBox(width: 10),
                _actionChip(
                  icon: LucideIcons.trash2,
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
              icon: LucideIcons.nfc,
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
              icon: LucideIcons.fileUp,
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
              icon: LucideIcons.download,
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
              icon: LucideIcons.info,
              iconColor: const Color(0xFF007AFF),
              title: 'My Wallet',
              subtitle: 'NFC Business Card Wallet v1.0',
              isDark: isDark,
            ),
            _settingsRow(
              icon: LucideIcons.creditCard,
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
  final VoidCallback onDetails;
  final VoidCallback onShare;
  final VoidCallback onEdit;
  final ValueChanged<int> onColorChange;
  final VoidCallback onDelete;

  const _CardBottomSheet({
    required this.card,
    required this.isEmulating,
    required this.emulatingCard,
    required this.onEmulate,
    required this.onDetails,
    required this.onShare,
    required this.onEdit,
    required this.onColorChange,
    required this.onDelete,
  });

  @override
  State<_CardBottomSheet> createState() => _CardBottomSheetState();
}

class _CardBottomSheetState extends State<_CardBottomSheet> {
  /// Stored `color` value of the selection: preset index, own ARGB colour,
  /// or a gradient ([kGradientBase] + index).
  late int _value;

  /// The random colour the card was created with; kept selectable after picking a preset.
  int? _ownColor;

  @override
  void initState() {
    super.initState();
    _value = widget.card.colorValue;
    final isPreset = _value >= 0 && _value < kCardColors.length;
    _ownColor = isPreset || cardGradientFromValue(_value) != null ? null : _value;
  }

  void _select(int value) {
    setState(() => _value = value);
    widget.onColorChange(value);
  }

  /// A small card-shaped preview of a theme, with its name and the card's sign.
  Widget _themeSwatch(CardThemeArt theme, int value, ZodiacSign? sign, bool isDark) {
    final isSelected = value == _value;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${theme.name} (${theme.vnName})',
      child: GestureDetector(
        onTap: () => _select(value),
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 70,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: isSelected ? (isDark ? Colors.white : Colors.black87) : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(fit: StackFit.expand, children: [
                  CustomPaint(painter: CardThemePainter(theme)),
                  if (sign != null) Center(child: ZodiacMark(sign: sign, background: theme.average, size: 26, opacity: 0.8)),
                ]),
              ),
            ),
            const SizedBox(height: 3),
            Text(theme.vnName,
                style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.black54)),
          ]),
        ),
      ),
    );
  }

  /// One round swatch (solid or gradient) with the card's zodiac sign on it,
  /// so the gold can be judged against every background before choosing.
  Widget _swatch({
    required int value,
    required List<Color> colors,
    required ZodiacSign? sign,
    required bool isDark,
    required String label,
  }) {
    final isSelected = value == _value;
    final base = colors.length == 1 ? colors.first : cardColorFromValue(value);
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        onTap: () => _select(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: colors.length == 1 ? colors.first : null,
            gradient: colors.length > 1
                ? LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)
                : null,
            shape: BoxShape.circle,
            border: isSelected ? Border.all(color: isDark ? Colors.white : Colors.black87, width: 2.5) : null,
            boxShadow: [
              BoxShadow(color: base.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: sign != null
              ? Center(child: ZodiacMark(sign: sign, background: base, size: isSelected ? 26 : 22))
              : isSelected
                  ? const Icon(LucideIcons.check, color: Colors.white, size: 20)
                  : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = cardColorFromValue(_value);
    final gradient = cardGradientFromValue(_value);
    final theme = cardThemeFromValue(_value);
    final darkerColor = HSLColor.fromColor(cardColor)
        .withLightness(
            (HSLColor.fromColor(cardColor).lightness - 0.12).clamp(0.0, 1.0))
        .toColor();
    final isThisEmulating =
        widget.isEmulating && widget.emulatingCard?.id == widget.card.id;
    // Zodiac sign of the expiry month, previewed on the card and every swatch.
    final sign = ZodiacSign.fromExpiry(widget.card.expiry);

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
                colors: gradient?.colors ?? [cardColor, darkerColor],
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
            child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
            if (theme != null)
              Positioned(
                left: -20,
                top: -20,
                right: -20,
                bottom: -20,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: CustomPaint(painter: CardThemePainter(theme)),
                ),
              ),
            if (sign != null)
              Positioned(
                right: 0,
                top: 50,
                child: ZodiacBadge(sign: sign, background: cardColor, size: 36, animate: true),
              ),
            Column(
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
                    const Icon(LucideIcons.nfc,
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
            ]),
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
              // The card's own random colour (if any) comes first, then the presets.
              itemCount: kCardColors.length + (_ownColor != null ? 1 : 0),
              itemBuilder: (context, item) {
                final offset = _ownColor != null ? 1 : 0;
                final i = item - offset; // -1 = own colour
                final value = i < 0 ? _ownColor! : i;
                return _swatch(
                  value: value,
                  colors: [cardColorFromValue(value)],
                  sign: sign,
                  isDark: isDark,
                  label: i < 0 ? 'Own colour' : 'Colour ${i + 1}',
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Gradient',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: kCardGradients.length,
              itemBuilder: (context, i) => _swatch(
                value: gradientValue(i),
                colors: kCardGradients[i].colors,
                sign: sign,
                isDark: isDark,
                label: kCardGradients[i].name,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Theme · Chủ đề',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: kCardThemes.length,
              itemBuilder: (context, i) => _themeSwatch(kCardThemes[i], themeValue(i), sign, isDark),
            ),
          ),

          const SizedBox(height: 24),

          // Payment details (number, expiry, CVV…)
          SizedBox(
            width: double.infinity,
            child: _SheetButton(
              icon: LucideIcons.creditCard,
              label: widget.card.hasPaymentDetails
                  ? 'Card details  ·  •• ${widget.card.last4 ?? ''}'
                  : 'Add card details (scan or type)',
              backgroundColor: const Color(0xFF007AFF),
              textColor: Colors.white,
              onTap: widget.onDetails,
            ),
          ),
          const SizedBox(height: 10),

          // Action buttons row
          Row(
            children: [
              Expanded(
                child: _SheetButton(
                  icon: LucideIcons.share,
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
                  icon: LucideIcons.pencil,
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
                icon: LucideIcons.trash2,
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

/// DB v3 columns for payment details. `pan_enc` / `cvv_enc` hold AES-GCM tokens
/// from [VaultCrypto]; `last4` and the rest stay readable for lists and search.
/// DB v4 (v1.3.0): keyed HMAC of the card number, see [VaultCrypto.fingerprint].
const List<String> kCardV4Columns = ['pan_fp TEXT'];

const List<String> kCardDetailColumns = [
  'pan_enc TEXT',
  'last4 TEXT',
  'cvv_enc TEXT',
  'holder TEXT',
  'scheme TEXT',
  'product TEXT',
  'issuer TEXT',
  'expiry TEXT',
  'details_updated_at INTEGER',
];

class NFCCard {
  final String id;
  final String uid;
  final String name;
  final String tagType;
  final String? content;
  final DateTime timestamp;

  /// Preset index (0..7, legacy) or an ARGB colour. See [cardColorFromValue].
  final int colorValue;

  final String? panEnc;
  final String? last4;
  final String? cvvEnc;
  final String? holder;
  final String? scheme;
  final String? product;
  final String? issuer;
  final String? expiry;
  final String? panFp;

  NFCCard({
    required this.id,
    required this.uid,
    required this.name,
    required this.tagType,
    this.content,
    required this.timestamp,
    this.colorValue = 7,
    this.panEnc,
    this.last4,
    this.cvvEnc,
    this.holder,
    this.scheme,
    this.product,
    this.issuer,
    this.expiry,
    this.panFp,
  });

  bool get hasPaymentDetails =>
      panEnc != null || cvvEnc != null || holder != null || expiry != null || issuer != null;

  factory NFCCard.fromMap(Map<String, dynamic> map) {
    return NFCCard(
      id: map['id'] as String,
      uid: map['uid'] as String,
      name: map['name'] as String,
      tagType: map['tagType'] as String,
      content: map['content'] as String?,
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      colorValue: (map['color'] as int?) ?? 7,
      panEnc: map['pan_enc'] as String?,
      last4: map['last4'] as String?,
      cvvEnc: map['cvv_enc'] as String?,
      holder: map['holder'] as String?,
      scheme: map['scheme'] as String?,
      product: map['product'] as String?,
      issuer: map['issuer'] as String?,
      expiry: map['expiry'] as String?,
      panFp: map['pan_fp'] as String?,
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
      'color': colorValue,
      'pan_enc': panEnc,
      'last4': last4,
      'cvv_enc': cvvEnc,
      'holder': holder,
      'scheme': scheme,
      'product': product,
      'issuer': issuer,
      'expiry': expiry,
      'pan_fp': panFp,
    };
  }
}
