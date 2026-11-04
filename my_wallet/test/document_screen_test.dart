import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_wallet/document/document_screen.dart';
import 'package:my_wallet/document/document_store.dart';
import 'package:my_wallet/document/id_document.dart';
import 'package:my_wallet/security/vault_crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<DocumentStore> store(WidgetTester tester) async {
    // Tall surface so the whole form is built (ListView is lazy).
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = (await tester.runAsync(() => databaseFactoryFfi.openDatabase(inMemoryDatabasePath)))!;
    addTearDown(() => tester.runAsync(db.close));
    return DocumentStore(db, VaultCrypto(MemoryVaultKeyStore()));
  }

  testWidgets('CCCD screen shows chip card, both photo slots and CCCD fields', (tester) async {
    final s = await store(tester);
    await tester.pumpWidget(MaterialApp(
      home: DocumentScreen(store: s, initial: DocumentContent(kind: DocumentKind.cccd), chipDetected: true),
    ));
    expect(find.text('Read chip'), findsOneWidget);
    expect(find.textContaining('Chip detected'), findsOneWidget);
    expect(find.text('Front · Mặt trước'), findsOneWidget);
    expect(find.text('Back · Mặt sau'), findsOneWidget);
    expect(find.text('Number · Số'), findsOneWidget);
    expect(find.text('Place of residence · Nơi thường trú'), findsOneWidget);

    // No number / dates yet: the chip can't be unlocked, so say what's missing.
    await tester.tap(find.text('Read chip'));
    await tester.pump();
    expect(find.textContaining('Enter the ID number, date of birth'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Number · Số'), '12345');
    await tester.enterText(find.widgetWithText(TextField, 'Date of birth · Ngày sinh'), '15/01/1990');
    await tester.enterText(find.widgetWithText(TextField, 'Valid until · Có giá trị đến'), '15/01/2030');
    await tester.tap(find.text('Read chip'));
    await tester.pump();
    expect(find.text('The CCCD number must have 12 digits.'), findsOneWidget);
  });

  testWidgets('licence screen has no chip section and rejects a bad date on save', (tester) async {
    final s = await store(tester);
    await tester.pumpWidget(MaterialApp(
      home: DocumentScreen(store: s, initial: DocumentContent(kind: DocumentKind.motoLicense)),
    ));
    expect(find.text('Read chip'), findsNothing);
    expect(find.text('Class · Hạng'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Issue date · Ngày cấp'), '2020-13');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Issue date: use dd/mm/yyyy.'), findsOneWidget);
  });
}
