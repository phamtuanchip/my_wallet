import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../card/card_info.dart';
import 'tlv.dart';

/// Sends one APDU to the card and returns the full response (data + SW1 SW2).
typedef Transceive = Future<Uint8List> Function(Uint8List apdu);

/// What a contactless payment card reveals without any authentication.
/// The CVV/CVC2 is never on the chip.
class EmvCardData {
  const EmvCardData({
    required this.pan,
    this.expiry,
    this.holder,
    this.appLabel,
    this.aid,
    this.scheme = CardScheme.unknown,
    this.product,
  });

  final String pan; // digits only
  final String? expiry; // MM/YY
  final String? holder; // often blank on contactless cards
  final String? appLabel; // e.g. "VISA DEBIT"
  final String? aid;
  final CardScheme scheme;
  final CardProduct? product;

  String? get issuer => issuerFromNumber(pan) ?? (appLabel == null ? null : issuerFromText(appLabel!));
}

class _Response {
  _Response(this.data, this.sw);
  final Uint8List data;
  final int sw;
  bool get ok => sw == 0x9000;
}

/// Minimal EMV contactless reader: PPSE → SELECT AID → GET PROCESSING OPTIONS →
/// READ RECORD. Read-only, no cryptograms are generated or stored, and the
/// amount sent in GPO is zero, so no transaction can result from a read.
class EmvReader {
  EmvReader(this._tx, {DateTime Function()? clock, Random? random})
      : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final Transceive _tx;
  final DateTime Function() _clock;
  final Random _random;

  /// Payment AIDs tried when the card has no PPSE directory.
  static const List<String> knownAids = [
    'A0000000031010', // Visa credit/debit
    'A0000000032010', // Visa Electron
    'A0000000041010', // Mastercard
    'A0000000043060', // Maestro
    'A0000007271010', // NAPAS
    'A0000000651010', // JCB
    'A00000002501', // American Express
    'A000000333010101', // UnionPay debit
    'A000000333010102', // UnionPay credit
    'A0000001523010', // Discover
  ];

  static const _ppse = '2PAY.SYS.DDF01';

  /// Returns null when the tag is not a readable payment card.
  Future<EmvCardData?> read() async {
    final candidates = <({String aid, String? label})>[];
    final ppse = await _select(Uint8List.fromList(ascii.encode(_ppse)));
    if (ppse.ok) {
      final tlvs = parseTlv(ppse.data);
      final entries = findAll(tlvs, '61');
      final withPriority = <({String aid, String? label, int priority})>[];
      for (final e in entries) {
        final aid = findTag(e.children, '4F');
        if (aid == null) continue;
        final label = findTag(e.children, '50');
        final prio = findTag(e.children, '87');
        withPriority.add((
          aid: toHex(aid.value),
          label: label == null ? null : _text(label.value),
          priority: prio == null || prio.value.isEmpty ? 15 : (prio.value.first & 0x0F),
        ));
      }
      withPriority.sort((a, b) => a.priority.compareTo(b.priority));
      candidates.addAll(withPriority.map((e) => (aid: e.aid, label: e.label)));
    }
    if (candidates.isEmpty) {
      candidates.addAll(knownAids.map((a) => (aid: a, label: null)));
    }

    for (final c in candidates) {
      final data = await _readApplication(c.aid, c.label);
      if (data != null) return data;
    }
    return null;
  }

  Future<EmvCardData?> _readApplication(String aid, String? ppseLabel) async {
    final fci = await _select(fromHex(aid));
    if (!fci.ok) return null;
    final fciTlv = parseTlv(fci.data);
    final label = _textOf(fciTlv, '50') ?? ppseLabel;
    final preferredName = _textOf(fciTlv, '9F12');
    final pdol = findTag(fciTlv, '9F38');

    final records = <Tlv>[];
    final gpo = await _getProcessingOptions(pdol?.value);
    if (gpo.ok) {
      final gpoTlv = parseTlv(gpo.data);
      records.addAll(gpoTlv); // format 2 may already carry track 2 / PAN
      final afl = _afl(gpoTlv);
      for (final entry in afl) {
        for (var rec = entry.first; rec <= entry.last; rec++) {
          final r = await _readRecord(entry.sfi, rec);
          if (r.ok) records.addAll(parseTlv(r.data));
        }
      }
    }
    // Some cards refuse GPO with our terminal data; their records are usually still readable.
    if (_pan(records) == null) {
      records.addAll(await _scanRecords());
    }

    final pan = _pan(records);
    if (pan == null) return null;
    final labelText = [label, preferredName].whereType<String>().join(' ');
    return EmvCardData(
      pan: pan,
      expiry: _expiry(records),
      holder: _holder(records),
      appLabel: label ?? preferredName,
      aid: aid,
      scheme: _schemeFromAid(aid) ?? detectScheme(pan),
      product: _product(aid, labelText),
    );
  }

