import 'dart:typed_data';

import '../emv/emv_reader.dart' show Transceive;
import 'bac.dart';
import 'data_groups.dart';
import 'mrz.dart';

/// What was read from an eMRTD chip (passport or chip CCCD).
class EmrtdData {
  const EmrtdData({
    required this.mrz,
    this.faceImage,
    this.faceFormat,
    this.vnPersonal = const {},
  });

  final MrzData mrz;
  final Uint8List? faceImage;
  final FaceImageFormat? faceFormat;

  /// Vietnamese CCCD only (DG13): name with diacritics, address, parents…
  final Map<String, String> vnPersonal;
}

enum EmrtdStep { connecting, authenticating, readingData, readingPhoto, readingPersonal, done }

/// The chip refused the key: document number, birth date or expiry is wrong.
class EmrtdAccessDenied implements Exception {
  const EmrtdAccessDenied();
}

/// Reads an eMRTD over ISO-DEP: SELECT applet → BAC → DG1, DG2 (+ DG13).
/// Read-only. Passive authentication (SOD signature check) is not done yet,
/// so the data is trusted as much as the physical document in your hand.
class EmrtdReader {
  EmrtdReader(this._tx, {Uint8List Function(int length)? random}) : _random = random;

  final Transceive _tx;
  final Uint8List Function(int length)? _random;

  static final Uint8List _selectApplet =
      Uint8List.fromList([0x00, 0xA4, 0x04, 0x0C, 0x07, 0xA0, 0x00, 0x00, 0x02, 0x47, 0x10, 0x01]);

  static const int fidDg1 = 0x0101;
  static const int fidDg2 = 0x0102;
  static const int fidDg13 = 0x010D;

  /// Largest READ BINARY chunk that still fits a short secure-messaging response.
  static const int _chunk = 0xDF;

  /// True when the card has the ICAO eMRTD application (passport / chip ID).
  static Future<bool> probe(Transceive tx) async {
    try {
      final r = await tx(_selectApplet);
      return r.length >= 2 && r[r.length - 2] == 0x90 && r[r.length - 1] == 0x00;
    } catch (_) {
      return false;
    }
  }

  Future<EmrtdData> read(
    BacKey key, {
    bool readPhoto = true,
    bool readVnPersonal = false,
    void Function(EmrtdStep step, double progress)? onProgress,
  }) async {
    void report(EmrtdStep s, double p) => onProgress?.call(s, p);

    report(EmrtdStep.connecting, 0.02);
    final sel = await _tx(_selectApplet);
    if (_sw(sel) != 0x9000) throw const SecureMessagingException('not an eMRTD');

    report(EmrtdStep.authenticating, 0.06);
    final SecureMessaging sm;
    try {
      sm = await performBac(_tx, key, random: _random);
    } on BacException catch (e) {
      if (e.message == 'access denied') throw const EmrtdAccessDenied();
      rethrow;
    }

    report(EmrtdStep.readingData, 0.1);
    final dg1 = await _readFile(sm, fidDg1);
    final mrz = parseDg1(dg1);
    if (mrz == null) throw const SecureMessagingException('DG1 has no MRZ');

    Uint8List? face;
    FaceImageFormat? format;
    if (readPhoto) {
      final dg2 = await _readFile(sm, fidDg2, onChunk: (p) => report(EmrtdStep.readingPhoto, 0.15 + p * 0.7));
      final img = extractFaceImage(dg2);
      face = img?.bytes;
      format = img?.format;
    }

    var personal = const <String, String>{};
    if (readVnPersonal) {
      report(EmrtdStep.readingPersonal, 0.88);
      try {
        personal = parseVnDg13(await _readFile(sm, fidDg13));
      } on _FileMissing {
        // Passports and some IDs have no DG13.
      }
    }
    report(EmrtdStep.done, 1);
    return EmrtdData(mrz: mrz, faceImage: face, faceFormat: format, vnPersonal: personal);
  }

  Future<Uint8List> _send(SecureMessaging sm, List<int> apdu) async =>
      sm.unwrap(await _tx(sm.wrap(Uint8List.fromList(apdu))));

  Future<Uint8List> _readFile(SecureMessaging sm, int fid, {void Function(double)? onChunk}) async {
    final sel = await _send(sm, [0x00, 0xA4, 0x02, 0x0C, 0x02, fid >> 8, fid & 0xFF]);
    final sw = _sw(sel);
    if (sw == 0x6A82) throw _FileMissing();
    if (sw != 0x9000) throw SecureMessagingException('SELECT ${fid.toRadixString(16)} → ${sw.toRadixString(16)}');

    final head = _data(await _readBinary(sm, 0, 4));
    if (head.length < 2) throw const SecureMessagingException('empty file');
    final total = _tlvTotalLength(head);
    final out = BytesBuilder(copy: false)..add(head);
    var offset = head.length;
    while (offset < total) {
      final n = (total - offset) < _chunk ? total - offset : _chunk;
      final r = await _readBinary(sm, offset, n);
      final chunk = _data(r);
      if (chunk.isEmpty) break;
      out.add(chunk);
      offset += chunk.length;
      onChunk?.call(offset / total);
    }
    return out.takeBytes();
  }

  Future<Uint8List> _readBinary(SecureMessaging sm, int offset, int length) async {
    if (offset > 0x7FFF) throw const SecureMessagingException('file too large');
    final r = await _send(sm, [0x00, 0xB0, offset >> 8, offset & 0xFF, length]);
    final sw = _sw(r);
    if (sw != 0x9000 && sw != 0x6282) {
      throw SecureMessagingException('READ BINARY → ${sw.toRadixString(16)}');
    }
    return r;
  }

  /// Tag (1 or 2 bytes) + BER length → size of the whole file.
  static int _tlvTotalLength(Uint8List h) {
    var i = (h[0] & 0x1F) == 0x1F ? 2 : 1;
    if (i >= h.length) throw const SecureMessagingException('bad file header');
    final first = h[i++];
    if (first < 0x80) return i + first;
    final n = first & 0x7F;
    if (n > 2 || i + n > h.length) throw const SecureMessagingException('unsupported length');
    var len = 0;
    for (var k = 0; k < n; k++) {
      len = (len << 8) | h[i++];
    }
    return i + len;
  }

  static int _sw(Uint8List r) => r.length < 2 ? 0 : (r[r.length - 2] << 8) | r[r.length - 1];
  static Uint8List _data(Uint8List r) => r.sublist(0, r.length - 2);
}

class _FileMissing implements Exception {}
