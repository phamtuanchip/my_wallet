import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:my_wallet/document/document_export.dart';
import 'package:my_wallet/document/id_document.dart';

Uint8List _jpeg(int w, int h, int shade) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(shade, shade, shade));
  return img.encodeJpg(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final card = _jpeg(856, 540, 40); // ID-1 aspect
  final paper = _jpeg(700, 990, 200); // A4-ish portrait

  test('file names are ASCII, without diacritics', () {
    expect(removeDiacritics('Nguyễn Văn Đức, Hà Nội'), 'Nguyen Van Duc, Ha Noi');
    final c = DocumentContent(kind: DocumentKind.cccd, fields: {'holder': 'Nguyễn Văn An'});
    expect(exportBaseName(c, DateTime(2026, 11, 4)), 'CCCD_Nguyen_Van_An_20261104');
    final reg = DocumentContent(kind: DocumentKind.vehicleRegistration, fields: {'plate': '29A-123.45'});
    expect(exportBaseName(reg, DateTime(2026, 1, 9)), 'DangKyXe_29A_123_45_20260109');
    expect(exportBaseName(DocumentContent(kind: DocumentKind.other), DateTime(2026, 1, 9)), 'GiayTo_20260109');
  });

  test('PDF has one A4 page with both sides', () async {
    final pdf = await buildDocumentPdf([card, paper], title: 'Test');
    expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
    final text = latin1.decode(pdf);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 1);
    expect(RegExp(r'/Subtype\s*/Image').allMatches(text).length, 2);
    expect(text, contains('595.27')); // A4 width in points
  });

  test('combined image stacks the sides on a white sheet at the same width', () {
    final out = img.decodeJpg(combineSidesJpeg([card, paper]))!;
    expect(out.width, 1600);
    final inner = 1600 - 2 * 48;
    final expected = 2 * 48 + (inner * 540 / 856).round() + (inner * 990 / 700).round() + 48;
    expect((out.height - expected).abs(), lessThanOrEqualTo(2));
    expect(out.getPixel(5, 5).r, greaterThan(245)); // margin is white
    expect(out.getPixel(800, 48 + 100).r, lessThan(80)); // front is the dark one, on top
  });

  group('DocumentExporter', () {
    const channel = MethodChannel('test/downloads');
    final calls = <Map>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map;
        calls.add(args);
        return 'Download/MyWallet/${args['name']}';
      });
    });

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final exporter = DocumentExporter(channel: channel, clock: () => DateTime(2026, 11, 4));
    final content = DocumentContent(kind: DocumentKind.carLicense, fields: {'holder': 'Trần Bình'}, front: card, back: card);

    test('separate images: one JPEG per side', () async {
      final saved = await exporter.export(content, ExportFormat.separateImages);
      expect(saved, [
        'Download/MyWallet/BangLaiOto_Tran_Binh_20261104_front.jpg',
        'Download/MyWallet/BangLaiOto_Tran_Binh_20261104_back.jpg',
      ]);
      expect(calls.map((c) => c['mime']), everyElement('image/jpeg'));
      expect(calls.first['bytes'], card);
    });

    test('PDF and combined image are one file each', () async {
      expect(await exporter.export(content, ExportFormat.pdf), ['Download/MyWallet/BangLaiOto_Tran_Binh_20261104.pdf']);
      expect(calls.single['mime'], 'application/pdf');
      calls.clear();
      expect(await exporter.export(content, ExportFormat.combinedImage), ['Download/MyWallet/BangLaiOto_Tran_Binh_20261104.jpg']);
    });

    test('nothing to export without photos', () {
      expect(() => exporter.export(DocumentContent(kind: DocumentKind.other), ExportFormat.pdf), throwsStateError);
    });
  });
}
