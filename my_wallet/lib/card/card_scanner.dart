import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/document_scan.dart';
import 'card_ocr_parser.dart';

/// Captures the front of a card and reads it with on-device ML Kit.
///
/// Camera: Google's ML Kit Document Scanner (Play services, on-device) finds the
/// card edges, crops and deskews it. Falls back to the plain camera if the
/// scanner is unavailable. The image is then read in several OCR passes
/// (original, grey + contrast, rotated 180° if no number yet) and merged.
/// Nothing leaves the phone; every temporary image is deleted afterwards.
class CardScanner {
  CardScanner({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Returns null when the user cancels.
  Future<CardScanResult?> scan({bool fromGallery = false, void Function()? onPhotoReady}) async {
    final temp = <String>[];
    try {
      String? path;
      if (fromGallery) {
        final photo = await _picker.pickImage(source: ImageSource.gallery, requestFullMetadata: false);
        path = photo?.path;
      } else {
        switch (await scanDocumentPage()) {
          case DocumentScanCancelled():
            return null;
          case DocumentScanned(path: final scanned):
            path = scanned;
          case DocumentScanUnavailable():
            break;
        }
        path ??= (await _picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          maxWidth: 2000,
          requestFullMetadata: false,
        ))
            ?.path;
      }
      if (path == null) return null;
      temp.add(path);
      onPhotoReady?.call();

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final passes = <CardScanResult>[await _ocr(recognizer, path)];
        final dir = (await getTemporaryDirectory()).path;
        final stamp = DateTime.now().microsecondsSinceEpoch;

        final enhanced = await compute(_enhance, (path, '$dir/card_enh_$stamp.jpg', false));
        if (enhanced != null) {
          temp.add(enhanced);
          passes.add(await _ocr(recognizer, enhanced));
        }
        if (!passes.any((p) => p.numberVerified)) {
          final rotated = await compute(_enhance, (path, '$dir/card_rot_$stamp.jpg', true));
          if (rotated != null) {
            temp.add(rotated);
            passes.add(await _ocr(recognizer, rotated));
          }
        }
        return mergeScanResults(passes);
      } finally {
        await recognizer.close();
      }
    } finally {
      for (final p in temp) {
        deleteIfAppTemp(p);
      }
    }
  }

  Future<CardScanResult> _ocr(TextRecognizer recognizer, String path) async {
    final recognised = await recognizer.processImage(InputImage.fromFilePath(path));
    final pieces = [
      for (final block in recognised.blocks)
        for (final line in block.lines)
          (
            text: line.text,
            top: line.boundingBox.top,
            bottom: line.boundingBox.bottom,
            left: line.boundingBox.left,
          ),
    ];
    return parseCardText(groupTextRows(pieces));
  }
}

/// Runs in a background isolate: grey + contrast boost (helps embossed and
/// glossy cards), optionally rotated 180°, written as JPEG to `out`.
String? _enhance((String input, String out, bool rotate) args) {
  final (input, out, rotate) = args;
  try {
    var image = img.decodeImage(File(input).readAsBytesSync());
    if (image == null) return null;
    image = img.bakeOrientation(image);
    if (image.width > 1800) image = img.copyResize(image, width: 1800);
    if (rotate) image = img.copyRotate(image, angle: 180);
    image = img.grayscale(image);
    image = img.adjustColor(image, contrast: 1.6);
    File(out).writeAsBytesSync(img.encodeJpg(image, quality: 92));
    return out;
  } catch (_) {
    return null;
  }
}
