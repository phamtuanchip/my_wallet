import '../access/lf_card_id.dart';
import '../nfc/emrtd/mrz.dart';
import 'id_document.dart';

/// Fields from an MRZ (back of the CCCD, passport data page).
Map<String, String> fieldsFromMrz(MrzData mrz, DocumentKind kind) {
  final vn = mrz.issuingState == 'VNM' || mrz.nationality == 'VNM';
  final out = <String, String>{};
  if (kind == DocumentKind.passport) {
    out['passportNumber'] = mrz.documentNumber;
  } else {
    out['number'] = mrz.vnIdNumber ?? mrz.documentNumber;
  }
  if (mrz.fullName.isNotEmpty) out['holder'] = mrz.fullName;
  final dob = fromMrzDate(mrz.birthDate, isExpiry: false);
  if (dob != null) out['dob'] = dob;
  final exp = fromMrzDate(mrz.expiryDate, isExpiry: true);
  if (exp != null) out['expiry'] = exp;
  if (mrz.sex.isNotEmpty) {
    out['sex'] = vn ? (mrz.sex == 'M' ? 'Nam' : 'Nữ') : (mrz.sex == 'M' ? 'Male' : 'Female');
  }
  if (mrz.nationality.isNotEmpty) out['nationality'] = mrz.nationality == 'VNM' ? 'Việt Nam' : mrz.nationality;
  return out;
}

final _date = RegExp(r'\b(\d{1,2})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*((?:19|20)\d{2})\b');
final _nameLabel = RegExp(r'(full\s*name|h[oọ]\s*(v[aà]|,)?\s*t[eê]n|surname)', caseSensitive: false);
final _sex = RegExp(r'(gi[oớ]i\s*t[ií]nh|sex)\W*(nam|n[uữ]|male|female|m|f)\b', caseSensitive: false);
final _class = RegExp(r'(?:h[aạ]ng|class)\s*[:/]?\s*([A-F][1-3]?E?)\b', caseSensitive: false);
final _plate = RegExp(r'\b(\d{2}\s?[A-Z]{1,2}\d?)\s?[-–]?\s?(\d{3}[.\s]?\d{2}|\d{4})\b');

/// Best-effort read of a photographed document. Only fields that belong to
/// [kind] are returned; the user reviews everything in the form.
Map<String, String> parseDocumentText(DocumentKind kind, List<String> lines, {DateTime? now}) {
  final allowed = kind.fields.map((f) => f.key).toSet();
  final out = <String, String>{};
  void put(String key, String? value) {
    if (value == null || value.trim().isEmpty || !allowed.contains(key)) return;
    out.putIfAbsent(key, () => value.trim());
  }

  final mrz = kind.hasChip ? findMrz(lines) : null;
  if (mrz != null) fieldsFromMrz(mrz, kind).forEach(put);

  final text = lines.join('\n');

  // Access cards: the printed 125 kHz ID; skip the generic number/date rules.
  if (kind == DocumentKind.accessCard) {
    findPrintedLfId(text)?.toFields().forEach(put);
    return out;
  }

  // Numbers: 12-digit personal number (CCCD, new licences), passport number.
  final id12 = RegExp(r'(?<!\d)(\d{12})(?!\d)').firstMatch(text.replaceAll(' ', ''));
  if (kind == DocumentKind.passport) {
    put('passportNumber', RegExp(r'\b([A-Z]\d{7,8})\b').firstMatch(text)?.group(1));
  } else if (kind != DocumentKind.vehicleRegistration) {
    put('number', id12?.group(1));
  }

  // Dates: earliest = birth date, latest (in the future) = expiry.
  final today = now ?? DateTime.now();
  final dates = <DateTime>[];
  for (final m in _date.allMatches(text)) {
    final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
    if (d < 1 || d > 31 || mo < 1 || mo > 12) continue;
    dates.add(DateTime(y, mo, d));
  }
  dates.sort();
  String fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  if (dates.isNotEmpty) {
    final hasDob = allowed.contains('dob');
    final first = dates.first;
    if (hasDob && today.difference(first).inDays > 365 * 14) put('dob', fmt(first));
    final last = dates.last;
    if (last.isAfter(today) && dates.length > (hasDob ? 1 : 0)) put('expiry', fmt(last));
    final middle = dates.where((d) => !d.isAfter(today) && (!hasDob || d != first));
    if (middle.isNotEmpty) put('issueDate', fmt(middle.last));
  }

  // Name: the text after "Họ và tên / Full name", or on the next line.
  for (var i = 0; i < lines.length; i++) {
    final m = _nameLabel.firstMatch(lines[i]);
    if (m == null) continue;
    var rest = lines[i].substring(m.end).replaceFirst(RegExp(r'^[^A-Za-zÀ-ỹ]+'), '');
    rest = rest.replaceFirst(RegExp(r'^(full\s*name|name)\W*', caseSensitive: false), '');
    final candidate = rest.length >= 4 ? rest : (i + 1 < lines.length ? lines[i + 1] : '');
    if (RegExp(r'^[A-ZÀ-Ỹ][A-ZÀ-Ỹ\s]{3,}$').hasMatch(candidate.trim())) {
      put('holder', candidate);
      put('owner', candidate);
      break;
    }
  }

  final sex = _sex.firstMatch(text)?.group(2)?.toLowerCase();
  if (sex != null) {
    put('sex', switch (sex) { 'nam' || 'male' || 'm' => 'Nam', _ => 'Nữ' });
  }
  put('licenseClass', _class.firstMatch(text)?.group(1)?.toUpperCase());
  final plate = _plate.firstMatch(text);
  if (plate != null) put('plate', '${plate.group(1)!.replaceAll(' ', '')}-${plate.group(2)!.replaceAll(' ', '.')}');
  return out;
}
