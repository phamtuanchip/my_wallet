import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_wallet/nfc/emrtd/bac.dart';
import 'package:my_wallet/nfc/emrtd/data_groups.dart';
import 'package:my_wallet/nfc/emrtd/emrtd_reader.dart';
import 'package:my_wallet/nfc/emrtd/mrz.dart';
import 'package:my_wallet/nfc/emv/tlv.dart';

/// Worked example from ICAO Doc 9303 Part 11, Appendix D.
final _icaoKey = BacKey('L898902C', '690806', '940623');
final _rndIc = fromHex('4608F91988702212');
final _rndIfd = fromHex('781723860C06C226');
final _kIfd = fromHex('0B795240CB7049B01C19B33E32804F0B');
final _kIc = fromHex('0B4F80323EB3191CB04970CB4052790B');

Uint8List Function(int) _icaoRandom() {
  final queue = [_rndIfd, _kIfd];
  return (n) => queue.removeAt(0);
}

void main() {
  group('BAC key derivation (ICAO 9303-11 App. D)', () {
    test('MRZ information, seed and keys', () {
      expect(_icaoKey.mrzInformation, 'L898902C<369080619406236');
      final seed = bacKeySeed(_icaoKey);
      expect(toHex(seed), '239AB9CB282DAF66231DC5A4DF6BFBAE');
      expect(toHex(deriveKey(seed, 1)), 'AB94FDECF2674FDFB9B391F85D7F76F2');
      expect(toHex(deriveKey(seed, 2)), '7962D9ECE03D1ACD4C76089DCE131543');
    });

    test('mutual authentication cryptogram and MAC', () {
      final kEnc = fromHex('AB94FDECF2674FDFB9B391F85D7F76F2');
      final kMac = fromHex('7962D9ECE03D1ACD4C76089DCE131543');
      final eIfd = tdesEncrypt(kEnc, Uint8List.fromList([..._rndIfd, ..._rndIc, ..._kIfd]));
      expect(toHex(eIfd), '72C29C2371CC9BDB65B779B8E8D37B29ECC154AA56A8799FAE2F498F76ED92F2');
      expect(toHex(retailMac(kMac, eIfd)), '5F1448EEA8AD90A7');
    });
  });

  test('performBac derives the ICAO session keys and SSC', () async {
    final sent = <String>[];
    Future<Uint8List> tx(Uint8List apdu) async {
      sent.add(toHex(apdu));
      if (apdu[1] == 0x84) return Uint8List.fromList([..._rndIc, 0x90, 0x00]);
      return fromHex('46B9342A41396CD7386BF5803104D7CEDC122B9132139BAF2EEDC94EE178534F2F2D235D074D74499000');
    }

    final sm = await performBac(tx, _icaoKey, random: _icaoRandom());
    expect(sent.last,
        '008200002872C29C2371CC9BDB65B779B8E8D37B29ECC154AA56A8799FAE2F498F76ED92F25F1448EEA8AD90A728');
    expect(toHex(sm.ksEnc), '979EC13B1CBFE9DCD01AB0FED307EAE5');
    expect(toHex(sm.ksMac), 'F1CB1F1FB5ADF208806B89DC579DC1F8');
    expect(toHex(sm.ssc), '887022120C06C226');
  });

  test('performBac reports a wrong key as access denied', () async {
    Future<Uint8List> tx(Uint8List apdu) async =>
        apdu[1] == 0x84 ? Uint8List.fromList([..._rndIc, 0x90, 0x00]) : fromHex('6300');
    expect(() => performBac(tx, _icaoKey), throwsA(isA<BacException>()));
  });

  test('secure messaging matches the ICAO SELECT / READ BINARY example', () {
    final sm = SecureMessaging(
      fromHex('979EC13B1CBFE9DCD01AB0FED307EAE5'),
      fromHex('F1CB1F1FB5ADF208806B89DC579DC1F8'),
      fromHex('887022120C06C226'),
    );
    expect(toHex(sm.wrap(fromHex('00A4020C02011E'))),
        '0CA4020C158709016375432908C044F68E08BF8B92D635FF24F800');
    expect(toHex(sm.unwrap(fromHex('990290008E08FA855A5D4C50A8ED9000'))), '9000');

    expect(toHex(sm.wrap(fromHex('00B0000004'))), '0CB000000D9701048E08ED6705417E96BA5500');
    expect(toHex(sm.unwrap(fromHex('8709019FF0EC34F9922651990290008E08AD55CC17140B2DED9000'))), '60145F019000');

    expect(toHex(sm.wrap(fromHex('00B0000412'))), '0CB000040D9701128E082EA28A70F3C7B53500');
    expect(
        toHex(sm.unwrap(fromHex(
            '871901FB9235F4E4037F2327DCC8964F1F9B8C30F42C8E2FFF224A990290008E08C8B2787EAEA07D749000'))),
        '04303130365F36063034303030305C0261759000');
  });

  test('a tampered response fails the MAC check', () {
    final sm = SecureMessaging(
      fromHex('979EC13B1CBFE9DCD01AB0FED307EAE5'),
      fromHex('F1CB1F1FB5ADF208806B89DC579DC1F8'),
      fromHex('887022120C06C227'),
    );
    expect(() => sm.unwrap(fromHex('990290018E08FA855A5D4C50A8ED9000')), throwsA(isA<SecureMessagingException>()));
  });

  group('MRZ', () {
    test('check digits', () {
      expect(mrzCheckDigit('L898902C<'), 3);
      expect(mrzCheckDigit('690806'), 1);
      expect(mrzCheckDigit('940623'), 6);
    });

    test('TD3 passport (ICAO specimen)', () {
      final m = parseMrz([
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
        'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
      ])!;
      expect(m.format, 'TD3');
      expect(m.documentNumber, 'L898902C3');
      expect(m.birthDate, '740812');
      expect(m.expiryDate, '120415');
      expect(m.sex, 'F');
      expect(m.surname, 'ERIKSSON');
      expect(m.givenNames, 'ANNA MARIA');
      expect(m.checksOk, isTrue);
    });

    test('TD1 Vietnamese CCCD with the 12-digit number in the optional data', () {
      final number = '001090123456';
      final doc = number.substring(3); // last 9 digits
      final line1 = 'IDVNM$doc${mrzCheckDigit(doc)}$number<<<'.padRight(30, '<').substring(0, 30);
      final line2 = '900115${mrzCheckDigit('900115')}M300115${mrzCheckDigit('300115')}VNM<<<<<<<<<<<0';
      final m = findMrz(['CĂN CƯỚC CÔNG DÂN', line1.toLowerCase(), line2.replaceAll('0', 'O'), 'NGUYEN<<VAN<AN<<<<<<<<<<<<<<<<'])!;
      expect(m.format, 'TD1');
      expect(m.documentNumber, doc);
      expect(m.vnIdNumber, number);
      expect(m.birthDate, '900115');
      expect(m.expiryDate, '300115');
      expect(m.fullName, 'NGUYEN VAN AN');
      expect(m.checksOk, isTrue);
    });

    test('dates convert both ways with the right century', () {
      final now = DateTime(2026, 11, 4);
      expect(toMrzDate('15/01/1990'), '900115');
      expect(toMrzDate('1/2/2030'), '300201');
      expect(toMrzDate('31/13/2030'), isNull);
      expect(fromMrzDate('900115', isExpiry: false, now: now), '15/01/1990');
      expect(fromMrzDate('150115', isExpiry: false, now: now), '15/01/2015');
      expect(fromMrzDate('300115', isExpiry: true, now: now), '15/01/2030');
      expect(fromMrzDate('990101', isExpiry: true, now: now), '01/01/2099');
    });
  });

  group('data groups', () {
    test('DG2 face image is found inside the biometric block', () {
      final jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9];
      final header = ascii.encode('FAC\u0000010\u0000') + List.filled(30, 0);
      final dg2 = _tlv(0x75, _tlv2(0x7F61, _tlv2(0x7F60, _tlv2(0x5F2E, [...header, ...jpeg]))));
      final face = extractFaceImage(Uint8List.fromList(dg2))!;
      expect(face.format, FaceImageFormat.jpeg);
      expect(face.bytes, jpeg);
    });

    test('Vietnamese DG13 items map to fields, parents split', () {
      List<int> item(int i, List<String> values) => _tlv(0x30, [
            0x02, 0x01, i,
            for (final v in values) ..._tlv(0x0C, utf8.encode(v)),
          ]);
      final dg13 = _tlv(0x6D, _tlv(0x30, [
        0x02, 0x01, 0x01, // version, not an item of its own
        ...item(1, ['001090123456']),
        ...item(2, ['Nguyễn Văn An']),
        ...item(9, ['Số 1 Tràng Tiền, Hoàn Kiếm, Hà Nội']),
        ...item(13, ['Nguyễn Văn Bình', 'Trần Thị Cúc']),
        ...item(99, ['ignored']),
      ]));
      final fields = parseVnDg13(Uint8List.fromList(dg13));
      expect(fields['number'], '001090123456');
      expect(fields['holder'], 'Nguyễn Văn An');
      expect(fields['residence'], 'Số 1 Tràng Tiền, Hoàn Kiếm, Hà Nội');
      expect(fields['father'], 'Nguyễn Văn Bình');
      expect(fields['mother'], 'Trần Thị Cúc');
      expect(fields.containsKey('99'), isFalse);
    });

    test('garbage DG13 gives an empty map', () {
      expect(parseVnDg13(Uint8List.fromList([0x6D, 0x05, 0x01])), isEmpty);
    });
  });

  test('EmrtdReader reads DG1, DG2 and DG13 from a simulated chip', () async {
    final number = '001090123456';
    final doc = number.substring(3);
    final mrz = 'IDVNM$doc${mrzCheckDigit(doc)}${number.padRight(15, '<')}'
        '900115${mrzCheckDigit('900115')}M300115${mrzCheckDigit('300115')}VNM<<<<<<<<<<<0'
        'NGUYEN<<VAN<AN<<<<<<<<<<<<<<<<';
    final face = [0xFF, 0xD8, 0xFF, 0xE0, ...List.generate(600, (i) => i & 0x7F), 0xFF, 0xD9];
    final chip = _ChipSim(BacKey(doc, '900115', '300115'), {
      0x0101: _tlv(0x61, _tlv2(0x5F1F, ascii.encode(mrz))),
      0x0102: _tlv(0x75, _tlv2(0x7F61, _tlv2(0x7F60, _tlv2(0x5F2E, face)))),
      0x010D: _tlv(0x6D, _tlv(0x30, [..._tlv(0x30, [0x02, 0x01, 0x02, ..._tlv(0x0C, utf8.encode('Nguyễn Văn An'))])])),
    });

    final steps = <EmrtdStep>[];
    final data = await EmrtdReader(chip.transceive).read(
      BacKey(doc, '900115', '300115'),
      readVnPersonal: true,
      onProgress: (s, _) => steps.add(s),
    );
    expect(data.mrz.vnIdNumber, number);
    expect(data.mrz.fullName, 'NGUYEN VAN AN');
    expect(data.faceImage, face);
    expect(data.faceFormat, FaceImageFormat.jpeg);
    expect(data.vnPersonal['holder'], 'Nguyễn Văn An');
    expect(steps.last, EmrtdStep.done);

    expect(await EmrtdReader.probe(chip.transceive), isTrue);
    expect(
      () => EmrtdReader(_ChipSim(BacKey(doc, '900115', '300115'), {}).transceive)
          .read(BacKey(doc, '900116', '300115')),
      throwsA(isA<EmrtdAccessDenied>()),
    );
  });
}