  // ── APDUs

  Future<_Response> _send(List<int> apdu) async {
    var res = await _tx(Uint8List.fromList(apdu));
    if (res.length < 2) return _Response(Uint8List(0), 0);
    var sw = (res[res.length - 2] << 8) | res[res.length - 1];
    if ((sw >> 8) == 0x6C) {
      // Wrong Le: resend with the length the card asks for.
      final again = [...apdu.sublist(0, apdu.length - 1), sw & 0xFF];
      res = await _tx(Uint8List.fromList(again));
      if (res.length < 2) return _Response(Uint8List(0), 0);
      sw = (res[res.length - 2] << 8) | res[res.length - 1];
    }
    final data = BytesBuilder()..add(res.sublist(0, res.length - 2));
    var guard = 0;
    while ((sw >> 8) == 0x61 && guard++ < 8) {
      // More data available: GET RESPONSE.
      final more = await _tx(Uint8List.fromList([0x00, 0xC0, 0x00, 0x00, sw & 0xFF]));
      if (more.length < 2) break;
      data.add(more.sublist(0, more.length - 2));
      sw = (more[more.length - 2] << 8) | more[more.length - 1];
    }
    return _Response(data.toBytes(), sw);
  }

  Future<_Response> _select(List<int> name) =>
      _send([0x00, 0xA4, 0x04, 0x00, name.length, ...name, 0x00]);

  Future<_Response> _getProcessingOptions(Uint8List? pdol) {
    final dolData = pdol == null ? <int>[] : _fillDol(parseDol(pdol));
    final template = [0x83, dolData.length, ...dolData];
    return _send([0x80, 0xA8, 0x00, 0x00, template.length, ...template, 0x00]);
  }

  Future<_Response> _readRecord(int sfi, int record) =>
      _send([0x00, 0xB2, record, (sfi << 3) | 0x04, 0x00]);

  /// Last resort: read the first records of the usual short files.
  Future<List<Tlv>> _scanRecords() async {
    final out = <Tlv>[];
    for (var sfi = 1; sfi <= 4; sfi++) {
      for (var rec = 1; rec <= 4; rec++) {
        final r = await _readRecord(sfi, rec);
        if (r.sw == 0x6A83 || r.sw == 0x6A82) break; // no such record / file
        if (r.ok) out.addAll(parseTlv(r.data));
        if (_pan(out) != null) return out;
      }
    }
    return out;
  }

  // ── Terminal data for the PDOL

  List<int> _fillDol(List<({String tag, int length})> dol) {
    final now = _clock();
    int bcd(int v) => ((v ~/ 10) << 4) | (v % 10);
    final defaults = <String, List<int>>{
      '9F66': [0x36, 0x00, 0x40, 0x00], // TTQ: qVSDC, contact chip, online PIN, signature, CDCVM
      '9F02': [0, 0, 0, 0, 0, 0], // amount authorised: 0
      '9F03': [0, 0, 0, 0, 0, 0], // amount other: 0
      '9F1A': [0x07, 0x04], // terminal country: Viet Nam
      '5F2A': [0x07, 0x04], // currency: VND
      '95': [0, 0, 0, 0, 0], // TVR
      '9A': [bcd(now.year % 100), bcd(now.month), bcd(now.day)],
      '9F21': [bcd(now.hour), bcd(now.minute), bcd(now.second)],
      '9C': [0x00], // transaction type: purchase
      '9F35': [0x22], // terminal type
      '9F33': [0xE0, 0xF0, 0xC8], // terminal capabilities
      '9F40': [0x8E, 0x00, 0xB0, 0x50, 0x05],
      '9F37': List<int>.generate(4, (_) => _random.nextInt(256)), // unpredictable number
    };
    final out = <int>[];
    for (final e in dol) {
      final v = defaults[e.tag] ?? const <int>[];
      if (v.length >= e.length) {
        out.addAll(v.sublist(0, e.length));
      } else {
        out.addAll(v);
        out.addAll(List<int>.filled(e.length - v.length, 0));
      }
    }
    return out;
  }

  // ── Parsing helpers

