/// Pure helpers for payment-card data: scheme detection, Luhn, formatting,
/// expiry parsing and issuer lookup. No Flutter imports, so it is unit-testable.
library;

enum CardScheme {
  visa('Visa'),
  mastercard('Mastercard'),
  jcb('JCB'),
  amex('American Express'),
  unionpay('UnionPay'),
  napas('NAPAS'),
  discover('Discover'),
  diners('Diners Club'),
  unknown('Other');

  const CardScheme(this.label);
  final String label;

  static CardScheme fromName(String? name) => CardScheme.values
      .firstWhere((s) => s.name == name, orElse: () => CardScheme.unknown);
}

enum CardProduct {
  debit('Debit'),
  credit('Credit'),
  prepaid('Prepaid'),
  unknown('Other');

  const CardProduct(this.label);
  final String label;

  static CardProduct fromName(String? name) => CardProduct.values
      .firstWhere((p) => p.name == name, orElse: () => CardProduct.unknown);
}

String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Detects the card scheme from the leading digits (IIN ranges).
CardScheme detectScheme(String number) {
  final d = digitsOnly(number);
  if (d.isEmpty) return CardScheme.unknown;
  int prefix(int n) => d.length >= n ? int.parse(d.substring(0, n)) : -1;

  if (d.startsWith('9704')) return CardScheme.napas;
  if (d.startsWith('34') || d.startsWith('37')) return CardScheme.amex;
  if (d.startsWith('4')) return CardScheme.visa;
  final p2 = prefix(2), p3 = prefix(3), p4 = prefix(4);
  if ((p2 >= 51 && p2 <= 55) || (p4 >= 2221 && p4 <= 2720)) {
    return CardScheme.mastercard;
  }
  if (p4 >= 3528 && p4 <= 3589) return CardScheme.jcb;
  if (d.startsWith('6011') || (p3 >= 644 && p3 <= 649) || d.startsWith('65')) {
    return CardScheme.discover;
  }
  if (d.startsWith('62')) return CardScheme.unionpay;
  if (d.startsWith('36') || (p3 >= 300 && p3 <= 305) || d.startsWith('38') ||
      d.startsWith('39')) {
    return CardScheme.diners;
  }
  return CardScheme.unknown;
}

/// Luhn (mod 10) check used by every major card scheme.
bool luhnValid(String number) {
  final d = digitsOnly(number);
  if (d.length < 12 || d.length > 19) return false;
  var sum = 0;
  var dbl = false;
  for (var i = d.length - 1; i >= 0; i--) {
    var v = d.codeUnitAt(i) - 48;
    if (dbl) {
      v *= 2;
      if (v > 9) v -= 9;
    }
    sum += v;
    dbl = !dbl;
  }
  return sum % 10 == 0;
}

/// Groups digits for display: Amex 4-6-5, everything else in fours.
String formatPan(String number) {
  final d = digitsOnly(number);
  if (detectScheme(d) == CardScheme.amex) {
    final parts = <String>[];
    if (d.isNotEmpty) parts.add(d.substring(0, d.length.clamp(0, 4)));
    if (d.length > 4) parts.add(d.substring(4, d.length.clamp(4, 10)));
    if (d.length > 10) parts.add(d.substring(10, d.length.clamp(10, 15)));
    return parts.join(' ');
  }
  final b = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    if (i > 0 && i % 4 == 0) b.write(' ');
    b.write(d[i]);
  }
  return b.toString();
}

String last4Of(String number) {
  final d = digitsOnly(number);
  return d.length <= 4 ? d : d.substring(d.length - 4);
}

/// Parses `MM/YY`, `MM/YYYY`, `MMYY` into (month, two-digit year), or null.
({int month, int year})? parseExpiry(String input) {
  final m = RegExp(r'^\s*(\d{1,2})\s*[/\-.]?\s*(\d{2}|\d{4})\s*$').firstMatch(input);
  if (m == null) return null;
  final month = int.parse(m.group(1)!);
  var year = int.parse(m.group(2)!);
  if (year >= 2000) year -= 2000;
  if (month < 1 || month > 12 || year > 99) return null;
  return (month: month, year: year);
}

String formatExpiry(int month, int year) =>
    '${month.toString().padLeft(2, '0')}/${year.toString().padLeft(2, '0')}';

/// Cards are valid through the last day of the expiry month.
bool isExpired(String expiry, {DateTime? now}) {
  final e = parseExpiry(expiry);
  if (e == null) return false;
  final firstOfNextMonth = DateTime(2000 + e.year, e.month + 1);
  return !(now ?? DateTime.now()).isBefore(firstOfNextMonth);
}

