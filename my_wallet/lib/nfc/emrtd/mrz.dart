/// Machine Readable Zone parsing (ICAO Doc 9303 Parts 4–6).
///
/// TD1 = 3 lines × 30 (ID cards, incl. the Vietnamese chip CCCD on the back),
/// TD3 = 2 lines × 44 (passport data page). TD2 (2 × 36) is parsed too.
library;

/// ICAO 9303 check digit: weights 7, 3, 1; `<` = 0, `A` = 10 … `Z` = 35.
int mrzCheckDigit(String s) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    int v;
    if (c >= 0x30 && c <= 0x39) {
      v = c - 0x30;
    } else if (c >= 0x41 && c <= 0x5A) {
      v = c - 0x41 + 10;
    } else {
      v = 0; // '<' and anything unexpected
    }
    sum += v * weights[i % 3];
  }
  return sum % 10;
}

class MrzData {
  const MrzData({
    required this.format,
    required this.documentCode,
    required this.issuingState,
    required this.documentNumber,
    required this.birthDate,
    required this.sex,
    required this.expiryDate,
    required this.nationality,
    required this.surname,
    required this.givenNames,
    this.optionalData = '',
    this.checksOk = false,
  });

  final String format; // TD1 | TD2 | TD3
  final String documentCode; // e.g. "ID", "P"
  final String issuingState; // e.g. "VNM"
  final String documentNumber; // '<' removed
  final String birthDate; // YYMMDD
  final String sex; // M | F | '' (unspecified)
  final String expiryDate; // YYMMDD
  final String nationality;
  final String surname;
  final String givenNames;
  final String optionalData; // '<' removed
  final bool checksOk; // every check digit matched

  String get fullName => [surname, givenNames].where((s) => s.isNotEmpty).join(' ');

  /// Vietnamese CCCD: the 12-digit personal number is in the TD1 optional data;
  /// the 9-character document number is its last 9 digits.
  String? get vnIdNumber {
    final m = RegExp(r'^(\d{12})').firstMatch(optionalData);
    if (m != null) return m.group(1);
    return null;
  }
}

/// Parses an MRZ given as its lines (any whitespace between them is ignored).
/// Returns null unless the text has a TD1/TD2/TD3 shape.
MrzData? parseMrz(List<String> lines) {
  final clean = lines.map(_normaliseLine).where((l) => l.isNotEmpty).toList();
  if (clean.length == 3 && clean.every((l) => l.length == 30)) return _td1(clean);
  if (clean.length == 2 && clean.every((l) => l.length == 44)) return _td3(clean);
  if (clean.length == 2 && clean.every((l) => l.length == 36)) return _td2(clean);
  return null;
}

/// Finds an MRZ in OCR output: looks for consecutive lines with the right
/// lengths (after fixing common OCR mistakes) and prefers one whose check
/// digits all match.
MrzData? findMrz(List<String> ocrLines) {
  final lines = ocrLines.map(_normaliseLine).where((l) => l.length >= 28).toList();
  MrzData? fallback;
  for (final (count, width) in const [(3, 30), (2, 44), (2, 36)]) {
    for (var i = 0; i + count <= lines.length; i++) {
      final group = [
        for (var k = 0; k < count; k++) _fitWidth(lines[i + k], width),
      ];
      if (group.any((l) => l == null)) continue;
      final mrz = parseMrz(group.cast<String>());
      if (mrz == null) continue;
      if (mrz.checksOk) return mrz;
      fallback ??= mrz;
    }
  }
  return fallback;
}

String _normaliseLine(String s) => s
    .toUpperCase()
    .replaceAll(RegExp(r'\s'), '')
    .replaceAll('«', '<<')
    .replaceAll('‹', '<')
    .replaceAll(RegExp(r'[^A-Z0-9<]'), '');

/// OCR often drops or adds a filler `<` at the end.
String? _fitWidth(String line, int width) {
  if (line.length == width) return line;
  if (line.length < width && line.length >= width - 3) return line.padRight(width, '<');
  if (line.length > width && line.length <= width + 3 && line.substring(width).replaceAll('<', '').isEmpty) {
    return line.substring(0, width);
  }
  return null;
}

/// Digits misread as letters in numeric fields.
String _digits(String s) {
  const map = {'O': '0', 'Q': '0', 'D': '0', 'I': '1', 'L': '1', 'Z': '2', 'S': '5', 'B': '8', 'G': '6', 'T': '7'};
  return s.split('').map((c) => map[c] ?? c).join();
}

String _strip(String s) => s.replaceAll('<', '');

bool _check(String field, String digit) => digit == '<' ? _strip(field).isEmpty : mrzCheckDigit(field).toString() == digit;

