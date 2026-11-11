// SMS capture: the Android permission, the inbox, and SMS as they arrive
// (android/.../SmsReceiver.kt and MainActivity.kt hold the other end).
// Off Android (tests, desktop runs) a sample inbox stands in, in debug only.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'data.dart';
import 'format.dart';
import 'sms.dart';
import 'store.dart';

const _ch = MethodChannel('hisaab/capture');
final _android = !kIsWeb && Platform.isAndroid;

/// Asks for RECEIVE_SMS and READ_SMS. Off Android: granted, for the sample inbox.
Future<bool> requestSmsPermission() async =>
    !_android || (await _ch.invokeMethod<bool>('requestPermission', 'sms') ?? false);

/// Asks to post notifications (a runtime permission from Android 13).
Future<bool> requestNotificationPermission() async =>
    !_android || (await _ch.invokeMethod<bool>('requestPermission', 'notifications') ?? false);

/// Saves [bytes] where the user picks (Android's "Save as"). false: cancelled
/// or not on Android.
Future<bool> saveFile(String name, Uint8List bytes, {String type = 'text/csv'}) async =>
    _android && (await _ch.invokeMethod<bool>('saveFile', {'name': name, 'bytes': bytes, 'type': type}) ?? false);

/// A file the user picks (Android's "Open"), read whole. null: cancelled or
/// not on Android.
Future<Uint8List?> openFile() async => _android ? _ch.invokeMethod<Uint8List>('openFile') : null;

/// Inbox SMS received from [since] on that mention an amount, oldest first.
/// Which of them are bank payments is the store's call.
Future<List<Sms>> readInbox(DateTime since, {DateTime? now}) async {
  if (!_android) {
    return kDebugMode ? sampleInbox(now ?? DateTime.now()).where((s) => !s.at.isBefore(since)).toList() : const [];
  }
  final rows = await _ch.invokeListMethod<Map<Object?, Object?>>('inbox', {'since': since.millisecondsSinceEpoch});
  return [for (final r in rows ?? const <Map<Object?, Object?>>[]) _sms(r)];
}

Sms _sms(Map<Object?, Object?> m) =>
    (sender: m['sender'] as String, body: m['body'] as String, at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int));

/// Wires the running app to the phone: SMS pushed in as they arrive, the
/// inbox read again on launch and on every resume, the receiver switched
/// on or off and the check-in alarm kept in step with Settings, and
/// notification taps routed to [open] ('review', 'add' or `txn:<id>`).
void startCapture(Store s, {required void Function(String route) open}) {
  if (!_android) return;
  _ch.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'sms':
        final m = _sms(call.arguments as Map<Object?, Object?>);
        await _notifyCaptured(s, s.ingest(m.sender, m.body, m.at));
      case 'action':
        await notificationAction(s, call.arguments as Map<Object?, Object?>);
      case 'route':
        open(call.arguments as String);
    }
  });
  bool? capturing;
  var alarm = '';
  void push() {
    if (s.captureOn != capturing) {
      capturing = s.captureOn;
      _ch.invokeMethod('capture', capturing);
    }
    final on = s.onboarded && s.reminderOn, at = s.reminderAt;
    if ('$on ${at.hour}:${at.minute}' != alarm) {
      alarm = '$on ${at.hour}:${at.minute}';
      _ch.invokeMethod('reminder', {'on': on, 'hour': at.hour, 'minute': at.minute});
    }
  }

  s.addListener(push);
  push();
  AppLifecycleListener(onResume: () => catchUp(s));
  catchUp(s);
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final route = await _ch.invokeMethod<String>('launchRoute');
    if (route != null && s.onboarded) open(route);
  });
}

/// Reads the inbox from where the last read stopped. Notices SMS access
/// taken away in Android settings.
Future<void> catchUp(Store s) async {
  if (!_android || !s.onboarded || !s.smsOn) return;
  if (!(await _ch.invokeMethod<bool>('hasPermission', 'sms') ?? false)) return s.smsOff();
  s.catchUp(await readInbox(s.inboxFrom));
}

/// The UI-less run the check-in alarm starts: word the notification from
/// the ledger, hand it to Android to post.
Future<void> postReminder(Store s) async {
  try {
    final c = s.checkIn();
    await _ch.invokeMethod('notify', {
      'pending': c.pending,
      'title': c.title,
      'text': c.text,
      'lines': c.lines,
      'summary': c.summary,
    });
  } finally {
    await _ch.invokeMethod('done');
  }
}

/// The UI-less run SmsReceiver starts for an SMS that arrives with the app
/// closed: file it, notify, then tell Android this engine can go.
Future<void> captureOne(Store s) async {
  try {
    final m = await _ch.invokeMapMethod<Object?, Object?>('pending');
    if (m != null) {
      final sms = _sms(m);
      await _notifyCaptured(s, s.ingest(sms.sender, sms.body, sms.at));
    }
  } finally {
    await _ch.invokeMethod('done');
  }
}

/// The UI-less run for a capture notification's button with the app closed.
Future<void> actionOne(Store s) async {
  try {
    final a = await _ch.invokeMapMethod<Object?, Object?>('pending');
    if (a != null) await notificationAction(s, a);
  } finally {
    await _ch.invokeMethod('done');
  }
}

