import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../emv/emv_reader.dart' show Transceive;
import 'mrz.dart';

/// Basic Access Control + 3DES Secure Messaging for eMRTD chips
/// (ICAO Doc 9303 Part 11, sections 4.3 and 9.8). Used by passports and the
/// Vietnamese chip CCCD. Keys come from the MRZ, so a chip can only be read by
/// someone who can see the document.

/// The three MRZ fields that make the BAC key. Dates are `YYMMDD`.
class BacKey {
  BacKey(String documentNumber, this.birthDate, this.expiryDate)
      : documentNumber = documentNumber.toUpperCase().replaceAll(' ', '');

  final String documentNumber;
  final String birthDate;
  final String expiryDate;

  /// `MRZ_information`: number (padded to 9 with `<`) + dates, each with its check digit.
  String get mrzInformation {
    final doc = documentNumber.padRight(9, '<');
    return '$doc${mrzCheckDigit(doc)}'
        '$birthDate${mrzCheckDigit(birthDate)}'
        '$expiryDate${mrzCheckDigit(expiryDate)}';
  }

  bool get isComplete =>
      documentNumber.isNotEmpty &&
      RegExp(r'^\d{6}$').hasMatch(birthDate) &&
      RegExp(r'^\d{6}$').hasMatch(expiryDate);
}

class BacException implements Exception {
  const BacException(this.message, {this.sw});
  final String message;
  final int? sw;
  @override
  String toString() => 'BacException($message${sw == null ? '' : ', SW ${sw!.toRadixString(16)}'})';
}

/// Secure-messaging integrity or protocol failure (also when the card moved away mid-read).
class SecureMessagingException implements Exception {
  const SecureMessagingException(this.message);
  final String message;
  @override
  String toString() => 'SecureMessagingException($message)';
}

// ── Primitives ──────────────────────────────────────────────────────────

Uint8List _sha1(List<int> data) => SHA1Digest().process(Uint8List.fromList(data));

/// Key derivation (9303-11 §9.7.1): SHA-1(seed || counter), first 16 bytes, DES parity.
Uint8List deriveKey(List<int> seed, int counter) {
  final digest = _sha1([...seed, 0, 0, 0, counter]);
  return _adjustParity(digest.sublist(0, 16));
}

Uint8List _adjustParity(Uint8List key) {
  final out = Uint8List.fromList(key);
  for (var i = 0; i < out.length; i++) {
    final b = out[i];
    var ones = 0;
    for (var k = 1; k < 8; k++) {
      if ((b >> k) & 1 == 1) ones++;
    }
    out[i] = (b & 0xFE) | (ones % 2 == 0 ? 1 : 0);
  }
  return out;
}

/// `K_seed` = first 16 bytes of SHA-1(MRZ_information).
Uint8List bacKeySeed(BacKey key) => _sha1(key.mrzInformation.codeUnits).sublist(0, 16);

/// ISO/IEC 9797-1 padding method 2: `80` then zeros to a multiple of 8.
Uint8List pad(List<int> data) {
  final len = (data.length ~/ 8 + 1) * 8;
  final out = Uint8List(len)..setAll(0, data);
  out[data.length] = 0x80;
  return out;
}

Uint8List unpad(Uint8List data) {
  var i = data.length - 1;
  while (i >= 0 && data[i] == 0x00) {
    i--;
  }
  if (i < 0 || data[i] != 0x80) throw const SecureMessagingException('bad padding');
  return data.sublist(0, i);
}

Uint8List _tdesCbc(Uint8List key16, Uint8List data, {required bool encrypt}) {
  if (data.length % 8 != 0) throw const SecureMessagingException('not block aligned');
  final cipher = CBCBlockCipher(DESedeEngine())
    ..init(encrypt, ParametersWithIV(KeyParameter(key16), Uint8List(8)));
  final out = Uint8List(data.length);
  for (var off = 0; off < data.length; off += 8) {
    cipher.processBlock(data, off, out, off);
  }
  return out;
}

