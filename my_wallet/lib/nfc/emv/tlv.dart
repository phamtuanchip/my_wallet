import 'dart:typed_data';

/// One BER-TLV element (EMV Book 3, Annex B). [tag] is upper-case hex, e.g. `5F24`.
class Tlv {
  Tlv(this.tag, this.value, this.children);

  final String tag;
  final Uint8List value;
  final List<Tlv> children;

  bool get isConstructed => children.isNotEmpty;
}

String toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

Uint8List fromHex(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Parses a BER-TLV byte string. Constructed elements are parsed recursively.
/// Malformed tails are ignored rather than throwing: card data is untrusted.
List<Tlv> parseTlv(List<int> data) {
  final out = <Tlv>[];
  var i = 0;
  while (i < data.length) {
    final first = data[i];
    if (first == 0x00 || first == 0xFF) {
      i++; // padding between elements
      continue;
    }
    final tagStart = i;
    i++;
    if ((first & 0x1F) == 0x1F) {
      while (i < data.length && (data[i] & 0x80) != 0) {
        i++;
      }
      i++;
    }
    if (i >= data.length) break;
    final tag = toHex(data.sublist(tagStart, i));

    var len = data[i++];
    if (len & 0x80 != 0) {
      final n = len & 0x7F;
      if (n == 0 || n > 3 || i + n > data.length) break;
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | data[i++];
      }
    }
    if (i + len > data.length) break;
    final value = Uint8List.fromList(data.sublist(i, i + len));
    i += len;

    final constructed = (first & 0x20) != 0;
    out.add(Tlv(tag, value, constructed ? parseTlv(value) : const []));
  }
  return out;
}

/// Depth-first search for the first element with [tag].
Tlv? findTag(List<Tlv> tlvs, String tag) {
  for (final t in tlvs) {
    if (t.tag == tag) return t;
    final inner = findTag(t.children, tag);
    if (inner != null) return inner;
  }
  return null;
}

/// All elements with [tag], depth-first.
List<Tlv> findAll(List<Tlv> tlvs, String tag) => [
      for (final t in tlvs) ...[
        if (t.tag == tag) t,
        ...findAll(t.children, tag),
      ],
    ];

/// A Data Object List (PDOL, CDOL…): tags with requested lengths, no values.
List<({String tag, int length})> parseDol(List<int> data) {
  final out = <({String tag, int length})>[];
  var i = 0;
  while (i < data.length) {
    final start = i;
    final first = data[i++];
    if ((first & 0x1F) == 0x1F) {
      while (i < data.length && (data[i] & 0x80) != 0) {
        i++;
      }
      i++;
    }
    if (i >= data.length) break;
    out.add((tag: toHex(data.sublist(start, i)), length: data[i++]));
  }
  return out;
}
