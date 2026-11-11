import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/capture.dart';
import 'package:tracker/data.dart';
import 'package:tracker/sms.dart';
import 'package:tracker/store.dart';

void main() {
  final now = DateTime(2026, 11, 8, 14);
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('hisaab'));
  tearDown(() => dir.deleteSync(recursive: true));

  Store onboarded() {
    final inbox = sampleInbox(now);
    return Store.memory(clock: () => now)
      ..finishOnboarding(sms: true, since: DateTime(2026, 11), found: scanInbox(inbox), inbox: inbox);
  }

  test('a backup imports into a fresh install, filing and all', () async {
    final a = onboarded(), t = a.queue().first;
    a.file(t.id, cats.first);
    a.backupTo('${dir.path}/backup.db');

    final b = Store.open('${dir.path}/live.db'); // a file in WAL mode, as on the phone
    expect(b.onboarded, isFalse);
    await b.restoreFrom('${dir.path}/backup.db');
    expect(b.onboarded, isTrue);
    expect(b.counts, a.counts);
    expect((b.txn(t.id)!.status, b.txn(t.id)!.cat), (TxnStatus.filed, cats.first));
    b.dispose();
  });

  test("a file that isn't a backup changes nothing", () async {
    final s = onboarded(), before = s.counts;
    File('${dir.path}/notes.db').writeAsStringSync('not a database');
    await expectLater(s.restoreFrom('${dir.path}/notes.db'), throwsFormatException);
    expect(s.counts, before);
  });
}
