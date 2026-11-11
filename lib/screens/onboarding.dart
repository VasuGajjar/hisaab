import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../capture.dart';
import 'home.dart';
import '../sms.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings.dart';

/// Five steps: value → SMS rationale → notifications → reminder time → banks.
/// ponytail: the notifications step only advances; POST_NOTIFICATIONS comes
/// with the capture notification.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  TimeOfDay _time = const TimeOfDay(hour: 21, minute: 30);
  bool _fromToday = true, _notify = false;
  List<Sms> _inbox = const [];
  List<Found> _found = const [];

  /// Keys of found accounts switched off.
  final _off = <String>{};

  void _next() => setState(() => _step++);

  /// Denied: finish now, with SMS off; Home then offers "Turn on".
  Future<void> _allowSms() async {
    final now = context.store.now();
    if (!await requestSmsPermission()) {
      if (mounted) _finish(sms: false);
      return;
    }
    final inbox = await readInbox(now.subtract(const Duration(days: 90)), now: now);
    if (!mounted) return;
    setState(() {
      _inbox = inbox;
      _found = scanInbox(inbox);
      _step++;
    });
  }

  void _finish({required bool sms}) {
    final s = context.store, now = s.now();
    s.finishOnboarding(
      sms: sms,
      since: sms && !_fromToday ? monthStart(now) : now,
      found: _found,
      off: _off,
      inbox: _inbox,
    );
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  String get _timeLabel => time12(DateTime(2026, 1, 1, _time.hour, _time.minute));

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time, initialEntryMode: TimePickerEntryMode.input);
    if (t != null) setState(() => _time = t);
  }

  @override
  Widget build(BuildContext context) {
    final (body, bottom) = switch (_step) {
      0 => _value(context),
      1 => _sms(context),
      2 => _notif(context),
      3 => _reminder(context),
      _ => _accounts(context),
    };
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        body: Ambient(
          child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, right: 8),
                  child: Row(children: [
                    Steps(_step),
                    const Spacer(),
                    if (_step == 2) TextButton(onPressed: _next, child: const Text('Skip')),
                  ]),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: SingleChildScrollView(
                    key: ValueKey(_step),
                    padding: EdgeInsets.fromLTRB(_step == 4 ? 16 : 24, 8, _step == 4 ? 16 : 24, 16),
                    child: body,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: bottom),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String title, String body, {bool large = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Semantics(header: true, child: Text(title, style: T.hl)),
          Text(body, style: (large ? T.bl : T.b).copyWith(color: context.cs.onSurfaceVariant)),
        ],
      );

  Widget _bullet(BuildContext context, IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: context.cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20),
          ),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(text, style: T.b))),
        ],
      );

  (Widget, List<Widget>) _value(BuildContext context) {
    final cs = context.cs, hc = context.hc;
    return (
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Column(
                  spacing: 12,
                  children: [
                    Transform.rotate(
                      angle: -2 * math.pi / 180,
                      child: SizedBox(
                        width: 248,
                        child: Receipt(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ReceiptHead(
                                'SMS · VM-HDFCBK',
                                trailing: Text('DEBIT',
                                    style: T.monoS.copyWith(letterSpacing: .8, fontWeight: FontWeight.w500, color: hc.paperMuted)),
                              ),
                              const Text('−₹450.00', style: TextStyle(fontSize: 26, height: 32 / 26, fontWeight: FontWeight.w500)),
                              Text('to swiggy@icici · 1:42 pm', style: T.monoS.copyWith(color: hc.paperMuted)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_downward_rounded, size: 20),
                    ),
                    Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                      const HChip('Food & dining', cat: food, kind: ChipKind.sel),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(6)),
                        child: Text('1 tap', style: T.monoS.copyWith(color: cs.onPrimaryContainer)),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
          _heading(context, 'Every UPI payment, filed in one tap.',
              "Hisaab reads your bank's payment SMS on this phone and asks one question: what was it for?",
              large: true),
          Column(spacing: 16, children: [
            _bullet(context, Icons.sms_outlined, 'Captured from bank SMS — nothing to type'),
            _bullet(context, Icons.notifications_none_rounded, 'Payees you know: file from the notification'),
            _bullet(context, Icons.shield_outlined, 'No account, no server. Nothing leaves your phone.'),
          ]),
        ],
      ),
      [
        FilledButton(onPressed: _next, child: const Text('Get started')),
        TextButton(onPressed: () => importBackup(context), child: const Text('Import a backup')),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Android only · works offline', textAlign: TextAlign.center, style: T.lsReg.copyWith(color: hc.muted)),
        ),
      ],
    );
  }

  (Widget, List<Widget>) _sms(BuildContext context) => (
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 20,
          children: [
            _heading(context, 'Read bank SMS — on this phone only',
                "This is how payments get captured without you typing anything. Here's exactly what we take from a message:"),
            Receipt(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ReceiptHead('VM-HDFCBK · example'),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: RawSms(
                        'Rs.[450.00] debited from A/c [XX1111] on [07-11-26] to VPA [swiggy@icici]. UPI Ref [631200000005].'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final f in const ['₹450.00', 'debit', 'a/c ••1111', 'swiggy@icici', '07 Nov', 'Ref ••0005'])
                        HBadge(f, tone: Tone.sms),
                    ]),
                  ),
                ],
              ),
            ),
            Column(spacing: 16, children: [
              _bullet(context, Icons.account_balance_outlined, 'Only SMS that name a bank and an amount are kept'),
              _bullet(context, Icons.lock_outline_rounded, 'OTPs and personal messages are skipped and never stored'),
              _bullet(context, Icons.cloud_off_outlined, 'The app has no internet permission, so nothing can be uploaded'),
            ]),
          ],
        ),
        [
          FilledButton(onPressed: _allowSms, child: const Text('Allow SMS access')),
          TextButton(
            onPressed: () => _finish(sms: false),
            child: const Text("Not now — I'll add spends by hand"),
          ),
        ],
      );

  (Widget, List<Widget>) _notif(BuildContext context) {
    // System notification shade: Android's colours, not the app theme.
    const shade = Color(0xFFDEDCE4), card = Color(0xFFFAF9FD), ink = Color(0xFF1B1B1F), sub = Color(0xFF45464F);
    const accent = Color(0xFF2F3FA0);
    return (
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          _heading(context, 'Get a nudge right after you pay',
              "For payees you know, tap the category right in the notification. New ones open a short sheet over whatever app you're in — no need to open Hisaab."),
          Semantics(
            label: 'Example notification: ₹450.00 paid to Swiggy. Actions: Food & dining, Groceries, Add details.',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(20)),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: const Icon(Icons.receipt_long_outlined, size: 20, color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          const Text.rich(
                            TextSpan(children: [
                              TextSpan(text: 'Hisaab', style: TextStyle(color: ink, fontWeight: FontWeight.w500)),
                              TextSpan(text: ' • HDFC ••1111 • now'),
                            ]),
                            style: TextStyle(fontSize: 12, height: 16 / 12, color: sub),
                          ),
                          const Text('₹450.00 paid to Swiggy',
                              style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: ink)),
                          const Text('Food & dining the last 6 times.', style: TextStyle(fontSize: 14, height: 20 / 14, color: sub)),
                          Transform.translate(
                            offset: const Offset(-12, 0),
                            child: Wrap(children: [
                              for (final a in const ['Food & dining', 'Groceries', 'Add details'])
                                Container(
                                  height: 40,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(a,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accent)),
                                ),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _bullet(context, Icons.schedule_rounded, 'Skipping is fine: everything still waits for your daily check-in.'),
        ],
      ),
      [
        FilledButton(
          onPressed: () async {
            _notify = await requestNotificationPermission();
            _next();
          },
          child: const Text('Allow notifications'),
        ),
      ],
    );
  }

  (Widget, List<Widget>) _reminder(BuildContext context) {
    final cs = context.cs, hc = context.hc;
    const presets = [TimeOfDay(hour: 20, minute: 30), TimeOfDay(hour: 21, minute: 30), TimeOfDay(hour: 22, minute: 30)];
    final custom = !presets.contains(_time);
    Widget seg(String v, String label, {bool on = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 96,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? cs.primaryContainer : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: on ? Border.all(color: cs.primary, width: 2) : null,
              ),
              child: Text(v,
                  style: T.num.copyWith(fontSize: 44, height: 52 / 44, color: on ? cs.onPrimaryContainer : cs.onSurface)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(label, style: TextStyle(fontSize: 12, height: 16 / 12, color: hc.muted)),
            ),
          ],
        );
    Widget half(String label, bool on) => Expanded(
          child: Container(
            alignment: Alignment.center,
            color: on ? hc.amberC : null,
            child: Text(label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? hc.onAmberC : cs.onSurfaceVariant)),
          ),
        );
    final pm = _time.period == DayPeriod.pm;
    return (
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          _heading(context, 'When should we check in each day?',
              'One reminder a day to finish anything pending and add the cash or other-account spends SMS can’t see.'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              const Eyebrow('Pick a time'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in presets)
                  HChip(time12(DateTime(2026, 1, 1, p.hour, p.minute)),
                      kind: p == _time ? ChipKind.tagSel : ChipKind.plain, onTap: () => setState(() => _time = p)),
                HChip(custom ? 'Custom · $_timeLabel' : 'Custom',
                    kind: custom ? ChipKind.tagSel : ChipKind.plain, onTap: _pickTime),
              ]),
            ],
          ),
          Semantics(
            button: true,
            label: 'Reminder time $_timeLabel. Tap to change.',
            excludeSemantics: true,
            child: Material(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _pickTime,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      seg(_time.hourOfPeriod.toString().padLeft(2, '0'), 'Hour', on: true),
                      const SizedBox(
                        width: 16,
                        height: 72,
                        child: Center(child: Text(':', style: TextStyle(fontSize: 44))),
                      ),
                      seg(_time.minute.toString().padLeft(2, '0'), 'Minute'),
                      Container(
                        width: 56,
                        height: 72,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outline),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(children: [half('AM', !pm), Divider(height: 1, color: cs.outline), half('PM', pm)]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(spacing: 12, children: [
            const Icon(Icons.info_outline_rounded),
            Expanded(
              child: Text('Pick a time after your last payment of the day, so one check-in covers everything.',
                  style: T.b.copyWith(color: cs.onSurfaceVariant)),
            ),
          ]),
        ],
      ),
      [
        FilledButton(
          onPressed: () {
            // Without notification access the check-in can't show; Settings turns it on later.
            context.store
              ..reminderAt = _time
              ..reminderOn = _notify;
            _next();
          },
          child: Text('Remind me at $_timeLabel'),
        ),
      ],
    );
  }

  (Widget, List<Widget>) _accounts(BuildContext context) {
    final hc = context.hc, now = context.store.now();
    final banks = _found.where((f) => !f.bank.dupOnly).length;
    final importable = paymentsSince(_inbox, monthStart(now));
    Widget sw(Found f, String label) => Semantics(
          label: label,
          child: HSwitch(
            value: !_off.contains(f.bank.name),
            onChanged: (v) => setState(() => v ? _off.remove(f.bank.name) : _off.add(f.bank.name)),
          ),
        );
    String sub(Found f) => [for (final l in f.accounts) '••$l', '${f.count} SMS'].join(' · ');
    return (
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: banks == 0
                ? _heading(context, 'No bank SMS found yet',
                    'Payments are picked up from the next SMS that names a bank.')
                : _heading(context, 'We found $banks bank${banks == 1 ? '' : 's'}',
                    "From payment SMS in the last 90 days. Switch off any you don't want tracked."),
          ),
          HCard(
            child: Column(children: [
              for (final f in _found) ...[
                f.bank.dupOnly
                    ? Li(
                        icon: Icons.content_copy_rounded,
                        title: '${f.bank.name} UPI',
                        sub: sub(f),
                        subMono: true,
                        note: 'Only used to spot duplicates',
                        trailing: sw(f, 'Use ${f.bank.name} SMS for duplicates'),
                      )
                    : Li(
                        icon: Icons.account_balance_outlined,
                        title: '${f.bank.name} Bank',
                        sub: sub(f),
                        subMono: true,
                        trailing: sw(f, 'Track ${f.bank.name} Bank'),
                      ),
                const LiDivider(),
              ],
              Li(
                icon: Icons.add_rounded,
                title: 'Add a bank',
                titleStyle: TextStyle(fontWeight: FontWeight.w600, color: context.cs.primary),
                onTap: () => addBank(context),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                const Eyebrow('Start tracking from'),
                Seg<bool>(
                  label: 'Start tracking from',
                  value: _fromToday,
                  options: [(true, 'Today', null), (false, '1 ${monthShort(now)} · $importable payments', null)],
                  onChanged: (v) => setState(() => _fromToday = v),
                ),
                Text(
                  'Today keeps your queue empty. Importing ${monthName(now)} adds $importable payments to categorise.',
                  style: T.lsReg.copyWith(color: hc.muted),
                ),
              ],
            ),
          ),
        ],
      ),
      [
        FilledButton(
          onPressed: () => _finish(sms: true),
          child: const Text('Finish setup'),
        ),
      ],
    );
  }
}
