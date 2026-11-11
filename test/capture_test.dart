// The capture notification's buttons, against a fake Android side.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/capture.dart';
import 'package:tracker/data.dart';
import 'package:tracker/sms.dart';
import 'package:tracker/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 8, 14);
  final posted = <Map<Object?, Object?>>[];

  setUp(() {
    posted.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('hisaab/capture'), (call) async {
      if (call.method == 'notifyCapture') posted.add(call.arguments as Map<Object?, Object?>);
      return null;
    });
  });

  Store imported() {
    final inbox = sampleInbox(now);
    return Store.memory(clock: () => now)
      ..finishOnboarding(sms: true, since: DateTime(2026, 11), found: scanInbox(inbox), inbox: inbox);
  }

  int idOf(Store s, String name) => s.queue().firstWhere((t) => t.name == name).id;

  test('a category button files, then offers Undo for 8 s; Undo asks again', () async {
    final s = imported();
    final chai = idOf(s, 'Chai Point');
    await notificationAction(s, {'id': chai, 'cat': 'food'});
    expect((s.txn(chai)!.status, s.txn(chai)!.cat, s.ruleOf(chai)), (TxnStatus.filed, food, 'food'));
    expect((posted.last['title'], posted.last['timeout']), ('Filed · Chai Point as Food & dining', 8000));

    final undo = (posted.last['actions'] as List).single as Map;
    await notificationAction(s, {'id': chai, ...undo.cast<String, Object?>()});
    expect((s.txn(chai)!.status, s.ruleOf(chai)), (TxnStatus.needs, null)); // rule as it was before
    expect(posted.last['title'], '₹180.00 paid to Chai Point'); // the prompt again
  });

  test('Not an expense takes the notification down', () async {
    final s = imported();
    final id = idOf(s, 'PhonePe merchant ••0113');
    await notificationAction(s, {'id': id, 'ignore': true});
    expect(s.txn(id)!.status, TxnStatus.ignored);
    expect(posted.last, {'id': id, 'cancel': true});
  });

  test('a stale button (already filed in the app) does nothing', () async {
    final s = imported();
    final id = idOf(s, 'Chai Point');
    s.file(id, groc);
    await notificationAction(s, {'id': id, 'cat': 'food'});
    expect(s.txn(id)!.cat, groc);
    expect(posted, isEmpty);
  });
}