List<int> _len(int n) => n < 0x80 ? [n] : (n <= 0xFF ? [0x81, n] : [0x82, n >> 8, n & 0xFF]);
List<int> _tlv(int tag, List<int> value) => [tag, ..._len(value.length), ...value];
List<int> _tlv2(int tag, List<int> value) => [tag >> 8, tag & 0xFF, ..._len(value.length), ...value];

/// Minimal eMRTD chip: BAC, then protected SELECT / READ BINARY over [files].
class _ChipSim {
  _ChipSim(this.key, this.files);

  final BacKey key;
  final Map<int, List<int>> files;
  final Uint8List _rnd = fromHex('4608F91988702212');
  SecureMessaging? _sm; // used from the chip side: unwrap = check command, wrap = response
  Uint8List? _ksEnc, _ksMac;
  Uint8List _ssc = Uint8List(8);
  List<int>? _selected;

  Future<Uint8List> transceive(Uint8List apdu) async {
    if (apdu[1] == 0xA4 && apdu[2] == 0x04) return fromHex('9000');
    if (apdu[1] == 0x84) return Uint8List.fromList([..._rnd, 0x90, 0x00]);
    if (apdu[1] == 0x82) return _externalAuth(apdu);
    return _protected(apdu);
  }

  Uint8List _externalAuth(Uint8List apdu) {
    final seed = bacKeySeed(key);
    final kEnc = deriveKey(seed, 1), kMac = deriveKey(seed, 2);
    final e = apdu.sublist(5, 37), m = apdu.sublist(37, 45);
    if (toHex(retailMac(kMac, e)) != toHex(m)) return fromHex('6300');
    final s = tdesDecrypt(kEnc, e);
    if (toHex(s.sublist(8, 16)) != toHex(_rnd)) return fromHex('6300');
    final rndIfd = s.sublist(0, 8), kIfd = s.sublist(16, 32);
    final r = tdesEncrypt(kEnc, Uint8List.fromList([..._rnd, ...rndIfd, ..._kIc]));
    final sessionSeed = Uint8List.fromList(List.generate(16, (i) => kIfd[i] ^ _kIc[i]));
    _ksEnc = deriveKey(sessionSeed, 1);
    _ksMac = deriveKey(sessionSeed, 2);
    _ssc = Uint8List.fromList([..._rnd.sublist(4), ...rndIfd.sublist(4)]);
    _sm = SecureMessaging(_ksEnc!, _ksMac!, _ssc);
    return Uint8List.fromList([...r, ...retailMac(kMac, r), 0x90, 0x00]);
  }

