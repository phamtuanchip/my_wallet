import 'package:flutter_test/flutter_test.dart';
import 'package:my_wallet/card/card_info.dart';

void main() {
  group('detectScheme', () {
    test('recognises the major networks', () {
      expect(detectScheme('4111 1111 1111 1111'), CardScheme.visa);
      expect(detectScheme('5555555555554444'), CardScheme.mastercard);
      expect(detectScheme('2223003122003222'), CardScheme.mastercard);
      expect(detectScheme('3530111333300000'), CardScheme.jcb);
      expect(detectScheme('378282246310005'), CardScheme.amex);
      expect(detectScheme('6200000000000005'), CardScheme.unionpay);
      expect(detectScheme('6011111111111117'), CardScheme.discover);
      expect(detectScheme('9704366614952217'), CardScheme.napas);
      expect(detectScheme(''), CardScheme.unknown);
      expect(detectScheme('1234'), CardScheme.unknown);
    });
  });

  group('luhnValid', () {
    test('accepts valid test numbers and rejects typos', () {
      expect(luhnValid('4111111111111111'), isTrue);
      expect(luhnValid('4111 1111 1111 1112'), isFalse);
      expect(luhnValid('378282246310005'), isTrue);
      expect(luhnValid('123'), isFalse);
    });
  });

  test('formatPan groups like the card', () {
    expect(formatPan('4111111111111111'), '4111 1111 1111 1111');
    expect(formatPan('378282246310005'), '3782 822463 10005');
    expect(formatPan('41111'), '4111 1');
    expect(last4Of('4111 1111 1111 1234'), '1234');
  });

  group('expiry', () {
    test('parses common forms', () {
      expect(parseExpiry('09/27'), (month: 9, year: 27));
      expect(parseExpiry('9/2027'), (month: 9, year: 27));
      expect(parseExpiry('0927'), (month: 9, year: 27));
      expect(parseExpiry('13/27'), isNull);
      expect(parseExpiry('ab'), isNull);
    });

    test('a card is valid through the end of its expiry month', () {
      expect(isExpired('11/26', now: DateTime(2026, 11, 30)), isFalse);
      expect(isExpired('11/26', now: DateTime(2026, 12, 1)), isTrue);
      expect(isExpired('', now: DateTime(2026)), isFalse);
    });
  });

  group('issuer lookup', () {
    test('NAPAS BIN maps to the bank', () {
      expect(issuerFromNumber('9704 3666 1495 2217'), 'Vietcombank');
      expect(issuerFromNumber('9704 0700 0000 0000'), 'Techcombank');
      expect(issuerFromNumber('4111111111111111'), isNull);
    });

    test('bank name printed on the card', () {
      expect(issuerFromText('TECHCOMBANK\nVISA DEBIT'), 'Techcombank');
      expect(issuerFromText('Vietcombank'), 'Vietcombank');
      expect(issuerFromText('ACB\nPLATINUM'), 'ACB');
      // Short acronyms must be whole words: "VIBRANT" is not VIB.
      expect(issuerFromText('VIBRANT CARD'), isNull);
    });
  });
}
