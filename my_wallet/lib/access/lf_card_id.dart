/// 125 kHz proximity card IDs (EM4100 / EM4102, and T5577 cards written as
/// EM4100). A phone's NFC (13.56 MHz) cannot read these; the ID comes from a
/// USB/OTG "keyboard" reader or from the number printed on the card.
///
/// EM4100 carries 40 bits: 1 version/customer byte + a 32-bit ID. Cards and
/// readers show the 32-bit part as 10 decimal digits (`0004335038`) and/or as
/// Wiegand-26 `facility,card` (`066,09662` = bits 16–23 and 0–15).
class LfCardId {
  const LfCardId({this.version, this.id32, this.facility, this.cardNumber});

  /// First byte of the 40-bit EM4100 ID, only known from a 10-hex-digit read.
  final int? version;

  /// Lower 32 bits; null when only Wiegand-26 numbers are known (24 bits).
  final int? id32;
  final int? facility;
  final int? cardNumber;

  /// `0004335038` (10 digits, as printed on most cards).
  String? get decimal10 => id32?.toString().padLeft(10, '0');

  /// `066,09662` (Wiegand 26: 3 + 5 digits).
  String? get wiegand26 => facility == null || cardNumber == null
      ? null
      : '${facility.toString().padLeft(3, '0')},${cardNumber.toString().padLeft(5, '0')}';

  /// Hex as copiers / T5577 writers expect: 10 digits when the version byte is
  /// known, else the 8-digit 32-bit ID.
  String? get hex {
    if (id32 == null) {
      if (facility == null || cardNumber == null) return null;
      return ((facility! << 16) | cardNumber!).toRadixString(16).padLeft(6, '0').toUpperCase();
    }
    final low = id32!.toRadixString(16).padLeft(8, '0').toUpperCase();
    return version == null ? low : version!.toRadixString(16).padLeft(2, '0').toUpperCase() + low;
  }

  Map<String, String> toFields() => {
        'frequency': '125 kHz',
        'chipType': 'EM4100 / compatible',
        'uid': ?hex,
        'idDecimal': ?decimal10,
        'wiegand26': ?wiegand26,
      };
}

LfCardId _from32(int id32, {int? version}) =>
    LfCardId(version: version, id32: id32, facility: (id32 >> 16) & 0xFF, cardNumber: id32 & 0xFFFF);

final _w26 = RegExp(r'(?<!\d)(\d{1,3})\s*[,.]\s*(\d{5})(?!\d)');
final _dec10 = RegExp(r'(?<![\dA-Fa-f])(\d{10})(?![\dA-Fa-f])');

/// Parses what a USB reader typed or what OCR found on the card. Accepts:
/// 10 decimal digits, 8 or 10 hex digits, `fff,ccccc`, or a printed line with
/// both (`0004335038 066,09662`; the 10-digit number is then used).
/// Returns null when nothing usable is found.
LfCardId? parseLfCardId(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final dec = _dec10.firstMatch(text);
  final w26 = _w26.firstMatch(text);
  final dec32 = dec == null ? null : int.parse(dec.group(1)!);
  final decOk = dec32 != null && dec32 <= 0xFFFFFFFF;

  // The 10-digit number wins over a printed `fff,ccccc` pair: it has all 32
  // bits, and the pair is derived from it anyway.
  if (decOk) return _from32(dec32);

  final compact = text.replaceAll(RegExp(r'[\s:\-]'), '');
  // 10 hex digits = full 40-bit EM4100 ID (a reader in hex mode). All-digit
  // strings land here only when too big to be the 32-bit decimal form.
  if (RegExp(r'^[0-9A-Fa-f]{10}$').hasMatch(compact)) {
    final v = int.parse(compact.substring(0, 2), radix: 16);
    return _from32(int.parse(compact.substring(2), radix: 16), version: v);
  }
  if (RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(compact)) {
    return _from32(int.parse(compact, radix: 16));
  }

  if (w26 != null) {
    final f = int.parse(w26.group(1)!), c = int.parse(w26.group(2)!);
    if (f <= 0xFF && c <= 0xFFFF) return LfCardId(facility: f, cardNumber: c);
  }
  return null;
}

/// OCR of a card's printed number. Stricter than [parseLfCardId]: a 10-digit
/// number only counts when it starts with `00` (IDs below 2^32 are printed
/// zero-padded) or matches a printed `fff,ccccc` pair, so phone numbers such
/// as `0912345678` on hotel cards are not taken for card IDs.
LfCardId? findPrintedLfId(String text) {
  final pairs = [
    for (final m in _w26.allMatches(text))
      if (int.parse(m.group(1)!) <= 0xFF && int.parse(m.group(2)!) <= 0xFFFF)
        (int.parse(m.group(1)!), int.parse(m.group(2)!)),
  ];
  for (final m in _dec10.allMatches(text)) {
    final v = int.parse(m.group(1)!);
    if (v > 0xFFFFFFFF) continue;
    final id = _from32(v);
    final agrees = pairs.any((p) => p.$1 == id.facility && p.$2 == id.cardNumber);
    if (agrees || m.group(1)!.startsWith('00')) return id;
  }
  if (pairs.length == 1) return LfCardId(facility: pairs.first.$1, cardNumber: pairs.first.$2);
  return null;
}
