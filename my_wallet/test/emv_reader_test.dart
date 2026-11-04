import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_wallet/card/card_info.dart';
import 'package:my_wallet/nfc/emv/emv_reader.dart';
import 'package:my_wallet/nfc/emv/tlv.dart';

/// Builds a TLV element (short lengths only, enough for tests).
List<int> tlv(String tag, List<int> value) => [...fromHex(tag), value.length, ...value];

Uint8List ok(List<int> data) => Uint8List.fromList([...data, 0x90, 0x00]);
Uint8List sw(int sw) => Uint8List.fromList([sw >> 8, sw & 0xFF]);

/// A scripted contactless card. Unknown commands answer 6D00 / 6A82.
class FakeCard {
  FakeCard(this.responder);
  final Uint8List? Function(String apduHex) responder;
  final sent = <String>[];

  Future<Uint8List> transceive(Uint8List apdu) async {
    final hex = toHex(apdu);
    sent.add(hex);
    return responder(hex) ?? (hex.startsWith('00A4') ? sw(0x6A82) : sw(0x6D00));
  }
}

String selectHex(List<int> name) => toHex([0x00, 0xA4, 0x04, 0x00, name.length, ...name, 0x00]);

void main() {
  final ppseName = '2PAY.SYS.DDF01'.codeUnits;
  final visaAid = fromHex('A0000000031010');
  EmvReader reader(FakeCard c) =>
      EmvReader(c.transceive, clock: () => DateTime(2026, 11, 4, 10, 30), random: Random(1));

  test('Visa via PPSE, PDOL, GPO format 2 and READ RECORD', () async {
    final card = FakeCard((apdu) {
      if (apdu == selectHex(ppseName)) {
        return ok(tlv('6F', [
          ...tlv('84', ppseName),
          ...tlv('A5', tlv('BF0C', tlv('61', [
            ...tlv('4F', visaAid),
            ...tlv('50', 'VISA DEBIT'.codeUnits),
            ...tlv('87', [0x01]),
          ]))),
        ]));
      }
      if (apdu == selectHex(visaAid)) {
        return ok(tlv('6F', [
          ...tlv('84', visaAid),
          ...tlv('A5', [
            ...tlv('50', 'VISA DEBIT'.codeUnits),
            ...tlv('9F38', fromHex('9F66049F02069F37049F1A02')),
          ]),
        ]));
      }
      if (apdu.startsWith('80A80000')) {
        // PDOL data must be 4 + 6 + 4 + 2 = 16 bytes inside tag 83.
        expect(apdu.substring(10, 14), '8310');
        expect(apdu.substring(14, 22), '36004000'); // TTQ
        expect(apdu.substring(42, 46), '0704'); // country VN (after TTQ, amount, UN)
        return ok(tlv('77', [...tlv('82', [0x20, 0x00]), ...tlv('94', [0x08, 0x01, 0x01, 0x00])]));
      }
      if (apdu == '00B2010C00') {
        return ok(tlv('70', [
          ...tlv('57', fromHex('4111111111111111D29052011234567800000F')),
          ...tlv('5F20', 'NGUYEN/VAN AN'.codeUnits),
          ...tlv('5F24', fromHex('290531')),
        ]));
      }
      return null;
    });

    final data = await reader(card).read();
    expect(data, isNotNull);
    expect(data!.pan, '4111111111111111');
    expect(data.expiry, '05/29');
    expect(data.holder, 'NGUYEN VAN AN');
    expect(data.scheme, CardScheme.visa);
    expect(data.product, CardProduct.debit);
    expect(data.appLabel, 'VISA DEBIT');
  });

  test('no PPSE: falls back to known AIDs, GPO format 1, 6Cxx and 61xx handling', () async {
    final mcAid = fromHex('A0000000041010');
    final record = tlv('70', [
      ...tlv('5A', fromHex('5555555555554444')),
      ...tlv('5F24', fromHex('281231')),
      ...tlv('5F20', '/'.codeUnits), // blank name, as many contactless cards do
    ]);
    final card = FakeCard((apdu) {
      if (apdu == selectHex(mcAid)) {
        return ok(tlv('6F', [...tlv('84', mcAid), ...tlv('A5', tlv('50', 'Mastercard'.codeUnits))]));
      }
      if (apdu == '80A8000002830000') return ok(tlv('80', [0x19, 0x80, 0x10, 0x01, 0x01, 0x00]));
      if (apdu == '00B2011400') return sw(0x6C00 | record.length); // wrong Le
      if (apdu == '00B20114${record.length.toRadixString(16).padLeft(2, '0').toUpperCase()}') {
        return Uint8List.fromList([...record.sublist(0, 10), 0x61, record.length - 10]);
      }
      if (apdu.startsWith('00C00000')) return ok(record.sublist(10));
      return null;
    });

    final data = await reader(card).read();
    expect(data, isNotNull);
    expect(data!.pan, '5555555555554444');
    expect(data.expiry, '12/28');
    expect(data.holder, isNull);
    expect(data.scheme, CardScheme.mastercard);
    expect(card.sent.first, selectHex(ppseName)); // tried PPSE first
  });

  test('NAPAS card maps the issuer from its BIN', () async {
    final napasAid = fromHex('A0000007271010');
    final card = FakeCard((apdu) {
      if (apdu == selectHex(napasAid)) return ok(tlv('6F', tlv('84', napasAid)));
      if (apdu.startsWith('80A8')) return ok(tlv('77', tlv('94', [0x08, 0x01, 0x01, 0x00])));
      if (apdu == '00B2010C00') {
        return ok(tlv('70', tlv('57', fromHex('9704366614952217D3008F'))));
      }
      return null;
    });
    final data = await reader(card).read();
    expect(data!.scheme, CardScheme.napas);
    expect(data.issuer, 'Vietcombank');
    expect(data.expiry, '08/30');
  });

  test('a non-payment tag returns null', () async {
    final card = FakeCard((_) => null);
    expect(await reader(card).read(), isNull);
  });

  test('parseTlv skips padding and survives truncated data', () {
    final t = parseTlv([0x00, ...tlv('5A', [0x41, 0x11]), 0xFF, 0x5F, 0x24, 0x05, 0x29]);
    expect(findTag(t, '5A')!.value, [0x41, 0x11]);
    expect(findTag(t, '5F24'), isNull); // truncated: ignored, no throw
  });
}
