
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';

import 'id_document.dart';

enum ExportFormat {
  pdf('PDF, both sides on one page', 'A4, real card size: print like a photocopy'),
  combinedImage('One image with both sides', 'Front above back, JPEG'),
  separateImages('Separate images', 'One JPEG per side');

  const ExportFormat(this.label, this.description);
  final String label;
  final String description;
}

/// Saves exports into the public `Download/MyWallet` folder (Android MediaStore).
/// Exported files are NOT encrypted: anyone with access to the phone's files can open them.
class DocumentExporter {
  DocumentExporter({MethodChannel? channel, DateTime Function()? clock})
      : _channel = channel ?? const MethodChannel('com.phamtuanchip.mywallet/downloads'),
        _clock = clock ?? DateTime.now;

  final MethodChannel _channel;
  final DateTime Function() _clock;

  /// Returns the saved locations, e.g. `Download/MyWallet/CCCD_Nguyen_Van_An_20261104.pdf`.
  Future<List<String>> export(DocumentContent c, ExportFormat format) async {
    final sides = [c.front, c.back].whereType<Uint8List>().toList();
    if (sides.isEmpty) throw StateError('no photos');
    final base = exportBaseName(c, _clock());
    switch (format) {
      case ExportFormat.pdf:
        final pdf = await buildDocumentPdf(sides, title: c.title.isEmpty ? c.defaultTitle : c.title);
        return [await _save('$base.pdf', 'application/pdf', pdf)];
      case ExportFormat.combinedImage:
        final jpeg = await compute(combineSidesJpeg, sides);
        return [await _save('$base.jpg', 'image/jpeg', jpeg)];
      case ExportFormat.separateImages:
        return [
          if (c.front != null) await _saveImage('${base}_front', c.front!),
          if (c.back != null) await _saveImage('${base}_back', c.back!),
        ];
    }
  }

  Future<String> _saveImage(String name, Uint8List bytes) {
    final png = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
    return _save('$name.${png ? 'png' : 'jpg'}', png ? 'image/png' : 'image/jpeg', bytes);
  }

  Future<String> _save(String name, String mime, Uint8List bytes) async {
    Future<String> call() async =>
        (await _channel.invokeMethod<String>('save', {'name': name, 'mime': mime, 'bytes': bytes}))!;
    try {
      return await call();
    } on PlatformException catch (e) {
      // Android 7–9 only: the public Download folder needs the storage permission.
      if (e.code != 'PERMISSION') rethrow;
      if (!(await Permission.storage.request()).isGranted) rethrow;
      return call();
    }
  }
}

/// `CCCD_Nguyen_Van_An_20261104`: ASCII only, safe on every file system.
String exportBaseName(DocumentContent c, DateTime now) {
  final kindTag = switch (c.kind) {
    DocumentKind.cccd => 'CCCD',
    DocumentKind.passport => 'HoChieu',
    DocumentKind.carLicense => 'BangLaiOto',
    DocumentKind.motoLicense => 'BangLaiXeMay',
    DocumentKind.vehicleRegistration => 'DangKyXe',
    DocumentKind.insurance => 'BaoHiemXe',
    DocumentKind.accessCard => 'TheTu',
    DocumentKind.other => 'GiayTo',
  };
  final who = removeDiacritics(
          c.fields['holder'] ?? c.fields['owner'] ?? c.fields['plate'] ?? c.fields['building'] ?? '')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final date = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  return [kindTag, if (who.isNotEmpty) who, date].join('_');
}

const _vnGroups = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};

String removeDiacritics(String s) {
  final map = <String, String>{};
  _vnGroups.forEach((base, chars) {
    for (final ch in chars.split('')) {
      map[ch] = base;
      map[ch.toUpperCase()] = base.toUpperCase();
    }
  });
  return s.split('').map((ch) => map[ch] ?? ch).join();
}

/// A4 portrait, sides stacked and centred. Card-shaped photos (ID-1, ≈1.586:1)
/// are placed at their real size, 85.6 × 54 mm, so a print matches a photocopy;
/// other shapes are scaled to fit half of the page.
Future<Uint8List> buildDocumentPdf(List<Uint8List> sides, {String title = 'Document'}) async {
  final doc = pw.Document(title: title, creator: 'My Wallet');
  final images = [for (final s in sides) pw.MemoryImage(s)];
  const pageFormat = PdfPageFormat.a4;
  const margin = 15 * PdfPageFormat.mm;
  const gap = 12 * PdfPageFormat.mm;
  final maxW = pageFormat.width - 2 * margin;
  final maxH = (pageFormat.height - 2 * margin - gap * (images.length - 1)) / images.length;

  (double, double) sizeOf(pw.MemoryImage image) {
    final w = (image.width ?? 1).toDouble(), h = (image.height ?? 1).toDouble();
    final aspect = w / h;
    if (aspect > 1.45 && aspect < 1.72) return (85.6 * PdfPageFormat.mm, 54 * PdfPageFormat.mm);
    var outW = maxW, outH = maxW / aspect;
    if (outH > maxH) {
      outH = maxH;
      outW = maxH * aspect;
    }
    return (outW, outH);
  }

  doc.addPage(pw.Page(
    pageFormat: pageFormat,
    margin: const pw.EdgeInsets.all(margin),
    build: (_) => pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.start,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < images.length; i++) ...[
          if (i > 0) pw.SizedBox(height: gap),
          () {
            final (w, h) = sizeOf(images[i]);
            return pw.Image(images[i], width: w, height: h, fit: pw.BoxFit.contain);
          }(),
        ],
      ],
    ),
  ));
  return doc.save();
}

/// Runs in an isolate: both sides scaled to the same width on a white sheet,
/// front above back, as one JPEG.
Uint8List combineSidesJpeg(List<Uint8List> sides) {
  const width = 1600, pad = 48, gap = 48;
  final decoded = <img.Image>[];
  for (final s in sides) {
    final d = img.decodeImage(s);
    if (d != null) decoded.add(img.copyResize(img.bakeOrientation(d), width: width - 2 * pad));
  }
  if (decoded.isEmpty) throw const FormatException('photos could not be decoded');
  final height = 2 * pad + decoded.fold<int>(0, (h, d) => h + d.height) + gap * (decoded.length - 1);
  final canvas = img.Image(width: width, height: height, numChannels: 3);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  var y = pad;
  for (final d in decoded) {
    img.compositeImage(canvas, d, dstX: pad, dstY: y);
    y += d.height + gap;
  }
  return img.encodeJpg(canvas, quality: 90);
}
