import 'dart:convert';
import 'dart:typed_data';

import '../emv/tlv.dart';
import 'mrz.dart';

/// DG1: tag 61 → 5F1F holds the MRZ as one string (90, 72 or 88 characters).
MrzData? parseDg1(Uint8List dg1) {
  final mrz = findTag(parseTlv(dg1), '5F1F');
  if (mrz == null) return null;
  final text = ascii.decode(mrz.value, allowInvalid: true);
  final width = switch (text.length) { 90 => 30, 72 => 36, 88 => 44, _ => 0 };
  if (width == 0) return null;
  return parseMrz([
    for (var i = 0; i < text.length; i += width) text.substring(i, i + width),
  ]);
}

enum FaceImageFormat { jpeg, jpeg2000 }

/// DG2 (ISO/IEC 19794-5 inside a CBEFF wrapper): finds the encoded face image.
/// JPEG can be shown directly; JPEG 2000 (common on passports) cannot be
/// decoded by Flutter on Android, so the caller keeps it but shows a placeholder.
({Uint8List bytes, FaceImageFormat format})? extractFaceImage(Uint8List dg2) {
  final tlvs = parseTlv(dg2);
  final block = findTag(tlvs, '5F2E') ?? findTag(tlvs, '7F2E');
  final data = block?.value ?? dg2;
  for (var i = 0; i + 4 <= data.length; i++) {
    if (data[i] == 0xFF && data[i + 1] == 0xD8 && data[i + 2] == 0xFF) {
      return (bytes: Uint8List.fromList(data.sublist(i)), format: FaceImageFormat.jpeg);
    }
    // JP2 file signature box, or a raw J2K codestream (SOC + SIZ markers).
    if (i + 12 <= data.length &&
        data[i] == 0x00 && data[i + 1] == 0x00 && data[i + 2] == 0x00 && data[i + 3] == 0x0C &&
        data[i + 4] == 0x6A && data[i + 5] == 0x50 && data[i + 6] == 0x20 && data[i + 7] == 0x20) {
      return (bytes: Uint8List.fromList(data.sublist(i)), format: FaceImageFormat.jpeg2000);
    }
    if (data[i] == 0xFF && data[i + 1] == 0x4F && data[i + 2] == 0xFF && data[i + 3] == 0x51) {
      return (bytes: Uint8List.fromList(data.sublist(i)), format: FaceImageFormat.jpeg2000);
    }
  }
  return null;
}

/// Field keys filled from the Vietnamese CCCD DG13 (personal data in
/// Vietnamese, with diacritics). The layout is not published by the issuer;
/// this follows the one observed on chip CCCDs: a list of SEQUENCEs, each
/// starting with an INTEGER index followed by one or more strings.
const Map<int, List<String>> vnDg13Fields = {
  1: ['number'],
  2: ['holder'],
  3: ['dob'],
  4: ['sex'],
  5: ['nationality'],
  6: ['ethnicity'],
  7: ['religion'],
  8: ['hometown'],
  9: ['residence'],
  10: ['features'],
  11: ['issueDate'],
  12: ['expiry'],
  13: ['father', 'mother'],
  14: ['spouse'],
  15: ['oldIdNumber'],
};

/// Best-effort DG13 parse. Unknown indexes are ignored; never throws.
Map<String, String> parseVnDg13(Uint8List dg13) {
  final items = <int, List<String>>{};
  try {
    void visit(Tlv t) {
      if (_isItem(t)) {
        final index = _intValue(t.children.first.value);
        final strings = _strings(t.children.skip(1)).where((s) => s.isNotEmpty).toList();
        if (index != null && strings.isNotEmpty) items.putIfAbsent(index, () => strings);
        return;
      }
      t.children.forEach(visit);
    }

    parseTlv(dg13).forEach(visit);
  } catch (_) {
    return const {};
  }
  final out = <String, String>{};
  items.forEach((index, values) {
    final keys = vnDg13Fields[index];
    if (keys == null) return;
    for (var k = 0; k < keys.length && k < values.length; k++) {
      out[keys[k]] = values[k];
    }
  });
  return out;
}

/// A SEQUENCE that starts with an INTEGER and holds no nested item.
bool _isItem(Tlv t) {
  if (t.tag != '30' || t.children.isEmpty || t.children.first.tag != '02') return false;
  bool hasItem(Tlv x) => x.children.any((c) => _isItem(c) || hasItem(c));
  return !t.children.skip(1).any((c) => _isItem(c) || hasItem(c));
}

int? _intValue(Uint8List v) {
  if (v.isEmpty || v.length > 4) return null;
  var n = 0;
  for (final b in v) {
    n = (n << 8) | b;
  }
  return n;
}

Iterable<String> _strings(Iterable<Tlv> tlvs) sync* {
  for (final t in tlvs) {
    // UTF8String, PrintableString, IA5String, VisibleString, BMPString.
    switch (t.tag) {
      case '0C' || '13' || '16' || '1A':
        yield utf8.decode(t.value, allowMalformed: true).trim();
      case '1E':
        final codes = [for (var i = 0; i + 1 < t.value.length; i += 2) (t.value[i] << 8) | t.value[i + 1]];
        yield String.fromCharCodes(codes).trim();
      default:
        yield* _strings(t.children);
    }
  }
}
