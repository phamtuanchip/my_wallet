import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the 256-bit data key lives. Production: Android Keystore / iOS Keychain
/// through flutter_secure_storage. Tests: in memory.
abstract class VaultKeyStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureVaultKeyStore implements VaultKeyStore {
  SecureVaultKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _name = 'vault_data_key_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _name);

  @override
  Future<void> write(String value) => _storage.write(key: _name, value: value);
}

class MemoryVaultKeyStore implements VaultKeyStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;
}

/// Encrypts card secrets (full number, CVV) with AES-256-GCM before they go
/// into SQLite. Token format: `v1:<base64(nonce | ciphertext | mac)>`.
class VaultCrypto {
  VaultCrypto(this._store);

  static const _prefix = 'v1:';
  final VaultKeyStore _store;
  final AesGcm _algo = AesGcm.with256bits();
  Future<SecretKey>? _key;

  Future<SecretKey> _loadKey() => _key ??= () async {
        final existing = await _store.read();
        if (existing != null) return SecretKey(base64Decode(existing));
        final rnd = Random.secure();
        final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
        await _store.write(base64Encode(bytes));
        return SecretKey(bytes);
      }();

  Future<String> encrypt(String plain) async {
    final box = await _algo.encrypt(utf8.encode(plain), secretKey: await _loadKey());
    return _prefix + base64Encode(box.concatenation());
  }

  /// Throws if the token was not produced with this device's key.
  Future<String> decrypt(String token) async {
    if (!token.startsWith(_prefix)) {
      throw const FormatException('Unknown vault token version');
    }
    final box = SecretBox.fromConcatenation(
      base64Decode(token.substring(_prefix.length)),
      nonceLength: _algo.nonceLength,
      macLength: _algo.macAlgorithm.macLength,
    );
    return utf8.decode(await _algo.decrypt(box, secretKey: await _loadKey()));
  }
}
