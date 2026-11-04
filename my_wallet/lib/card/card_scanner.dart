import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'card_ocr_parser.dart';

/// Takes a photo of the card (or picks one) and reads it with on-device ML Kit
/// text recognition. Nothing leaves the phone and the photo is deleted after reading.
class CardScanner {
  CardScanner({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Returns null when the user cancels the camera / gallery.
  Future<CardScanResult?> scan({
    bool fromGallery = false,
    void Function()? onPhotoReady,
  }) async {
    final photo = await _picker.pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 2000,
      requestFullMetadata: false,
    );
    if (photo == null) return null;
    onPhotoReady?.call();

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognised = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
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
    } finally {
      await recognizer.close();
      // image_picker hands back a copy in the app cache (camera shot or gallery copy).
      // It shows the full card number, so remove it; never touch the user's original.
      if (photo.path.contains(
        '${Platform.pathSeparator}cache${Platform.pathSeparator}',
      )) {
        try {
          await File(photo.path).delete();
        } catch (_) {}
      }
    }
  }
}
