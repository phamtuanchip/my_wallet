import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../security/vault_crypto.dart';
import 'id_document.dart';

/// DB v5 (v1.4.0). Only the kind, a title and the last 4 characters of the
/// number are in clear; every field and photo is AES-256-GCM encrypted.
const String kDocumentsTableSql = '''
  CREATE TABLE IF NOT EXISTS documents (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    number_last4 TEXT,
    has_chip_data INTEGER NOT NULL DEFAULT 0,
    data_enc TEXT,
    front_file TEXT,
    back_file TEXT,
    face_file TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
''';

class DocumentStore {
  DocumentStore(this._db, this._vault, {Future<Directory> Function()? baseDir})
      : _baseDir = baseDir ?? getApplicationSupportDirectory;

  final Database _db;
  final VaultCrypto _vault;
  final Future<Directory> Function() _baseDir;
  Directory? _dir;

  /// Private app storage (not the gallery, not backed up: allowBackup=false).
  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final dir = Directory('${(await _baseDir()).path}${Platform.pathSeparator}documents');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<List<IdDocument>> list() async {
    final rows = await _db.query('documents', orderBy: 'updated_at DESC');
    return rows.map(IdDocument.fromMap).toList();
  }

  /// Decrypts fields and photos. Call only after the user unlocked.
  Future<DocumentContent> open(IdDocument doc) async {
    final fields = <String, String>{};
    if (doc.dataEnc != null) {
      final decoded = jsonDecode(await _vault.decrypt(doc.dataEnc!)) as Map<String, dynamic>;
      decoded.forEach((k, v) {
        if (v is String) fields[k] = v;
      });
    }
    return DocumentContent(
      kind: doc.kind,
      title: doc.title,
      fields: fields,
      front: await _readImage(doc.frontFile),
      back: await _readImage(doc.backFile),
      face: await _readImage(doc.faceFile),
      hasChipData: doc.hasChipData,
    );
  }

  /// Inserts or replaces. Photos are re-encrypted into new files, then the old
  /// files are deleted, so a crash mid-save never loses the previous version.
  Future<String> save(DocumentContent c, {IdDocument? existing}) async {
    final id = existing?.id ?? const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanFields = {
      for (final e in c.fields.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    };
    final row = <String, Object?>{
      'id': id,
      'kind': c.kind.name,
      'title': c.title.trim().isEmpty ? c.defaultTitle : c.title.trim(),
      'number_last4': maskedTail(c.number),
      'has_chip_data': c.hasChipData ? 1 : 0,
      'data_enc': await _vault.encrypt(jsonEncode(cleanFields)),
      'front_file': await _writeImage(id, 'front', c.front),
      'back_file': await _writeImage(id, 'back', c.back),
      'face_file': await _writeImage(id, 'face', c.face),
      'created_at': existing?.createdAt.millisecondsSinceEpoch ?? now,
      'updated_at': now,
    };
    await _db.insert('documents', row, conflictAlgorithm: ConflictAlgorithm.replace);
    if (existing != null) {
      for (final f in [existing.frontFile, existing.backFile, existing.faceFile]) {
        await _deleteFile(f);
      }
    }
    return id;
  }

  Future<void> delete(IdDocument doc) async {
    await _db.delete('documents', where: 'id = ?', whereArgs: [doc.id]);
    for (final f in [doc.frontFile, doc.backFile, doc.faceFile]) {
      await _deleteFile(f);
    }
  }

  Future<String?> _writeImage(String id, String side, Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    final name = '${id}_${side}_${DateTime.now().microsecondsSinceEpoch}.enc';
    final file = File('${(await _folder()).path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(await _vault.encryptBytes(bytes), flush: true);
    return name;
  }

  Future<Uint8List?> _readImage(String? name) async {
    if (name == null) return null;
    final file = File('${(await _folder()).path}${Platform.pathSeparator}$name');
    if (!await file.exists()) return null;
    return _vault.decryptBytes(await file.readAsBytes());
  }

  Future<void> _deleteFile(String? name) async {
    if (name == null || name.contains('/') || name.contains(r'\')) return;
    final file = File('${(await _folder()).path}${Platform.pathSeparator}$name');
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
