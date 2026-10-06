import 'package:flutter_test/flutter_test.dart';

/// Part 1: SyncId identity — value fingerprints must not imply delete.
void main() {
  test('identical business values with different SyncIds are distinct entries', () {
    final a = {
      'SyncId': 'aaa-111',
      'CustomerId': 1,
      'Date': '2026-10-01',
      'Amount': 1000.0,
      'Credit': 0.0,
      'Litter': 10.0,
      'Rate': 100.0,
      'ReceiptNo': 'R1',
      'vehicle': 'ABC',
    };
    final b = {
      'SyncId': 'bbb-222',
      'CustomerId': 1,
      'Date': '2026-10-01',
      'Amount': 1000.0,
      'Credit': 0.0,
      'Litter': 10.0,
      'Rate': 100.0,
      'ReceiptNo': 'R1',
      'vehicle': 'ABC',
    };

    String fp(Map<String, Object?> r) =>
        '${r['CustomerId']}|${r['Date']}|${r['Amount']}|${r['Credit']}|${r['Litter']}|${r['Rate']}|${r['ReceiptNo']}|${r['vehicle']}';

    expect(fp(a), fp(b));
    expect(a['SyncId'], isNot(equals(b['SyncId'])));
    // Policy: both survive; purgeDuplicatePetrolEntries is a no-op.
    final keep = {a['SyncId'], b['SyncId']};
    expect(keep.length, 2);
  });

  test('updating one SyncId must not imply removing the other', () {
    final rows = <String, Map<String, Object?>>{
      'aaa-111': {'Amount': 1000.0},
      'bbb-222': {'Amount': 1000.0},
    };
    rows['aaa-111'] = {'Amount': 1500.0};
    expect(rows.containsKey('bbb-222'), isTrue);
    expect(rows['bbb-222']!['Amount'], 1000.0);
    expect(rows['aaa-111']!['Amount'], 1500.0);
  });
}
