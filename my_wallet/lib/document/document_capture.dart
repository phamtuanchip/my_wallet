import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/document_scan.dart';

/// One photographed side: the JPEG to keep (encrypted later) and its OCR text.
class CapturedSide {
  const CapturedSide(this.jpeg, this.lines);
  final Uint8List jpeg;
  final List<String> lines;
}

/// "Photo scan" capture for documents: ML Kit Document Scanner in full mode
/// (auto edge detection, adjustable corners, rotate, filters, shadow/finger
/// clean-up), plain camera / gallery as fallback, then on-device OCR.
/// Temporary files are deleted; only the returned bytes remain, in memory.
class DocumentCapture {
  DocumentCapture({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Longest side kept: cards stay sharp at 1800 px; A4/A5 papers need more
  /// for small print to stay readable when zoomed or printed.
  static int maxSideFor({required bool largeFormat}) => largeFormat ? 3000 : 1800;

  /// One side. With [fromGallery] the photo is picked from the gallery and,
  /// when the scanner is available, cropped by it. Null when cancelled.
  Future<CapturedSide?> capture({bool fromGallery = false, bool largeFormat = false}) async {
    final sides = await _run(pages: 1, fromGallery: fromGallery, largeFormat: largeFormat);
    return sides == null || sides.isEmpty ? null : sides.first;
  }

  /// Front and back in one scanner session (first page = front). Null when
  /// cancelled; falls back to two plain camera shots without the scanner.
  Future<List<CapturedSide>?> captureBothSides({bool largeFormat = false}) =>
      _run(pages: 2, fromGallery: false, largeFormat: largeFormat);

  Future<List<CapturedSide>?> _run({required int pages, required bool fromGallery, required bool largeFormat}) async {
    final temp = <String>[];
    try {
      List<String> paths;
      switch (await scanDocumentPage(pages: pages, full: true, gallery: fromGallery)) {
        case DocumentScanCancelled():
          return null;
        case DocumentScanned(paths: final scanned):
          paths = scanned;
        case DocumentScanUnavailable():
          paths = [];
          for (var i = 0; i < pages; i++) {
            final shot = await _picker.pickImage(
              source: fromGallery ? ImageSource.gallery : ImageSource.camera,
              preferredCameraDevice: CameraDevice.rear,
              requestFullMetadata: false,
            );
            if (shot == null) break;
            paths.add(shot.path);
          }
          if (paths.isEmpty) return null;
      }
      temp.addAll(paths);

      final dir = (await getTemporaryDirectory()).path;
      final maxSide = maxSideFor(largeFormat: largeFormat);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final out = <CapturedSide>[];
        for (final path in paths) {
          final target = '$dir/doc_${DateTime.now().microsecondsSinceEpoch}.jpg';
          final shrunk = await compute(_shrink, (path, target, maxSide));
          final usable = shrunk ?? path;
          if (shrunk != null) temp.add(shrunk);
          List<String> lines;
          try {
            final r = await recognizer.processImage(InputImage.fromFilePath(usable));
            lines = [
              for (final b in r.blocks)
                for (final l in b.lines) l.text,
            ];
          } catch (_) {
            lines = const [];
          }
          out.add(CapturedSide(await File(usable).readAsBytes(), lines));
        }
        return out;
      } finally {
        await recognizer.close();
      }
    } finally {
      for (final p in temp) {
        deleteIfAppTemp(p);
      }
    }
  }
}

/// Background isolate: fix orientation, cap the longest side, JPEG q90.
String? _shrink((String input, String out, int maxSide) args) {
  final (input, out, maxSide) = args;
  try {
    var image = img.decodeImage(File(input).readAsBytesSync());
    if (image == null) return null;
    image = img.bakeOrientation(image);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.cubic)
          : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.cubic);
    }
    File(out).writeAsBytesSync(img.encodeJpg(image, quality: 90));
    return out;
  } catch (_) {
    return null;
  }
}
