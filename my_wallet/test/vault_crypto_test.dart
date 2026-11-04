import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_wallet/card/card_color.dart';
import 'package:my_wallet/security/vault_crypto.dart';

void main() {
  group('VaultCrypto', () {
    test('round-trips and never stores the plain value', () async {
      final store = MemoryVaultKeyStore();
      final vault = VaultCrypto(store);
      final token = await vault.encrypt('4111111111111111');

      expect(token, startsWith('v1:'));
      expect(token, isNot(contains('4111')));
      expect(await vault.decrypt(token), '4111111111111111');
      expect(store.value, isNotNull); // key was created once and persisted
    });

    test('same plain text encrypts differently each time (random nonce)', () async {
      final vault = VaultCrypto(MemoryVaultKeyStore());
      expect(await vault.encrypt('123'), isNot(await vault.encrypt('123')));
    });

    test('a new instance with the same stored key can decrypt', () async {
      final store = MemoryVaultKeyStore();
      final token = await VaultCrypto(store).encrypt('987');
      expect(await VaultCrypto(store).decrypt(token), '987');
    });

    test('fingerprint is stable per key and does not reveal the number', () async {
      final store = MemoryVaultKeyStore();
      final a = await VaultCrypto(store).fingerprint('4111111111111111');
      expect(await VaultCrypto(store).fingerprint('4111111111111111'), a);
      expect(await VaultCrypto(store).fingerprint('4111111111111112'), isNot(a));
      expect(await VaultCrypto(MemoryVaultKeyStore()).fingerprint('4111111111111111'), isNot(a));
      expect(a, isNot(contains('4111')));
    });

    test('a different key cannot decrypt', () async {
      final token = await VaultCrypto(MemoryVaultKeyStore()).encrypt('987');
      expect(() => VaultCrypto(MemoryVaultKeyStore()).decrypt(token), throwsA(anything));
    });
  });

  group('pickDistinctCardColor', () {
    test('never repeats a colour and spreads hues apart', () {
      final rnd = Random(42);
      final used = <int>[];
      for (var i = 0; i < 12; i++) {
        final c = pickDistinctCardColor(used, random: rnd);
        expect(used, isNot(contains(c)));
        expect(c, greaterThanOrEqualTo(kCardColors.length)); // ARGB, not a preset index
        used.add(c);
      }
      // With 6 cards the closest pair of hues should still be clearly apart.
      final hues = used.take(6).map((v) => HSLColor.fromColor(Color(v)).hue).toList();
      var minGap = 360.0;
      for (var i = 0; i < hues.length; i++) {
        for (var j = i + 1; j < hues.length; j++) {
          final d = (hues[i] - hues[j]).abs();
          minGap = min(minGap, d > 180 ? 360 - d : d);
        }
      }
      expect(minGap, greaterThan(20));
    });

    test('legacy preset indexes still resolve', () {
      expect(cardColorFromValue(0), kCardColors[0]);
      expect(cardColorFromValue(0xFF123456), const Color(0xFF123456));
    });
  });
}
