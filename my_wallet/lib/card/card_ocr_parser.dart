import 'card_info.dart';

/// What could be read from a photo of the front of a card. Every field is
/// optional: OCR on embossed or glossy cards often misses some of them.
class CardScanResult {
  const CardScanResult({
    this.number,
    this.numberVerified = false,
    this.holder,
    this.expiry,
    this.scheme,
    this.product,
    this.issuer,
  });

  final String? number; // digits only
  final bool numberVerified; // passed the Luhn check
  final String? holder;
  final String? expiry; // MM/YY
  final CardScheme? scheme;
  final CardProduct? product;
  final String? issuer;

  bool get isEmpty =>
      number == null && holder == null && expiry == null && issuer == null;

  List<String> get foundFields => [
        if (number != null) 'number',
        if (holder != null) 'cardholder',
        if (expiry != null) 'expiry',
        if (issuer != null) 'bank',
        if (product != null) 'type',
      ];
}

// Characters OCR commonly confuses with digits on embossed numbers.
const _toDigit = {
  'O': '0', 'o': '0', 'D': '0', 'Q': '0',
  'I': '1', 'l': '1', '|': '1', 'i': '1', '!': '1',
  'Z': '2', 'z': '2',
  'S': '5', 's': '5',
  'G': '6', 'b': '6',
  'T': '7',
  'B': '8',
  'g': '9', 'q': '9',
};

/// Converts a token to digits if it looks numeric (at least half real digits).
String? _digitToken(String token) {
  if (token.isEmpty) return null;
  final realDigits = token.runes.where((r) => r >= 48 && r <= 57).length;
  if (realDigits * 2 < token.length) return null;
  final b = StringBuffer();
  for (final ch in token.split('')) {
    if (RegExp(r'\d').hasMatch(ch)) {
      b.write(ch);
    } else if (_toDigit.containsKey(ch)) {
      b.write(_toDigit[ch]);
    } else if (ch == '-' || ch == '.') {
      continue;
    } else {
      return null;
    }
  }
  return b.toString();
}

const _holderStopWords = {
  'VISA', 'MASTERCARD', 'MASTER', 'DEBIT', 'CREDIT', 'PREPAID', 'PLATINUM',
  'GOLD', 'CLASSIC', 'SIGNATURE', 'INFINITE', 'WORLD', 'ELITE', 'BUSINESS',
  'CORPORATE', 'VALID', 'THRU', 'FROM', 'GOOD', 'MONTH', 'YEAR', 'EXPIRES',
  'EXPIRY', 'END', 'BANK', 'NGAN', 'HANG', 'CARD', 'THE', 'ELECTRONIC',
  'USE', 'ONLY', 'NAPAS', 'JCB', 'AMERICAN', 'EXPRESS', 'UNIONPAY', 'MEMBER',
  'SINCE', 'CONTACTLESS', 'PAYWAVE', 'PAYPASS', 'INTERNATIONAL', 'DOMESTIC',
  'CHIP', 'CASHBACK', 'REWARDS', 'PREMIER', 'PRIORITY', 'STANDARD', 'TITANIUM',
};

/// Combines OCR passes over the same card (original, enhanced, rotated…):
/// a Luhn-verified number wins, the most common holder wins, the latest expiry
/// wins, other fields take the first value found.
CardScanResult mergeScanResults(List<CardScanResult> passes) {
  if (passes.isEmpty) return const CardScanResult();
  final verified = passes.where((p) => p.number != null && p.numberVerified).toList();
  final unverified = passes.where((p) => p.number != null && !p.numberVerified).toList()
    ..sort((a, b) => b.number!.length.compareTo(a.number!.length));
  final numberPass = verified.isNotEmpty ? verified.first : (unverified.isNotEmpty ? unverified.first : null);

  final holderVotes = <String, int>{};
  for (final p in passes) {
    if (p.holder != null) holderVotes[p.holder!] = (holderVotes[p.holder!] ?? 0) + 1;
  }
  final holder = holderVotes.isEmpty
      ? null
      : (holderVotes.entries.toList()
            ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : b.key.length.compareTo(a.key.length)))
          .first
          .key;

  ({int month, int year})? latest;
  for (final p in passes) {
    final e = p.expiry == null ? null : parseExpiry(p.expiry!);
    if (e != null && (latest == null || e.year > latest.year || (e.year == latest.year && e.month > latest.month))) {
      latest = e;
    }
  }

  T? first<T>(T? Function(CardScanResult) f) {
    for (final p in passes) {
      final v = f(p);
      if (v != null) return v;
    }
    return null;
  }

  final number = numberPass?.number;
  final scheme = number != null && detectScheme(number) != CardScheme.unknown
      ? detectScheme(number)
      : first((p) => p.scheme);
  return CardScanResult(
    number: number,
    numberVerified: numberPass?.numberVerified ?? false,
    holder: holder,
    expiry: latest == null ? null : formatExpiry(latest.month, latest.year),
    scheme: scheme,
    product: first((p) => p.product),
    issuer: (number != null ? issuerFromNumber(number) : null) ?? first((p) => p.issuer),
  );
}

typedef TextPiece = ({String text, double top, double bottom, double left});