  List<({int sfi, int first, int last})> _afl(List<Tlv> gpo) {
    Uint8List? afl;
    final f1 = findTag(gpo, '80');
    if (f1 != null && f1.value.length > 2) {
      afl = f1.value.sublist(2); // format 1: AIP (2 bytes) + AFL
    } else {
      afl = findTag(gpo, '94')?.value;
    }
    if (afl == null) return const [];
    return [
      for (var i = 0; i + 3 < afl.length; i += 4)
        if ((afl[i] >> 3) > 0 && afl[i + 1] > 0 && afl[i + 2] >= afl[i + 1])
          (sfi: afl[i] >> 3, first: afl[i + 1], last: min(afl[i + 2], afl[i + 1] + 15)),
    ];
  }

  static String? _pan(List<Tlv> tlvs) {
    final t5a = findTag(tlvs, '5A');
    if (t5a != null) {
      final pan = toHex(t5a.value).replaceAll('F', '');
      if (pan.length >= 12 && RegExp(r'^\d+$').hasMatch(pan)) return pan;
    }
    for (final tag in ['57', '9F6B']) {
      final t = findTag(tlvs, tag);
      if (t == null) continue;
      final track2 = toHex(t.value);
      final sep = track2.indexOf('D');
      if (sep >= 12) return track2.substring(0, sep);
    }
    final track1 = findTag(tlvs, '56');
    if (track1 != null) {
      final m = RegExp(r'^B?(\d{12,19})\^').firstMatch(_text(track1.value));
      if (m != null) return m.group(1);
    }
    return null;
  }

  static String? _expiry(List<Tlv> tlvs) {
    final t = findTag(tlvs, '5F24'); // YYMMDD
    if (t != null && t.value.length >= 2) {
      final hex = toHex(t.value);
      final e = parseExpiry('${hex.substring(2, 4)}/${hex.substring(0, 2)}');
      if (e != null) return formatExpiry(e.month, e.year);
    }
    for (final tag in ['57', '9F6B']) {
      final tr = findTag(tlvs, tag);
      if (tr == null) continue;
      final track2 = toHex(tr.value);
      final sep = track2.indexOf('D');
      if (sep >= 0 && track2.length >= sep + 5) {
        final yymm = track2.substring(sep + 1, sep + 5);
        final e = parseExpiry('${yymm.substring(2)}/${yymm.substring(0, 2)}');
        if (e != null) return formatExpiry(e.month, e.year);
      }
    }
    return null;
  }

  static String? _holder(List<Tlv> tlvs) {
    for (final tag in ['5F20', '9F0B']) {
      final t = findTag(tlvs, tag);
      if (t == null) continue;
      final name = _text(t.value).replaceAll('/', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (name.length < 2) continue;
      if (RegExp(r'CARDHOLDER|CARD HOLDER|CUSTOMER', caseSensitive: false).hasMatch(name)) continue;
      return name.toUpperCase();
    }
    return null;
  }

  static CardScheme? _schemeFromAid(String aid) {
    if (aid.startsWith('A000000003')) return CardScheme.visa;
    if (aid.startsWith('A000000004')) return CardScheme.mastercard;
    if (aid.startsWith('A000000727')) return CardScheme.napas;
    if (aid.startsWith('A000000065')) return CardScheme.jcb;
    if (aid.startsWith('A000000025')) return CardScheme.amex;
    if (aid.startsWith('A000000333')) return CardScheme.unionpay;
    if (aid.startsWith('A000000152')) return CardScheme.discover;
    return null;
  }

  static CardProduct? _product(String aid, String label) {
    final l = label.toUpperCase();
    if (l.contains('DEBIT')) return CardProduct.debit;
    if (l.contains('CREDIT')) return CardProduct.credit;
    if (l.contains('PREPAID')) return CardProduct.prepaid;
    if (aid == 'A0000000032010' || aid == 'A0000000043060' || aid == 'A000000333010101') {
      return CardProduct.debit; // Visa Electron, Maestro, UnionPay debit
    }
    if (aid == 'A000000333010102') return CardProduct.credit;
    return null;
  }

  static String? _textOf(List<Tlv> tlvs, String tag) {
    final t = findTag(tlvs, tag);
    if (t == null) return null;
    final s = _text(t.value).trim();
    return s.isEmpty ? null : s;
  }

  static String _text(List<int> bytes) =>
      String.fromCharCodes(bytes.where((b) => b >= 0x20 && b < 0x7F));
}