Uint8List tdesEncrypt(Uint8List key16, Uint8List data) => _tdesCbc(key16, data, encrypt: true);
Uint8List tdesDecrypt(Uint8List key16, Uint8List data) => _tdesCbc(key16, data, encrypt: false);

/// ISO/IEC 9797-1 MAC algorithm 3 ("retail MAC") with DES, padding method 2.
/// Single DES (K1) over every block, then 2-key 3DES on the last one.
Uint8List retailMac(Uint8List key16, List<int> message) {
  final data = pad(message);
  final k1 = key16.sublist(0, 8);
  final single = DESedeEngine()..init(true, KeyParameter(Uint8List.fromList([...k1, ...k1])));
  final triple = DESedeEngine()..init(true, KeyParameter(key16));
  var h = Uint8List(8);
  for (var off = 0; off < data.length; off += 8) {
    final x = Uint8List(8);
    for (var i = 0; i < 8; i++) {
      x[i] = h[i] ^ data[off + i];
    }
    final out = Uint8List(8);
    (off + 8 == data.length ? triple : single).processBlock(x, 0, out, 0);
    h = out;
  }
  return h;
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

List<int> _berLength(int n) {
  if (n < 0x80) return [n];
  if (n <= 0xFF) return [0x81, n];
  return [0x82, n >> 8, n & 0xFF];
}

// ── Secure messaging ────────────────────────────────────────────────────

/// Wraps plain APDUs into protected ones and checks/decrypts the responses.
class SecureMessaging {
  SecureMessaging(this.ksEnc, this.ksMac, Uint8List ssc) : _ssc = Uint8List.fromList(ssc);

  final Uint8List ksEnc;
  final Uint8List ksMac;
  final Uint8List _ssc;

  Uint8List get ssc => Uint8List.fromList(_ssc);

  void _incrementSsc() {
    for (var i = _ssc.length - 1; i >= 0; i--) {
      _ssc[i] = (_ssc[i] + 1) & 0xFF;
      if (_ssc[i] != 0) break;
    }
  }

  /// Short APDUs only (cases 1–4), even INS (DO87).
  Uint8List wrap(Uint8List apdu) {
    if (apdu.length < 4) throw ArgumentError('APDU too short');
    final header = [apdu[0] | 0x0C, apdu[1], apdu[2], apdu[3]];
    List<int> data = const [];
    int? le;
    if (apdu.length == 5) {
      le = apdu[4];
    } else if (apdu.length > 5) {
      final lc = apdu[4];
      data = apdu.sublist(5, 5 + lc);
      if (apdu.length > 5 + lc) le = apdu[5 + lc];
    }

    _incrementSsc();
    final do87 = <int>[];
    if (data.isNotEmpty) {
      final enc = tdesEncrypt(ksEnc, pad(data));
      do87
        ..add(0x87)
        ..addAll(_berLength(enc.length + 1))
        ..add(0x01)
        ..addAll(enc);
    }
    final do97 = le == null ? const <int>[] : [0x97, 0x01, le];
    final m = [...pad(header), ...do87, ...do97];
    final cc = retailMac(ksMac, [..._ssc, ...m]);
    final body = [...do87, ...do97, 0x8E, 0x08, ...cc];
    return Uint8List.fromList([...header, body.length, ...body, 0x00]);
  }

  /// Returns the plain response data followed by SW1 SW2.
  Uint8List unwrap(Uint8List response) {
    if (response.length < 2) throw const SecureMessagingException('empty response');
    _incrementSsc();
    final body = response.sublist(0, response.length - 2);
    if (body.isEmpty) {
      // Plain status word: the card dropped secure messaging (e.g. 6982, 6A82).
      return response;
    }
    List<int>? do87Raw;
    Uint8List? do87Value;
    List<int>? do99Raw;
    Uint8List? mac;
    var i = 0;
    while (i < body.length) {
      final tag = body[i];
      var j = i + 1;
      if (j >= body.length) break;
      var len = body[j++];
      if (len == 0x81) {
        len = body[j++];
      } else if (len == 0x82) {
        len = (body[j] << 8) | body[j + 1];
        j += 2;
      }
      if (j + len > body.length) throw const SecureMessagingException('truncated response');
      final value = Uint8List.fromList(body.sublist(j, j + len));
      final raw = body.sublist(i, j + len);
      if (tag == 0x87) {
        do87Raw = raw;
        do87Value = value;
      } else if (tag == 0x99) {
        do99Raw = raw;
      } else if (tag == 0x8E) {
        mac = value;
      }
      i = j + len;
    }
    if (mac == null) throw const SecureMessagingException('missing MAC');
    final k = [..._ssc, ...?do87Raw, ...?do99Raw];
    if (!_equal(retailMac(ksMac, k), mac)) {
      throw const SecureMessagingException('MAC mismatch');
    }
    final sw = do99Raw != null ? do99Raw.sublist(do99Raw.length - 2) : response.sublist(response.length - 2);
    Uint8List plain = Uint8List(0);
    if (do87Value != null) {
      if (do87Value.isEmpty || do87Value[0] != 0x01) {
        throw const SecureMessagingException('unknown padding indicator');
      }
      plain = unpad(tdesDecrypt(ksEnc, do87Value.sublist(1)));
    }
    return Uint8List.fromList([...plain, ...sw]);
  }
}

// ── BAC handshake ───────────────────────────────────────────────────────

/// Runs GET CHALLENGE + EXTERNAL AUTHENTICATE (the eMRTD applet must already be
/// selected) and returns the secure-messaging session. [random] is injectable
/// for the ICAO test vectors.
Future<SecureMessaging> performBac(
  Transceive tx,
  BacKey key, {
  Uint8List Function(int length)? random,
}) async {
  final rnd = random ?? _secureRandom;
  final seed = bacKeySeed(key);
  final kEnc = deriveKey(seed, 1);
  final kMac = deriveKey(seed, 2);

  final challenge = await tx(Uint8List.fromList([0x00, 0x84, 0x00, 0x00, 0x08]));
  final csw = _sw(challenge);
  if (csw != 0x9000 || challenge.length != 10) {
    throw BacException('GET CHALLENGE failed', sw: csw);
  }
  final rndIc = challenge.sublist(0, 8);
  final rndIfd = rnd(8);
  final kIfd = rnd(16);

  final eIfd = tdesEncrypt(kEnc, Uint8List.fromList([...rndIfd, ...rndIc, ...kIfd]));
  final mIfd = retailMac(kMac, eIfd);
  final resp = await tx(Uint8List.fromList([0x00, 0x82, 0x00, 0x00, 0x28, ...eIfd, ...mIfd, 0x28]));
  final sw = _sw(resp);
  if (sw != 0x9000 || resp.length != 42) {
    // 6300 / 6982: the chip did not accept the key, i.e. number or dates are wrong.
    throw BacException('access denied', sw: sw);
  }
  final eIc = resp.sublist(0, 32);
  if (!_equal(retailMac(kMac, eIc), resp.sublist(32, 40))) {
    throw const BacException('chip MAC mismatch');
  }
  final r = tdesDecrypt(kEnc, Uint8List.fromList(eIc));
  if (!_equal(r.sublist(0, 8), rndIc) || !_equal(r.sublist(8, 16), rndIfd)) {
    throw const BacException('chip answered a different challenge');
  }
  final kIc = r.sublist(16, 32);
  final sessionSeed = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    sessionSeed[i] = kIfd[i] ^ kIc[i];
  }
  return SecureMessaging(
    deriveKey(sessionSeed, 1),
    deriveKey(sessionSeed, 2),
    Uint8List.fromList([...rndIc.sublist(4), ...rndIfd.sublist(4)]),
  );
}

int _sw(Uint8List r) => r.length < 2 ? 0 : (r[r.length - 2] << 8) | r[r.length - 1];

final Random _rng = Random.secure();
Uint8List _secureRandom(int n) => Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));
