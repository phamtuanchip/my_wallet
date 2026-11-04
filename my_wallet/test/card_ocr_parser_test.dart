import 'package:flutter_test/flutter_test.dart';
import 'package:my_wallet/card/card_info.dart';
import 'package:my_wallet/card/card_ocr_parser.dart';

void main() {
  test('reads a typical Visa debit front', () {
    final r = parseCardText([
      'TECHCOMBANK',
      'VISA DEBIT',
      '4111 1111 1111 1111',
      'VALID FROM 05/22  VALID THRU 05/27',
      'NGUYEN VAN AN',
      'VISA',
    ]);
    expect(r.number, '4111111111111111');
    expect(r.numberVerified, isTrue);
    expect(r.expiry, '05/27'); // the later of FROM / THRU
    expect(r.holder, 'NGUYEN VAN AN');
    expect(r.scheme, CardScheme.visa);
    expect(r.product, CardProduct.debit);
    expect(r.issuer, 'Techcombank');
  });

  test('fixes OCR letter/digit confusion in embossed numbers', () {
    final r = parseCardText([
      '5555 5555 S5S5 4444', // S read instead of 5
      '12/28',
      'TRAN THI BINH',
    ]);
    expect(r.number, '5555555555554444');
    expect(r.numberVerified, isTrue);
    expect(r.scheme, CardScheme.mastercard);
    expect(r.holder, 'TRAN THI BINH');
  });

  test('NAPAS domestic card gets the bank from the BIN', () {
    final r = parseCardText(['9704 3666 1495 2217', 'THRU 08/2029', 'LE MINH']);
    expect(r.number, '9704366614952217');
    expect(r.scheme, CardScheme.napas);
    expect(r.issuer, 'Vietcombank');
    expect(r.expiry, '08/29');
  });

  test('keeps an unverified number when the check digit fails', () {
    final r = parseCardText(['4111 1111 1111 1112', 'PHAM TUAN']);
    expect(r.number, '4111111111111112');
    expect(r.numberVerified, isFalse);
  });

  test('ignores marketing lines as cardholder', () {
    final r = parseCardText(['VISA PLATINUM', 'WORLD ELITE', 'CONTACTLESS CARD']);
    expect(r.holder, isNull);
    expect(r.isEmpty, isTrue);
  });

  test('digit groups split over separate lines (tilted photo) are joined', () {
    final r = parseCardText(['TECHCOMBANK', '4111', '1111', '1111', '1111', '05/29', 'NGUYEN VAN AN']);
    expect(r.number, '4111111111111111');
    expect(r.numberVerified, isTrue);
    expect(r.holder, 'NGUYEN VAN AN');
  });

  test('groupTextRows merges pieces on the same row, left to right', () {
    final rows = groupTextRows([
      (text: '1111', top: 584, bottom: 642, left: 845), // tilted: lower on the right
      (text: '4111', top: 560, bottom: 620, left: 230),
      (text: 'NGUYEN VAN AN', top: 805, bottom: 860, left: 220),
      (text: '1111', top: 572, bottom: 632, left: 540),
      (text: '1111', top: 594, bottom: 655, left: 1150),
      (text: 'TECHCOMBANK', top: 190, bottom: 255, left: 245),
    ]);
    expect(rows, ['TECHCOMBANK', '4111 1111 1111 1111', 'NGUYEN VAN AN']);
  });

  test('mergeScanResults keeps the best value of each field across passes', () {
    final merged = mergeScanResults(const [
      CardScanResult(number: '4111111111111112', holder: 'NGUYEN VAN AM', expiry: '05/22'),
      CardScanResult(number: '4111111111111111', numberVerified: true, holder: 'NGUYEN VAN AN', expiry: '05/29'),
      CardScanResult(holder: 'NGUYEN VAN AN', issuer: 'Techcombank', product: CardProduct.debit),
    ]);
    expect(merged.number, '4111111111111111');
    expect(merged.numberVerified, isTrue);
    expect(merged.holder, 'NGUYEN VAN AN'); // 2 votes beat 1
    expect(merged.expiry, '05/29'); // latest
    expect(merged.scheme, CardScheme.visa);
    expect(merged.issuer, 'Techcombank');
    expect(merged.product, CardProduct.debit);
    expect(mergeScanResults(const []).isEmpty, isTrue);
  });

  test('handles nothing useful', () {
    expect(parseCardText([]).isEmpty, isTrue);
  });
}
