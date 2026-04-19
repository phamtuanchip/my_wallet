import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_wallet/utils/file_transfer_utils.dart';

void main() {
  group('formatFileSize', () {
    test('formats bytes', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(512), '512 B');
    });

    test('formats KB and MB', () {
      expect(formatFileSize(1024), '1.0 KB');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(1048576), '1.0 MB');
    });
  });

  group('buildUniqueFileName', () {
    test('returns same name when not existing', () async {
      final dir = await Directory.systemTemp.createTemp('file_utils_test_');
      addTearDown(() async => dir.delete(recursive: true));

      final result = await buildUniqueFileName(dir.path, 'hello.txt');
      expect(result, 'hello.txt');
    });

    test('increments when file exists', () async {
      final dir = await Directory.systemTemp.createTemp('file_utils_test_');
      addTearDown(() async => dir.delete(recursive: true));

      final existing = File('${dir.path}${Platform.pathSeparator}hello.txt');
      await existing.writeAsString('x');

      final result = await buildUniqueFileName(dir.path, 'hello.txt');
      expect(result, 'hello (1).txt');
    });

    test('applies fallback extension', () async {
      final dir = await Directory.systemTemp.createTemp('file_utils_test_');
      addTearDown(() async => dir.delete(recursive: true));

      final result =
          await buildUniqueFileName(dir.path, 'payload', fallbackExtension: 'bin');
      expect(result, 'payload.bin');
    });
  });
}
