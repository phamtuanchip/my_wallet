import 'dart:io';
import 'package:path/path.dart' as p;

String formatFileSize(int sizeBytes) {
  if (sizeBytes <= 0) return '0 B';
  if (sizeBytes < 1024) return '$sizeBytes B';
  if (sizeBytes < 1024 * 1024) {
    return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Future<String> buildUniqueFileName(
  String directoryPath,
  String originalName, {
  String fallbackExtension = 'bin',
}) async {
  final extension = p.extension(originalName).replaceFirst('.', '');
  final usedExtension = extension.isNotEmpty ? extension : fallbackExtension;
  final baseName = extension.isNotEmpty
      ? originalName.substring(0, originalName.length - extension.length - 1)
      : originalName;

  String fileName = extension.isNotEmpty ? originalName : '$originalName.$usedExtension';
  int counter = 1;

  while (await File(p.join(directoryPath, fileName)).exists()) {
    fileName = '$baseName ($counter).$usedExtension';
    counter++;
  }

  return fileName;
}
