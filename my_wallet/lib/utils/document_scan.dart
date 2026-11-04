import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// Result of [scanDocumentPage]: a cropped JPEG path, a user cancel, or
/// `unavailable` when the scanner can't run (no Play services / module).
sealed class DocumentScanOutcome {
  const DocumentScanOutcome();
}

class DocumentScanned extends DocumentScanOutcome {
  const DocumentScanned(this.path);
  final String path;
}

class DocumentScanCancelled extends DocumentScanOutcome {
  const DocumentScanCancelled();
}

class DocumentScanUnavailable extends DocumentScanOutcome {
  const DocumentScanUnavailable();
}

/// Google's ML Kit Document Scanner (on-device, Play services): finds the
/// card/page edges, crops and deskews it. One page per call.
Future<DocumentScanOutcome> scanDocumentPage() async {
  final scanner = DocumentScanner(
    options: DocumentScannerOptions(
      documentFormats: const {DocumentFormat.jpeg},
      mode: ScannerMode.filter, // crop + deskew + filters, no ML clean-up model download
      pageLimit: 1,
      isGalleryImport: false,
    ),
  );
  try {
    final result = await scanner.scanDocument();
    final images = result.images ?? const [];
    return images.isEmpty ? const DocumentScanCancelled() : DocumentScanned(images.first);
  } on PlatformException catch (e) {
    if ((e.message ?? '').toLowerCase().contains('cancel')) return const DocumentScanCancelled();
    return const DocumentScanUnavailable();
  } on MissingPluginException {
    return const DocumentScanUnavailable();
  } finally {
    await scanner.close();
  }
}

/// Only delete files inside the app's cache (never a user's gallery original).
void deleteIfAppTemp(String path) {
  final sep = Platform.pathSeparator;
  if (path.contains('${sep}cache$sep') || path.contains('${sep}tmp$sep')) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }
}
