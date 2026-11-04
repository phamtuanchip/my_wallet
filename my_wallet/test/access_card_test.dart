import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_wallet/access/lf_card_id.dart';
import 'package:my_wallet/access/nfc_tag_info.dart';
import 'package:my_wallet/document/document_ocr.dart';
import 'package:my_wallet/document/document_screen.dart';
import 'package:my_wallet/document/document_store.dart';
import 'package:my_wallet/document/id_document.dart';
import 'package:my_wallet/security/vault_crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('125 kHz EM4100 IDs', () {
    test('10-digit decimal → hex and Wiegand 26', () {
      final id = parseLfCardId('0004335038')!;
      expect(id.hex, '004225BE');
      expect(id.decimal10, '0004335038');
      expect(id.wiegand26, '066,09662');
    });

    test('printed line with both forms', () {
      expect(parseLfCardId('0004335038 066,09662')!.hex, '004225BE');
    });

    test('8 and 10 hex digits (reader in hex mode)', () {
      expect(parseLfCardId('004225be')!.decimal10, '0004335038');
      final full = parseLfCardId('1A004225BE')!;
      expect(full.version, 0x1A);
      expect(full.hex, '1A004225BE');
      expect(full.wiegand26, '066,09662');
    });

    test('Wiegand 26 only gives 24 bits', () {
      final id = parseLfCardId('066,09662')!;
      expect(id.id32, isNull);
      expect(id.decimal10, isNull);
      expect(id.hex, '4225BE');
    });

    test('junk is rejected', () {
      expect(parseLfCardId(''), isNull);
      expect(parseLfCardId('hello'), isNull);
      expect(parseLfCardId('300,99999'), isNull); // facility > 255, card > 65535
    });

    test('OCR ignores phone numbers but keeps zero-padded or W26-confirmed IDs', () {
      expect(findPrintedLfId('Hotline 0912345678'), isNull);
      expect(findPrintedLfId('Hotline 0912345678\n0004335038')!.hex, '004225BE');
      // Not zero-padded, but the printed pair confirms it (0x499602D2 → 150,00722).
      expect(findPrintedLfId('1234567890 150,00722')!.decimal10, '1234567890');
      // Pair disagrees with the number: only the pair is trusted.
      final pairOnly = findPrintedLfId('1234567890 073,50130')!;
      expect(pairOnly.id32, isNull);
      expect(pairOnly.wiegand26, '073,50130');
      final f = parseDocumentText(DocumentKind.accessCard, ['VINHOMES', 'Hotline 0912345678', '0004335038 066,09662']);
      expect(f['uid'], '004225BE');
      expect(f['frequency'], '125 kHz');
      expect(f.containsKey('expiry'), isFalse);
    });
  });

  test('chip family from SAK', () {
    expect(chipTypeFromSak(0x08), 'MIFARE Classic 1K');
    expect(chipTypeFromSak(0x18), 'MIFARE Classic 4K');
    expect(chipTypeFromSak(0x00), 'MIFARE Ultralight / NTAG');
    expect(chipTypeFromSak(0x20, isoDep: true), contains('DESFire'));
  });

  test('NFC tag info fields', () {
    const info = NfcTagInfo(uid: '04A1B2C3', chipType: 'MIFARE Classic 1K', sak: 0x08, atqa: '0400', defaultKeySectors: 3, sectorCount: 16);
    final f = info.toFields();
    expect(f['frequency'], '13.56 MHz (NFC)');
    expect(f['sakAtqa'], 'SAK 08 · ATQA 0400');
    expect(f['keyCheck'], '3/16 sectors open with a default key');
    expect(info.uidKind, '4-byte UID');
    const partial = NfcTagInfo(uid: '04A1B2C3D4E5F6', chipType: 'x', defaultKeySectors: 1, sectorCount: 16, keyCheckPartial: true);
    expect(partial.toFields()['keyCheck'], contains('stopped early'));
  });

  testWidgets('access card screen: USB reader fills the ID fields', (tester) async {
    sqfliteFfiInit();
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = (await tester.runAsync(() => databaseFactoryFfi.openDatabase(inMemoryDatabasePath)))!;
    addTearDown(() => tester.runAsync(db.close));

    await tester.pumpWidget(MaterialApp(
      home: DocumentScreen(
        store: DocumentStore(db, VaultCrypto(MemoryVaultKeyStore())),
        initial: DocumentContent(kind: DocumentKind.accessCard),
      ),
    ));
    expect(find.text('NFC · 13.56 MHz'), findsOneWidget);
    expect(find.text('Read chip'), findsNothing);

    await tester.tap(find.text('USB reader · 125 kHz'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Card number'), 'abc');
    await tester.tap(find.text('Use'));
    await tester.pump();
    expect(find.textContaining('Not a card number'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Card number'), '0004335038');
    await tester.testTextInput.receiveAction(TextInputAction.done); // reader presses Enter
    await tester.pumpAndSettle();
    expect(find.text('004225BE'), findsOneWidget);
    expect(find.text('066,09662'), findsOneWidget);
    expect(find.text('125 kHz'), findsOneWidget);
  });
}
