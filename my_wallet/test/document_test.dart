import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_wallet/document/document_ocr.dart';
import 'package:my_wallet/document/document_store.dart';
import 'package:my_wallet/document/id_document.dart';
import 'package:my_wallet/nfc/emrtd/mrz.dart';
import 'package:my_wallet/security/vault_crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('document OCR', () {
    final now = DateTime(2026, 11, 4);

    test('CCCD front: number, name, dates, sex', () {
      final f = parseDocumentText(DocumentKind.cccd, [
        'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM',
        'CĂN CƯỚC CÔNG DÂN',
        'Số / No.: 001090123456',
        'Họ và tên / Full name:',
        'NGUYỄN VĂN AN',
        'Ngày sinh / Date of birth: 15/01/1990',
        'Giới tính / Sex: Nam Quốc tịch / Nationality: Việt Nam',
        'Có giá trị đến: 15/01/2030',
      ], now: now);
      expect(f['number'], '001090123456');
      expect(f['holder'], 'NGUYỄN VĂN AN');
      expect(f['dob'], '15/01/1990');
      expect(f['expiry'], '15/01/2030');
      expect(f['sex'], 'Nam');
    });

    test('CCCD back: MRZ fills the chip key', () {
      const number = '001090123456';
      final doc = number.substring(3);
      final f = parseDocumentText(DocumentKind.cccd, [
        'Ngày, tháng, năm: 10/05/2021',
        'IDVNM$doc${mrzCheckDigit(doc)}$number<<<',
        '900115${mrzCheckDigit('900115')}M300115${mrzCheckDigit('300115')}VNM<<<<<<<<<<<0',
        'NGUYEN<<VAN<AN<<<<<<<<<<<<<<<<',
      ], now: now);
      expect(f['number'], number);
      expect(f['dob'], '15/01/1990');
      expect(f['expiry'], '15/01/2030');
      expect(f['nationality'], 'Việt Nam');
    });

    test('driving licence: class and dates; vehicle registration: plate', () {
      final lic = parseDocumentText(DocumentKind.carLicense, [
        'GIẤY PHÉP LÁI XE / DRIVER\'S LICENSE',
        'Số/No: 790123456789',
        'Ngày sinh/Date of Birth: 02/03/1985',
        'Hạng/Class: B2',
        'Ngày trúng tuyển 20/04/2015',
        'Có giá trị đến/Expires: 20/04/2028',
      ], now: now);
      expect(lic['number'], '790123456789');
      expect(lic['licenseClass'], 'B2');
      expect(lic['dob'], '02/03/1985');
      expect(lic['expiry'], '20/04/2028');
      expect(lic['issueDate'], '20/04/2015');

      final reg = parseDocumentText(DocumentKind.vehicleRegistration, ['Biển số đăng ký: 29A-123.45'], now: now);
      expect(reg['plate'], '29A-123.45');
      expect(reg.containsKey('number'), isFalse);
    });
  });

  test('vault encrypts and decrypts file bytes', () async {
    final vault = VaultCrypto(MemoryVaultKeyStore());
    final plain = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final enc = await vault.encryptBytes(plain);
    expect(enc.length, greaterThan(plain.length));
    expect(await vault.decryptBytes(enc), plain);
    expect(() => VaultCrypto(MemoryVaultKeyStore()).decryptBytes(enc), throwsA(anything));
    expect(() => vault.decryptBytes([1, 2, 3, 4]), throwsFormatException);
  });

  group('DocumentStore', () {
    late Database db;
    late Directory dir;
    late DocumentStore store;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(kDocumentsTableSql);
      dir = await Directory.systemTemp.createTemp('mw_docs_test');
      store = DocumentStore(db, VaultCrypto(MemoryVaultKeyStore()), baseDir: () async => dir);
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('saves encrypted, lists metadata only, reopens, replaces and deletes files', () async {
      final front = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);
      final id = await store.save(DocumentContent(
        kind: DocumentKind.cccd,
        fields: {'number': '001090123456', 'holder': 'Nguyễn Văn An', 'notes': '  '},
        front: front,
        hasChipData: true,
      ));

      final rows = await db.query('documents');
      expect(rows.single['number_last4'], '3456');
      expect(rows.single['title'], 'Căn cước công dân · Nguyễn Văn An');
      expect(rows.single['data_enc'].toString(), isNot(contains('001090123456')));
      final files = dir.listSync(recursive: true).whereType<File>().toList();
      expect(files, hasLength(1));
      expect(files.single.readAsBytesSync(), isNot(front));

      final doc = (await store.list()).single;
      expect(doc.id, id);
      expect(doc.hasChipData, isTrue);
      final opened = await store.open(doc);
      expect(opened.fields['number'], '001090123456');
      expect(opened.fields.containsKey('notes'), isFalse); // blank values are dropped
      expect(opened.front, front);
      expect(opened.back, isNull);

      opened.back = Uint8List.fromList([9, 9]);
      opened.front = null;
      await store.save(opened, existing: doc);
      final updated = (await store.list()).single;
      expect(updated.id, id);
      expect(updated.frontFile, isNull);
      expect(updated.createdAt, doc.createdAt);
      expect(dir.listSync(recursive: true).whereType<File>(), hasLength(1)); // old front removed

      await store.delete(updated);
      expect(await store.list(), isEmpty);
      expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
    });
  });
}
