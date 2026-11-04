import 'package:flutter_test/flutter_test.dart';

import 'package:my_wallet/main.dart';

void main() {
  test('NFCCard survives a toMap/fromMap round trip', () {
    final card = NFCCard(
      id: 'id-1',
      uid: '04A1B2C3',
      name: 'Card 1',
      tagType: 'NFC Type A',
      content: 'U: 0068747470',
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      colorIndex: 3,
    );

    final copy = NFCCard.fromMap(card.toMap());

    expect(copy.id, card.id);
    expect(copy.uid, card.uid);
    expect(copy.name, card.name);
    expect(copy.tagType, card.tagType);
    expect(copy.content, card.content);
    expect(copy.timestamp, card.timestamp);
    expect(copy.colorIndex, card.colorIndex);
  });

  test('NFCCard defaults to the dark colour when the column is missing', () {
    final card = NFCCard.fromMap({
      'id': 'id-2',
      'uid': 'AABB',
      'name': 'Legacy',
      'tagType': 'Mifare Classic 1K',
      'content': null,
      'timestamp': 0,
    });

    expect(card.colorIndex, 7);
  });
}