  void _inc() {
    for (var i = 7; i >= 0; i--) {
      _ssc[i] = (_ssc[i] + 1) & 0xFF;
      if (_ssc[i] != 0) break;
    }
  }

  Uint8List _protected(Uint8List apdu) {
    if (_sm == null) return fromHex('6982');
    // Verify the command MAC and decrypt it.
    _inc();
    final body = parseTlv(apdu.sublist(5, 5 + apdu[4]));
    final do87 = body.where((t) => t.tag == '87').firstOrNull;
    final do97 = body.where((t) => t.tag == '97').firstOrNull;
    final do8e = body.firstWhere((t) => t.tag == '8E');
    final macInput = [
      ..._ssc, ...pad(apdu.sublist(0, 4)),
      if (do87 != null) ...[0x87, ..._len(do87.value.length), ...do87.value],
      if (do97 != null) ...[0x97, 0x01, ...do97.value],
    ];
    if (toHex(retailMac(_ksMac!, macInput)) != toHex(do8e.value)) return fromHex('6988');
    final data = do87 == null ? <int>[] : unpad(tdesDecrypt(_ksEnc!, do87.value.sublist(1)));

    List<int> out;
    var sw = [0x90, 0x00];
    if (apdu[1] == 0xA4) {
      _selected = files[(data[0] << 8) | data[1]];
      out = [];
      if (_selected == null) sw = [0x6A, 0x82];
    } else {
      final offset = (apdu[2] << 8) | apdu[3];
      final le = do97!.value[0];
      final f = _selected ?? [];
      out = f.sublist(offset.clamp(0, f.length), (offset + le).clamp(0, f.length));
    }

    // Protected response.
    _inc();
    final r87 = out.isEmpty ? <int>[] : () {
      final enc = tdesEncrypt(_ksEnc!, pad(out));
      return [0x87, ..._len(enc.length + 1), 0x01, ...enc];
    }();
    final r99 = [0x99, 0x02, ...sw];
    final cc = retailMac(_ksMac!, [..._ssc, ...r87, ...r99]);
    return Uint8List.fromList([...r87, ...r99, 0x8E, 0x08, ...cc, ...sw]);
  }
}