/// Merges OCR pieces that sit on the same visual row (their vertical centres are
/// within half a line height) and returns rows top-to-bottom, each read
/// left-to-right. Card numbers are often split into one piece per digit group.
List<String> groupTextRows(List<TextPiece> pieces) {
  final sorted = [...pieces]..sort((a, b) => (a.top + a.bottom).compareTo(b.top + b.bottom));
  final rows = <List<TextPiece>>[];
  for (final p in sorted) {
    final cy = (p.top + p.bottom) / 2;
    final h = p.bottom - p.top;
    final row = rows.isEmpty ? null : rows.last;
    if (row != null) {
      final rcy = row.map((e) => (e.top + e.bottom) / 2).reduce((a, b) => a + b) / row.length;
      final rh = row.map((e) => e.bottom - e.top).reduce((a, b) => a > b ? a : b);
      if ((cy - rcy).abs() <= (h > rh ? h : rh) * 0.5) {
        row.add(p);
        continue;
      }
    }
    rows.add([p]);
  }
  return [
    for (final row in rows)
      (row..sort((a, b) => a.left.compareTo(b.left))).map((e) => e.text.trim()).join(' '),
  ];
}

/// Parses recognised text lines (top to bottom) from the front of a card.
CardScanResult parseCardText(List<String> lines) {
  final text = lines.join('\n');

  // ── Card number: consecutive numeric tokens on one line, 13–19 digits.
  String? number;
  var verified = false;
  var numberLine = -1;
  String? fallback;
  var fallbackLine = -1;
  for (var li = 0; li < lines.length && !verified; li++) {
    final tokens = lines[li].trim().split(RegExp(r'\s+'));
    // Try every run of consecutive numeric tokens.
    for (var start = 0; start < tokens.length && !verified; start++) {
      final buf = StringBuffer();
      for (var end = start; end < tokens.length; end++) {
        final d = _digitToken(tokens[end]);
        if (d == null) break;
        buf.write(d);
        final candidate = buf.toString();
        if (candidate.length > 19) break;
        if (candidate.length >= 13) {
          if (luhnValid(candidate) && detectScheme(candidate) != CardScheme.unknown) {
            number = candidate;
            verified = true;
            numberLine = li;
            break;
          }
          if (candidate.length >= 15 && (fallback == null || candidate.length > fallback.length)) {
            fallback = candidate;
            fallbackLine = li;
          }
        }
      }
    }
  }
  // Tilted photos: the digit groups can come back as separate lines. Join runs
  // of consecutive all-numeric lines and test those too.
  if (!verified) {
    final numericLines = <int, String>{};
    for (var li = 0; li < lines.length; li++) {
      final tokens = lines[li].trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
      final digits = tokens.map(_digitToken).toList();
      if (digits.isNotEmpty && digits.every((d) => d != null)) {
        numericLines[li] = digits.join();
      }
    }
    for (final start in numericLines.keys) {
      final buf = StringBuffer();
      for (var li = start; numericLines.containsKey(li); li++) {
        buf.write(numericLines[li]);
        final candidate = buf.toString();
        if (candidate.length > 19) break;
        if (candidate.length >= 13 && luhnValid(candidate) && detectScheme(candidate) != CardScheme.unknown) {
          number = candidate;
          verified = true;
          numberLine = li;
          break;
        }
      }
      if (verified) break;
    }
  }
  if (number == null && fallback != null) {
    number = fallback;
    numberLine = fallbackLine;
  }

  // ── Expiry: every MM/YY on the card; "valid from" is earlier, so keep the latest.
  ({int month, int year})? best;
  final expRe = RegExp(r'(?<!\d)(0[1-9]|1[0-2])\s?[/\\\-]\s?(20\d{2}|\d{2})(?!\d)');
  for (final m in expRe.allMatches(text)) {
    final e = parseExpiry('${m.group(1)}/${m.group(2)}');
    if (e == null) continue;
    if (best == null || e.year > best.year || (e.year == best.year && e.month > best.month)) {
      best = e;
    }
  }
  final expiry = best == null ? null : formatExpiry(best.month, best.year);

  // ── Cardholder: an all-letters line of 2–5 words, preferring lines after the number.
  String? holder;
  final order = [
    for (var i = numberLine + 1; i < lines.length; i++) i,
    for (var i = 0; i <= numberLine && i < lines.length; i++) i,
  ];
  for (final i in order) {
    final line = lines[i].trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!RegExp(r"^[A-Za-z][A-Za-z .'\-]{3,30}$").hasMatch(line)) continue;
    if (line != line.toUpperCase()) continue; // embossed names are upper case
    final words = line.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length < 2 || words.length > 5) continue;
    if (words.any((w) => _holderStopWords.contains(w.replaceAll(RegExp(r'[^A-Z]'), '')))) continue;
    if (issuerFromText(line) != null) continue;
    holder = words.join(' ');
    break;
  }

  final upper = text.toUpperCase();
  final product = upper.contains('DEBIT')
      ? CardProduct.debit
      : upper.contains('CREDIT')
          ? CardProduct.credit
          : upper.contains('PREPAID')
              ? CardProduct.prepaid
              : null;

  CardScheme? scheme = number != null ? detectScheme(number) : null;
  if (scheme == null || scheme == CardScheme.unknown) {
    if (upper.contains('VISA')) {
      scheme = CardScheme.visa;
    } else if (upper.contains('MASTERCARD')) {
      scheme = CardScheme.mastercard;
    } else if (upper.contains('NAPAS')) {
      scheme = CardScheme.napas;
    } else if (upper.contains('JCB')) {
      scheme = CardScheme.jcb;
    } else {
      scheme = null;
    }
  }

  final issuer = (number != null ? issuerFromNumber(number) : null) ?? issuerFromText(text);

  return CardScanResult(
    number: number,
    numberVerified: verified,
    holder: holder,
    expiry: expiry,
    scheme: scheme,
    product: product,
    issuer: issuer,
  );
}
