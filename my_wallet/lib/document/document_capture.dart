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

/// Takes a photo of a document side (Document Scanner → crop + deskew, plain
/// camera as fallback, or the gallery) and reads its text on-device.
/// Temporary files are deleted; only the returned bytes remain, in memory.
class DocumentCapture {
  DocumentCapture({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Null when the user cancels.
  Future<CapturedSide?> capture({bool fromGallery = false}) async {
    final temp = <String>[];
    try {
      String? path;
      if (fromGallery) {
        path = (await _picker.pickImage(source: ImageSource.gallery, requestFullMetadata: false))?.path;
      } else {
        switch (await scanDocumentPage()) {
          case DocumentScanCancelled():
            return null;
          case DocumentScanned(path: final scanned):
            path = scanned;
          case DocumentScanUnavailable():
            path = (await _picker.pickImage(
              source: ImageSource.camera,
              preferredCameraDevice: CameraDevice.rear,
              maxWidth: 2200,
              requestFullMetadata: false,
            ))
                ?.path;
        }
      }
      if (path == null) return null;
      temp.add(path);

      final out = '${(await getTemporaryDirectory()).path}/doc_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final shrunk = await compute(_shrink, (path, out));
      final usable = shrunk ?? path;
      if (shrunk != null) temp.add(shrunk);

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      List<String> lines;
      try {
        final r = await recognizer.processImage(InputImage.fromFilePath(usable));
        lines = [
          for (final b in r.blocks)
            for (final l in b.lines) l.text,
        ];
      } catch (_) {
        lines = const [];
      } finally {
        await recognizer.close();
      }
      return CapturedSide(await File(usable).readAsBytes(), lines);
    } finally {
      for (final p in temp) {
        deleteIfAppTemp(p);
      }
    }
  }
}

/// Background isolate: fix orientation, cap at 1800 px, JPEG q88 (keeps text
/// readable at ~300–600 KB instead of several MB).
String? _shrink((String input, String out) args) {
  final (input, out) = args;
  try {
    var image = img.decodeImage(File(input).readAsBytesSync());
    if (image == null) return null;
    image = img.bakeOrientation(image);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > 1800) {
      image = image.width >= image.height
          ? img.copyResize(image, width: 1800)
          : img.copyResize(image, height: 1800);
    }
    File(out).writeAsBytesSync(img.encodeJpg(image, quality: 88));
    return out;
  } catch (_) {
    return null;
  }
}
