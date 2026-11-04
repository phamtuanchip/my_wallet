import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';

/// What a 13.56 MHz access card (elevator, smart lock, hotel, office) reveals
/// to the phone. Read-only: nothing is written to the card.
class NfcTagInfo {
  const NfcTagInfo({
    required this.uid,
    required this.chipType,
    this.sak,
    this.atqa,
    this.sizeBytes,
    this.defaultKeySectors,
    this.sectorCount,
    this.block0,
    this.keyCheckPartial = false,
  });

  final String uid; // hex, e.g. 04A1B2C3
  final String chipType; // e.g. "MIFARE Classic 1K"
  final int? sak;
  final String? atqa;
  final int? sizeBytes;

  /// MIFARE Classic only: sectors that open with a well-known default key.
  /// Null when the phone can't talk MIFARE Classic (non-NXP NFC controller).
  final int? defaultKeySectors;
  final int? sectorCount;

  /// The card stopped answering mid-check (moved, or the phone dropped it
  /// after a failed key): [defaultKeySectors] is a lower bound.
  final bool keyCheckPartial;

  /// Manufacturer block (UID, BCC, SAK, ATQA, maker data), hex.
  final String? block0;

  /// UID length 4 bytes = "NUID"/random-able; 7 bytes = unique NXP UID.
  String get uidKind => switch (uid.length) { 8 => '4-byte UID', 14 => '7-byte UID', 20 => '10-byte UID', _ => 'UID' };

  Map<String, String> toFields() => {
        'frequency': '13.56 MHz (NFC)',
        'chipType': chipType,
        'uid': uid,
        if (sak != null) 'sakAtqa': 'SAK ${_hex([sak!])}${atqa == null ? '' : ' · ATQA $atqa'}',
        if (!keyCheckPartial && defaultKeySectors != null && sectorCount != null)
          'keyCheck': defaultKeySectors == 0
              ? 'No sector opens with a default key (data protected)'
              : '$defaultKeySectors/$sectorCount sectors open with a default key',
        if (keyCheckPartial) 'keyCheck': '${defaultKeySectors ?? 0}+ sectors open with a default key (check stopped early)',
        'block0': ?block0,
      };
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

/// Chip family from SAK (NXP AN10833), refined by what Android reports.
String chipTypeFromSak(int sak, {bool isoDep = false}) => switch (sak) {
      0x08 => 'MIFARE Classic 1K',
      0x18 => 'MIFARE Classic 4K',
      0x09 => 'MIFARE Mini',
      0x88 => 'MIFARE Classic 1K (Infineon)',
      0x10 || 0x11 => 'MIFARE Plus 2K/4K (SL2)',
      0x00 => 'MIFARE Ultralight / NTAG',
      0x28 || 0x38 => 'Smart card with MIFARE Classic emulation',
      0x20 || 0x24 => isoDep ? 'MIFARE DESFire / Plus SL3 / ISO 14443-4' : 'ISO 14443-4 card',
      _ => 'NFC-A card (SAK ${_hex([sak])})',
    };

/// Keys that ship on blank or carelessly set-up MIFARE Classic cards.
final List<Uint8List> kDefaultMifareKeys = [
  Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
  Uint8List.fromList([0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]),
  Uint8List.fromList([0xD3, 0xF7, 0xD3, 0xF7, 0xD3, 0xF7]),
  Uint8List.fromList([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
];

/// Reads UID / type, and for MIFARE Classic checks which sectors use a default
/// key (that's what makes a card easy to copy) and reads block 0.
Future<NfcTagInfo?> readNfcTagInfo(NfcTag tag) async {
  final nfcA = NfcA.from(tag);
  final isoDep = IsoDep.from(tag);
  if (nfcA == null) {
    final other = NfcB.from(tag)?.identifier ?? NfcF.from(tag)?.identifier ?? NfcV.from(tag)?.identifier;
    if (other == null) return null;
    final type = NfcB.from(tag) != null
        ? 'NFC-B card'
        : NfcF.from(tag) != null
            ? 'FeliCa'
            : 'ISO 15693 (NFC-V)';
    return NfcTagInfo(uid: _hex(other), chipType: type);
  }

  final sak = nfcA.sak;
  final atqa = _hex(nfcA.atqa);
  var type = chipTypeFromSak(sak, isoDep: isoDep != null);
  final ul = MifareUltralight.from(tag);
  if (ul != null) type = ul.type == 2 ? 'MIFARE Ultralight C' : 'MIFARE Ultralight / NTAG';

  final mc = MifareClassic.from(tag);
  int? opened;
  String? block0;
  var partial = false;
  if (mc != null) {
    opened = 0;
    sectors:
    for (var sector = 0; sector < mc.sectorCount; sector++) {
      for (final key in kDefaultMifareKeys) {
        try {
          if (await mc.authenticateSectorWithKeyA(sectorIndex: sector, key: key)) {
            opened = opened! + 1;
            if (sector == 0) block0 = _hex(await mc.readBlock(blockIndex: 0));
            break;
          }
        } catch (_) {
          // Card moved, or the phone lost the card after a failed key: stop
          // and report what was found rather than a wrong total.
          partial = true;
          break sectors;
        }
      }
    }
  }

  return NfcTagInfo(
    uid: _hex(nfcA.identifier),
    chipType: type,
    sak: sak,
    atqa: atqa,
    sizeBytes: mc?.size,
    sectorCount: mc?.sectorCount,
    defaultKeySectors: opened,
    block0: block0,
    keyCheckPartial: partial,
  );
}
