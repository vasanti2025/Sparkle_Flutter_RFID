import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_flutter/views/search_screen.dart';

SearchItem _item(int n) {
  final chip = n.toRadixString(16).padLeft(24, 'A');
  return SearchItem(
    epc: chip,
    itemCode: 'ITEM$n',
    productName: 'P$n',
    rfid: chip,
  );
}

void main() {
  test('47 unmatched reads all register and never fall', () {
    final items = List<SearchItem>.generate(47, _item);
    final seen = <int>{};

    for (var i = 0; i < items.length; i++) {
      final percent = 10 + (i % 80);
      final changed = applyUnmatchedRead(items[i], percent, '-$percent');
      expect(changed, isTrue, reason: 'item $i first read');
      expect(items[i].proximityPercent, greaterThan(0));
      seen.add(i);
    }
    expect(seen, hasLength(47));

    final peaks = items.map((item) => item.proximityPercent).toList();
    for (var i = 0; i < items.length; i++) {
      applyUnmatchedRead(items[i], 1, '-90');
      applyUnmatchedRead(items[i], 0, '0');
      applyUnmatchedRead(items[i], -1, '');
      expect(items[i].proximityPercent, peaks[i], reason: 'item $i kept its peak');
    }
  });

  test('a chip with no RSSI is still seen, then a real read can only rise', () {
    final quiet = _item(1);
    expect(applyUnmatchedRead(quiet, -1, '0'), isTrue);
    expect(quiet.proximityPercent, 5);
    expect(applyUnmatchedRead(quiet, -1, '0'), isFalse);
    expect(quiet.proximityPercent, 5);
    expect(applyUnmatchedRead(quiet, 62, '-55'), isTrue);
    expect(quiet.proximityPercent, greaterThanOrEqualTo(60));
    expect(applyUnmatchedRead(quiet, 20, '-70'), isFalse);
    expect(quiet.proximityPercent, greaterThanOrEqualTo(60));
  });

  test('shared index keys do not hide an earlier item', () {
    final map = <String, int>{};
    expect(claimUnmatchedIndexKey(map, 'SHARED', 0), isTrue);
    expect(claimUnmatchedIndexKey(map, 'SHARED', 1), isFalse);
    expect(claimUnmatchedIndexKey(map, 'CHIP-0', 0), isTrue);
    expect(claimUnmatchedIndexKey(map, 'CHIP-1', 1), isTrue);
    expect(map['SHARED'], 0);
    expect(map['CHIP-0'], 0);
    expect(map['CHIP-1'], 1);
  });
}