(String, String) _names(String field) {
  final parts = field.split('<<');
  final surname = parts.first.replaceAll('<', ' ').trim();
  final given = parts.skip(1).join(' ').replaceAll('<', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return (surname, given);
}

String _sex(String c) => c == 'M' || c == 'F' ? c : '';

MrzData _td1(List<String> l) {
  final l1 = l[0], l2 = _td1Line2(l[1]), l3 = l[2];
  final docNo = l1.substring(5, 14);
  final docCd = _digits(l1.substring(14, 15));
  final opt1 = l1.substring(15, 30);
  final dob = _digits(l2.substring(0, 6));
  final dobCd = _digits(l2.substring(6, 7));
  final exp = _digits(l2.substring(8, 14));
  final expCd = _digits(l2.substring(14, 15));
  final opt2 = l2.substring(18, 29);
  // Only the fields that make the BAC key have to be right; the composite
  // digit also covers optional data that OCR often garbles.
  final checks = _check(docNo, docCd) && _check(dob, dobCd) && _check(exp, expCd);
  final (surname, given) = _names(l3);
  return MrzData(
    format: 'TD1',
    documentCode: _strip(l1.substring(0, 2)),
    issuingState: _strip(l1.substring(2, 5)),
    documentNumber: _strip(docNo),
    birthDate: dob,
    sex: _sex(l2.substring(7, 8)),
    expiryDate: exp,
    nationality: _strip(l2.substring(15, 18)),
    surname: surname,
    givenNames: given,
    optionalData: _strip(_digitsIfMostlyDigits(opt1) + opt2),
    checksOk: checks,
  );
}

/// TD1 line 2 starts with two dates; fix letters inside them before slicing.
String _td1Line2(String l2) => _digits(l2.substring(0, 7)) + l2.substring(7, 8) + _digits(l2.substring(8, 15)) + l2.substring(15);

String _digitsIfMostlyDigits(String s) {
  final core = _strip(s);
  final digitCount = core.split('').where((c) => RegExp(r'\d').hasMatch(c)).length;
  return core.isNotEmpty && digitCount >= core.length - 2 ? _digits(s) : s;
}

MrzData _td3(List<String> l) {
  final l1 = l[0], l2 = l[1];
  final docNo = l2.substring(0, 9);
  final docCd = _digits(l2.substring(9, 10));
  final dob = _digits(l2.substring(13, 19));
  final dobCd = _digits(l2.substring(19, 20));
  final exp = _digits(l2.substring(21, 27));
  final expCd = _digits(l2.substring(27, 28));
  final opt = l2.substring(28, 42);
  final optCd = l2.substring(42, 43);
  final composite = _digits(l2.substring(43, 44));
  final compositeData = l2.substring(0, 10) + l2.substring(13, 20) + l2.substring(21, 43);
  final checks = _check(docNo, docCd) &&
      _check(dob, dobCd) &&
      _check(exp, expCd) &&
      (optCd == '<' || _check(opt, _digits(optCd))) &&
      _check(compositeData, composite);
  final (surname, given) = _names(l1.substring(5));
  return MrzData(
    format: 'TD3',
    documentCode: _strip(l1.substring(0, 2)),
    issuingState: _strip(l1.substring(2, 5)),
    documentNumber: _strip(docNo),
    birthDate: dob,
    sex: _sex(l2.substring(20, 21)),
    expiryDate: exp,
    nationality: _strip(l2.substring(10, 13)),
    surname: surname,
    givenNames: given,
    optionalData: _strip(opt),
    checksOk: checks,
  );
}

MrzData _td2(List<String> l) {
  final l1 = l[0], l2 = l[1];
  final docNo = l2.substring(0, 9);
  final docCd = _digits(l2.substring(9, 10));
  final dob = _digits(l2.substring(13, 19));
  final dobCd = _digits(l2.substring(19, 20));
  final exp = _digits(l2.substring(21, 27));
  final expCd = _digits(l2.substring(27, 28));
  final composite = _digits(l2.substring(35, 36));
  final compositeData = l2.substring(0, 10) + l2.substring(13, 20) + l2.substring(21, 35);
  final checks = _check(docNo, docCd) && _check(dob, dobCd) && _check(exp, expCd) && _check(compositeData, composite);
  final (surname, given) = _names(l1.substring(5));
  return MrzData(
    format: 'TD2',
    documentCode: _strip(l1.substring(0, 2)),
    issuingState: _strip(l1.substring(2, 5)),
    documentNumber: _strip(docNo),
    birthDate: dob,
    sex: _sex(l2.substring(20, 21)),
    expiryDate: exp,
    nationality: _strip(l2.substring(10, 13)),
    surname: surname,
    givenNames: given,
    optionalData: _strip(l2.substring(28, 35)),
    checksOk: checks,
  );
}

// ── Dates ───────────────────────────────────────────────────────────────

/// `dd/MM/yyyy` (also `-` or `.`) → `YYMMDD`, or null.
String? toMrzDate(String ddMmYyyy) {
  final m = RegExp(r'^\s*(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})\s*$').firstMatch(ddMmYyyy);
  if (m == null) return null;
  final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
  if (d < 1 || d > 31 || mo < 1 || mo > 12) return null;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(y % 100)}${two(mo)}${two(d)}';
}

/// `YYMMDD` → `dd/MM/yyyy`. Birth dates are placed in the past, expiry dates
/// within 50 years of [now].
String? fromMrzDate(String yymmdd, {required bool isExpiry, DateTime? now}) {
  if (!RegExp(r'^\d{6}$').hasMatch(yymmdd)) return null;
  final yy = int.parse(yymmdd.substring(0, 2));
  final mm = yymmdd.substring(2, 4);
  final dd = yymmdd.substring(4, 6);
  final today = now ?? DateTime.now();
  final century = today.year ~/ 100 * 100;
  var year = century + yy;
  if (isExpiry) {
    if (year < today.year - 50) year += 100;
  } else if (year > today.year) {
    year -= 100;
  }
  return '$dd/$mm/$year';
}