/// Vietnamese issuers. `bin` = NAPAS domestic BIN (9704 + bank code),
/// `keywords` = how the name is printed on cards (upper case, no spaces).
class Issuer {
  const Issuer(this.name, {this.bin, this.keywords = const []});
  final String name;
  final String? bin;
  final List<String> keywords;
}

const List<Issuer> kIssuers = [
  Issuer('Vietcombank', bin: '970436', keywords: ['VIETCOMBANK', 'VCB']),
  Issuer('VietinBank', bin: '970415', keywords: ['VIETINBANK']),
  Issuer('BIDV', bin: '970418', keywords: ['BIDV']),
  Issuer('Agribank', bin: '970405', keywords: ['AGRIBANK']),
  Issuer('Techcombank', bin: '970407', keywords: ['TECHCOMBANK']),
  Issuer('MB Bank', bin: '970422', keywords: ['MBBANK', 'MILITARYBANK']),
  Issuer('ACB', bin: '970416', keywords: ['ACB']),
  Issuer('VPBank', bin: '970432', keywords: ['VPBANK']),
  Issuer('TPBank', bin: '970423', keywords: ['TPBANK']),
  Issuer('Sacombank', bin: '970403', keywords: ['SACOMBANK']),
  Issuer('HDBank', bin: '970437', keywords: ['HDBANK']),
  Issuer('VIB', bin: '970441', keywords: ['VIB']),
  Issuer('SHB', bin: '970443', keywords: ['SHB']),
  Issuer('Eximbank', bin: '970431', keywords: ['EXIMBANK']),
  Issuer('MSB', bin: '970426', keywords: ['MSB', 'MARITIMEBANK']),
  Issuer('OCB', bin: '970448', keywords: ['OCB']),
  Issuer('SeABank', bin: '970440', keywords: ['SEABANK']),
  Issuer('BVBank (Viet Capital)', bin: '970454', keywords: ['BVBANK', 'VIETCAPITAL']),
  Issuer('SCB', bin: '970429', keywords: ['SCB']),
  Issuer('Bac A Bank', bin: '970409', keywords: ['BACABANK']),
  Issuer('PVcomBank', bin: '970412', keywords: ['PVCOMBANK']),
  Issuer('NCB', bin: '970419', keywords: ['NCB']),
  Issuer('Shinhan Bank', bin: '970424', keywords: ['SHINHAN']),
  Issuer('ABBANK', bin: '970425', keywords: ['ABBANK']),
  Issuer('VietABank', bin: '970427', keywords: ['VIETABANK']),
  Issuer('Nam A Bank', bin: '970428', keywords: ['NAMABANK']),
  Issuer('LPBank', bin: '970449', keywords: ['LPBANK', 'LIENVIET']),
  Issuer('KienlongBank', bin: '970452', keywords: ['KIENLONG']),
  Issuer('Saigonbank', bin: '970400', keywords: ['SAIGONBANK']),
  Issuer('DongA Bank', bin: '970406', keywords: ['DONGABANK']),
  Issuer('GPBank', bin: '970408', keywords: ['GPBANK']),
  Issuer('HSBC', keywords: ['HSBC']),
  Issuer('Citibank', keywords: ['CITIBANK', 'CITI']),
  Issuer('Standard Chartered', keywords: ['STANDARDCHARTERED']),
  Issuer('UOB', keywords: ['UOB']),
  Issuer('Woori Bank', keywords: ['WOORI']),
  Issuer('Home Credit', keywords: ['HOMECREDIT']),
  Issuer('FE Credit', keywords: ['FECREDIT']),
];

/// Issuer from a NAPAS domestic BIN (first 6 digits). International
/// Visa/Mastercard BINs are not mapped: the user picks the bank.
String? issuerFromNumber(String number) {
  final d = digitsOnly(number);
  if (d.length < 6) return null;
  final bin = d.substring(0, 6);
  for (final i in kIssuers) {
    if (i.bin == bin) return i.name;
  }
  return null;
}

/// Finds a known issuer name printed anywhere in free text (e.g. OCR output).
String? issuerFromText(String text) {
  final squashed = text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final words = text.toUpperCase().split(RegExp(r'[^A-Z0-9]+')).toSet();
  for (final i in kIssuers) {
    for (final k in i.keywords) {
      // Short acronyms (ACB, VIB...) must be whole words; long names may be squashed.
      if (k.length <= 4 ? words.contains(k) : squashed.contains(k)) return i.name;
    }
  }
  return null;
}