Future<void> _notifyCaptured(Store s, int? id) async {
  final n = id == null ? null : s.captureNotice(id);
  if (n != null) await _ch.invokeMethod('notifyCapture', n);
}

/// A capture notification's button: file in a category (then "Filed ·
/// Undo" for 8 s), Not an expense, or Undo (the original prompt again).
Future<void> notificationAction(Store s, Map<Object?, Object?> a) async {
  final id = a['id'] as int;
  final t = s.txn(id);
  if (t == null) return;
  if (a['undo'] == true) {
    s.unfile(id, rule: a['rule'] as String?);
    return _notifyCaptured(s, id);
  }
  if (a['ignore'] == true) {
    s.ignore(id);
    return _ch.invokeMethod('notifyCapture', {'id': id, 'cancel': true});
  }
  final cat = catOf(a['cat'] as String?);
  if (cat == null || t.status != TxnStatus.needs) return;
  final rule = s.ruleOf(id);
  s.file(id, cat);
  await _ch.invokeMethod('notifyCapture', {
    'id': id,
    'channel': 'capture',
    'title': 'Filed · ${t.name} as ${cat.full}',
    'text': rupees(t.paise),
    'route': 'txn:$id',
    'timeout': 8000,
    'actions': [
      {'label': 'Undo', 'undo': true, 'rule': rule},
    ],
  });
}

/// A week of a typical inbox up to [now]: HDFC and ICICI payments in three
/// bank formats, an Amazon Pay echo, an own-account transfer, an IMPS SMS
/// the parser can't fully read, and an OTP and a personal SMS to skip.
List<Sms> sampleInbox(DateTime now) {
  DateTime d(int ago, int h, int m) => DateTime(now.year, now.month, now.day - ago, h, m);
  String yy(DateTime t) => '${t.year % 100}'.padLeft(2, '0');
  Sms hdfc(DateTime at, String body) => (sender: 'VM-HDFCBK', body: body, at: at);
  Sms icici(DateTime at, String body) => (sender: 'VK-ICICIB', body: body, at: at);
  Sms upi(DateTime at, String rs, String dir, String vpa, String ref) => hdfc(at,
      'Rs.$rs ${dir == 'to' ? 'debited from' : 'credited to'} A/c XX1111 on ${smsDate(at)} $dir VPA $vpa. UPI Ref $ref.');

  final imps = d(2, 18, 12), own = d(1, 11, 0), bb = d(1, 20, 47), uber = d(0, 9, 20);
  return [
    upi(d(6, 16, 40), '1499.00', 'to', 'myntra@icici', '630600000001'),
    upi(d(5, 20, 15), '386.00', 'to', 'swiggy@icici', '630700000002'),
    upi(d(3, 13, 5), '412.00', 'to', 'swiggy@icici', '630900000003'),
    hdfc(d(3, 18, 30), '123456 is your OTP for txn of Rs.2,500.00 at AMAZON on HDFC Bank card XX1111. Do not share.'),
    hdfc(imps,
        'Your a/c no. XXXXXXXX1111 is debited for Rs.2150.00 on ${smsDate(imps)} '
        'and a/c linked to mobile 9XXXXXX000 credited (IMPS Ref no 631000000004).'),
    (sender: '+919800000001', body: 'Reached home. Call you at 8?', at: d(2, 19, 0)),
    hdfc(own, 'Rs.5000.00 debited from A/c XX1111 on ${smsDate(own)} to A/c XX2222. IMPS Ref 631200000017.'),
    icici(own.add(const Duration(minutes: 1)),
        'Dear Customer, Acct XX2222 is credited with Rs 5000.00 on ${dayMon(own).replaceAll(' ', '-')}-${yy(own)} from A/c XX1111. IMPS Ref 631200000017.'),
    upi(d(1, 15, 18), '1499.00', 'from', 'myntra@icici', '631200000018'),
    upi(d(1, 18, 2), '60.00', 'to', 'q000000113@ybl', '631200000019'),
    upi(d(1, 19, 30), '299.00', 'to', 'zomato@ptybl', '631200000020'),
    (sender: 'AX-AMZPAY', body: 'Paid Rs.299.00 to Zomato using Amazon Pay UPI from HDFC Bank XX1111. Ref 631200000020.', at: d(1, 19, 31)),
    icici(bb,
        'ICICI Bank Acct XX2222 debited for Rs 1326.40 on ${dayMon(bb).replaceAll(' ', '-')}-${yy(bb)}; BIGBASKET credited. UPI:631200000021. Call 18002662 for dispute.'),
    hdfc(uber,
        'Sent Rs.212.00\nFrom HDFC Bank A/C *1111\nTo UBER INDIA\nOn ${smsDate(uber).replaceAll('-', '/')}\nRef 631200000006\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808'),
    upi(d(0, 10, 5), '1200.00', 'from', 'asha.k@okhdfcbank', '631200000007'),
    upi(d(0, 12, 10), '180.00', 'to', 'chaipoint@axisbank', '631200000009'),
    upi(d(0, 13, 42), '450.00', 'to', 'swiggy@icici', '631200000008'),
  ].where((s) => !s.at.isAfter(now)).toList();
}
