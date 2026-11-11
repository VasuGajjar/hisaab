// The Entry sheet: one sheet for every add, edit and fix. A mode only
// changes what goes in each slot, never their order:
// header · attention · facts · your details · actions.
import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings.dart';

enum EntryMode { capture, edit, manual, gaps, dup, credit, queue }

/// Opens whatever a tap on a transaction row should open.
Future<void> openTxn(BuildContext context, Txn t) async {
  final mode = switch (t.status) {
    TxnStatus.needs => EntryMode.capture,
    TxnStatus.filed => EntryMode.edit,
    TxnStatus.dup => EntryMode.dup,
    TxnStatus.credit => EntryMode.credit,
    TxnStatus.unread => EntryMode.gaps,
    TxnStatus.ignored => null,
  };
  if (mode != null) await openSheet(context, EntrySheet(mode, t: t));
}

/// "Add a spend": cash or another account, typed on a keypad.
Future<void> addSpend(BuildContext context) => openSheet(context, const EntrySheet(EntryMode.manual));

/// "Finish up": everything waiting, one at a time.
Future<void> openQueue(BuildContext context) => openSheet(context, const EntrySheet(EntryMode.queue));

/// All categories in a sheet; pops with the picked one. For a payee rule,
/// which is one category.
Future<Cat?> pickCategory(BuildContext context, {Cat? selected}) => showHSheet<Cat>(
  context,
  (c) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Builder(
        builder: (c) {
          c.store; // rebuild after "New" adds a category
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              const Text('Category', style: T.tl),
              CategoryGrid(
                selected: {?selected},
                onPick: (cat) => Navigator.pop(c, cat),
                onNew: () => editCategory(c, null),
              ),
            ],
          );
        },
      ),
    ),
  ),
);

/// "Food & dining", or "Food + Groceries" for several.
String catNames(Iterable<Cat> cs) => cs.length == 1 ? cs.single.full : cs.map((c) => c.short).join(' + ');

/// "Swiggy filed as Food & dining", plus the payee's other pending payments
/// that remembering filed with it.
String filedMsg(String name, Iterable<Cat> cs, int more) =>
    '$name filed as ${catNames(cs)}${more == 0 ? '' : ', with $more more from them'}';

/// Asks for one new tag.
Future<String?> askTag(BuildContext context) async {
  final v = (await askText(context, 'New tag', [('Tag', 'e.g. office')]))?.first.toLowerCase() ?? '';
  return v.isEmpty ? null : v;
}

enum _Outcome { filed, merged, keptBoth, filled, deleted, notExpense, skipped }

typedef _Done = void Function(String msg, _Outcome o, VoidCallback undo);

class EntrySheet extends StatefulWidget {
  const EntrySheet(this.mode, {super.key, this.t});
  final EntryMode mode;

  /// The payment; null for a new spend and for the queue.
  final Txn? t;

  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

/// Single modes pop with a message. The queue walks the pending items as
/// they were on opening; each one leaves with Undo.
class _EntrySheetState extends State<EntrySheet> {
  List<int>? _ids;
  final _done = <(Txn, _Outcome, VoidCallback)>[];
  String? _snack;

  void _move(Txn q, _Outcome o, String msg, VoidCallback undo) => setState(() {
    _done.add((q, o, undo));
    _snack = msg;
  });

  void _undo() {
    if (_done.isEmpty) return;
    final (_, _, last) = _done.removeLast();
    setState(() {
      last();
      _snack = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode != EntryMode.queue) {
      return _Entry(mode: widget.mode, t: widget.t, done: (msg, _, _) => Navigator.pop(context, msg));
    }
    final s = context.store;
    final pending = [for (final t in s.queue()) t.id];
    final ids = _ids ??= pending;
    final seen = {for (final (t, _, _) in _done) t.id};
    // Filing a payee with remember files their later items too: those count as done.
    final left = [
      for (final id in ids)
        if (!seen.contains(id) && pending.contains(id)) id,
    ];
    final n = ids.length, idx = n - left.length;
    final q = left.isEmpty ? null : s.txn(left.first);
    if (q == null) {
      return _summary(context, n, [
        for (final id in ids)
          if (!seen.contains(id) && !pending.contains(id)) ?s.txn(id),
      ]);
    }
    return _Entry(
      key: ValueKey(q.id),
      mode: switch (q.status) {
        TxnStatus.dup => EntryMode.dup,
        TxnStatus.unread => EntryMode.gaps,
        _ => EntryMode.capture,
      },
      t: q,
      queue: (
        pos: idx + 1,
        n: n,
        skip: () => _move(q, _Outcome.skipped, '${q.name} skipped · kept for later', () {}),
        snack: _snack,
        undo: _undo,
      ),
      done: (msg, o, undo) => _move(q, o, msg, undo),
    );
  }

  /// [auto]: items filed along with an earlier one from the same payee.
  Widget _summary(BuildContext context, int n, List<Txn> auto) {
    final s = context.store, at = s.reminderAt;
    List<Txn> by(_Outcome o) => [
      for (final (t, x, _) in _done)
        if (x == o) t,
    ];
    final filed = [...by(_Outcome.filed), ...auto], merged = by(_Outcome.merged), filled = by(_Outcome.filled);
    final ignored = by(_Outcome.notExpense), skipped = by(_Outcome.skipped), kept = by(_Outcome.keptBoth);
    final deleted = by(_Outcome.deleted);
    String names(List<Txn> ts) => ts.map((t) => t.name).join(', ');
    final rows = <(IconData, String, String)>[
      if (filed.isNotEmpty) (Icons.check_rounded, '${filed.length} filed', names(filed)),
      if (merged.isNotEmpty)
        (
          Icons.call_merge_rounded,
          '${merged.length} duplicate merged',
          '${names(merged)} ${rupees(merged.first.paise, dec: false)} counted once',
        ),
      if (kept.isNotEmpty) (Icons.content_copy_rounded, '${kept.length} kept as separate payments', names(kept)),
      if (filled.isNotEmpty)
        (Icons.edit_outlined, '${filled.length} unreadable SMS filled in', rupees(filled.first.paise, dec: false)),
      if (deleted.isNotEmpty)
        (Icons.delete_outline_rounded, '${deleted.length} SMS deleted', rupees(deleted.first.paise, dec: false)),
      if (ignored.isNotEmpty) (Icons.do_not_disturb_on_outlined, '${ignored.length} not an expense', names(ignored)),
      if (skipped.isNotEmpty) (Icons.skip_next_outlined, '${skipped.length} kept for later', names(skipped)),
    ];
    final sorted = n - skipped.length;
    final days = _done.map((d) => d.$1.when).toList()..sort();
    final span = days.isEmpty || sameDay(days.first, days.last) ? '' : ' from ${dow(days.first)}–${dow(days.last)}';
    return SheetFrame(
      title: 'Finish up',
      closeTooltip: 'Close review',
      progress: 1,
      headerTrailing: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('Done', style: T.l.copyWith(color: context.hc.muted)),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Row(
            spacing: 16,
            children: [
              const Seal(size: 48),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    const Text('All caught up', style: T.tl),
                    Text(
                      n == 0
                          ? 'Nothing was waiting.'
                          : skipped.isEmpty
                          ? '$n of $n sorted. Nothing$span is left without a category.'
                          : '$sorted of $n sorted. The rest wait for the next check-in.',
                      style: T.b.copyWith(color: context.hc.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (rows.isNotEmpty)
            HCard(
              child: Column(
                children: [
                  for (final (i, (icon, title, sub)) in rows.indexed) ...[
                    if (i > 0) const LiDivider(),
                    Li(icon: icon, title: title, sub: sub),
                  ],
                ],
              ),
            ),
          HBanner(
            icon: Icons.payments_outlined,
            title: 'Paid anything in cash today?',
            text: "SMS can't see cash or other-bank spends.",
            actions: [
              ('Nothing today', () => Navigator.pop(context)),
              (
                'Add cash spend',
                () {
                  final nav = Navigator.of(context)..pop();
                  addSpend(nav.overlay!.context);
                },
              ),
            ],
          ),
          if (s.reminderOn)
            Text(
              'Next check-in tomorrow at ${time12(DateTime(2026, 1, 1, at.hour, at.minute))}',
              textAlign: TextAlign.center,
              style: T.lsReg.copyWith(color: context.hc.muted),
            ),
        ],
      ),
      actions: [
        Expanded(
          child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ),
      ],
    );
  }
}

typedef _Queue = ({int pos, int n, VoidCallback skip, String? snack, VoidCallback undo});

enum _Dup { merged, kept }

/// One item in one mode.
class _Entry extends StatefulWidget {
  const _Entry({super.key, required this.mode, this.t, this.queue, required this.done});
  final EntryMode mode;
  final Txn? t;
  final _Queue? queue;
  final _Done done;

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  EntryMode get m => widget.mode;
  Txn? get t => widget.t;
  bool get q => widget.queue != null;

  late final Set<Cat> _sel = switch (m) {
    EntryMode.edit => t!.splits.length > 1 ? {for (final (c, _) in t!.splits) c} : {?t!.cat},
    EntryMode.manual => {catOf('food')!},
    EntryMode.dup => {?catOf(context.store.ruleOf(t!.id))},
    _ => <Cat>{},
  };

  /// The payee: as edited on the receipt, or typed (fill the gaps, cash).
  late String _name = t == null || t!.status == TxnStatus.unread ? '' : t!.name;
  late String _note = t?.note ?? '';
  late final Set<String> _tags = {...?t?.tags};
  late bool _reimb = t?.reimb ?? false;
  bool _remember = true, _learn = true, _grid = false, _noteOpen = false, _out = true, _pad = true;
  _Dup? _dup;

  /// Typed in (added or edited): cash, else from [_account]; null = not listed.
  late bool _cash = t?.source != 'other';
  late int? _account = t?.accountId;
  String _typed = '';
  late TimeOfDay _time = TimeOfDay.fromDateTime(context.store.now());
  late DateTime _day = dayStart(context.store.now());

  /// Dup mode: the first SMS, which stays the source.
  late final Txn? _first = m == EntryMode.dup && t!.dupOf != null ? context.store.txn(t!.dupOf!) : null;

  /// Credit mode: the spend it refunds, linked already or likely.
  late final Txn? _match = m != EntryMode.credit
      ? null
      : t!.refundOf != null
      ? context.store.txn(t!.refundOf!)
      : context.store.refundMatch(t!);
  late String _money = t?.creditKind ?? (_match != null ? 'refund' : 'moneyBack');

  String get _payee => _name.trim().isEmpty ? t!.name : _name.trim();

  /// In the queue a category tap files the item when nothing else is missing.
  bool get _ready => switch (m) {
    EntryMode.capture => true,
    EntryMode.gaps => _out && _name.trim().isNotEmpty,
    EntryMode.dup => _dup != null,
    _ => false,
  };

  void _pick(Cat c) {
    if (q && _ready) return _save({c});
    setState(() => _sel.remove(c) || _sel.add(c));
  }

  /// Undo for [t] and, in dup mode, the first SMS too.
  VoidCallback _undoPoint(Store s) {
    final a = s.undoPoint(t!.id), f = _first, b = f == null ? null : s.undoPoint(f.id);
    return () {
      a();
      b?.call();
    };
  }

  void _rename(Store s) {
    if (_payee != t!.name) s.rename(t!.id, _payee);
  }

  void _save([Set<Cat>? only]) {
    final s = context.store, cats = (only ?? _sel).toList(), note = _note, tags = _tags;
    final t = this.t;
    final undo = t == null ? () {} : _undoPoint(s);
    switch (m) {
      case EntryMode.capture:
        _rename(s);
        final more = s.fileAll(t!.id, cats, remember: _remember, note: note, tags: tags);
        widget.done(filedMsg(_payee, cats, more), _Outcome.filed, undo);
      case EntryMode.edit:
        _rename(s);
        if (t!.manual) s.setPaidWith(t.id, cash: _cash, account: _account);
        final split = {for (final (c, _) in t.splits) c};
        if (split.length > 1 && split.length == cats.length && split.containsAll(cats)) {
          s.saveDetails(t.id, note: note, tags: tags, reimb: _reimb);
        } else {
          s.fileAll(t.id, cats, remember: _remember, note: note, tags: tags, reimb: _reimb);
        }
        widget.done('Changes saved · $_payee', _Outcome.filed, undo);
      case EntryMode.manual:
        final paise = keypadPaise(_typed);
        final id = s.addManual(
          paise: paise,
          cats: cats,
          cash: _cash,
          account: _account,
          note: note,
          payee: _name,
          at: DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute),
        );
        if (tags.isNotEmpty) s.saveDetails(id, tags: tags);
        widget.done(
          '${rupees(paise, dec: paise % 100 != 0)} ${_cash ? 'cash' : 'spend'} added · ${catNames(cats)}',
          _Outcome.filed,
          undo,
        );
      case EntryMode.gaps:
        final name = _name.trim(), amt = rupees(t!.paise, dec: t.paise % 100 != 0);
        final more = s.fillUnread(t.id, out: _out, name: name, cats: _out ? cats : const [], learn: _learn);
        if (note.isNotEmpty || tags.isNotEmpty) s.saveDetails(t.id, note: note, tags: tags);
        final also = more == 0 ? '' : ', with $more more like it';
        widget.done(_out ? '$amt to $name filed as ${catNames(cats)}$also' : '$amt from $name saved$also', _Outcome.filled, undo);
      case EntryMode.dup:
        final f = _first;
        if (_dup == _Dup.merged && f != null) {
          s.mergeDup(t!.id);
          s.fileAll(f.id, cats, note: note, tags: tags);
          widget.done('${f.name} filed · counted once', _Outcome.merged, undo);
        } else {
          s.keepBoth(t!.id);
          if (f != null) s.fileAll(f.id, cats, note: note, tags: tags);
          s.fileAll(t.id, cats, note: note, tags: tags);
          widget.done('Both ${t.name} payments filed', _Outcome.keptBoth, undo);
        }
      case EntryMode.credit:
        final mt = _match;
        final String msg;
        if (_money == 'refund' && mt != null) {
          s.linkRefund(t!.id, mt.id);
          msg = 'Linked · ${mt.cat?.full ?? 'your spend'} is ${rupees(t.paise, dec: false)} lower';
        } else if (_money == 'ignore') {
          s.ignore(t!.id);
          msg = 'Left out of totals';
        } else {
          final income = _money == 'income';
          s.explainCredit(t!.id, income ? 'income' : 'moneyBack');
          msg = income ? 'Saved as income' : 'Saved as money back';
        }
        if (note.isNotEmpty || tags.isNotEmpty) s.saveDetails(t.id, note: note, tags: tags);
        widget.done(msg, _Outcome.filed, undo);
      case EntryMode.queue:
        break;
    }
  }

  void _notExpense() {
    final s = context.store, t = this.t!, f = _first, undo = _undoPoint(s);
    _rename(s);
    if (m == EntryMode.dup) {
      if (_dup == _Dup.kept || f == null) {
        s.keepBoth(t.id);
        s.ignore(t.id);
      } else {
        s.mergeDup(t.id);
      }
      if (f != null) s.ignore(f.id);
    } else {
      s.ignore(t.id);
    }
    widget.done('$_payee marked not an expense', _Outcome.notExpense, undo);
  }

  void _deleteSms() {
    final s = context.store, undo = _undoPoint(s);
    s.deleteTxn(t!.id);
    widget.done('SMS deleted', _Outcome.deleted, undo);
  }

  void _resolve(_Dup r) {
    setState(() => _dup = r);
    if (q && _sel.isNotEmpty) _save();
  }

  Future<void> _addTag() async {
    final tag = await askTag(context);
    if (tag != null) setState(() => _tags.add(tag));
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc, t = this.t, queue = widget.queue;
    final paise = m == EntryMode.manual ? keypadPaise(_typed) : t!.paise;
    final title = q
        ? 'Finish up'
        : switch (m) {
            EntryMode.capture || EntryMode.dup => 'Add details',
            EntryMode.edit => 'Edit payment',
            EntryMode.manual => 'Add a spend',
            EntryMode.gaps => 'Fill in the gaps',
            EntryMode.credit => 'Money in',
            EntryMode.queue => 'Finish up',
          };

    final (String label, bool ok) = switch (m) {
      EntryMode.capture => _sel.isEmpty ? ('Pick a category', false) : ('Save', true),
      EntryMode.edit => _sel.isEmpty ? ('Pick a category', false) : ('Save changes', true),
      EntryMode.manual =>
        paise == 0
            ? ('Enter an amount', false)
            : _sel.isEmpty
            ? ('Pick a category', false)
            : ('Save ${rupees(paise, dec: paise % 100 != 0)} · ${_sel.map((c) => c.short).join(' + ')}', true),
      EntryMode.gaps =>
        _name.trim().isEmpty
            ? ('Add who it was', false)
            : _out && _sel.isEmpty
            ? ('Pick a category', false)
            : ('Save', true),
      EntryMode.dup =>
        _dup == null
            ? ('Merge or keep?', false)
            : _sel.isEmpty
            ? ('Pick a category', false)
            : ('Save', true),
      EntryMode.credit => (
        switch (_money) {
          'refund' => 'Link as refund',
          'income' => 'Save as income',
          'ignore' => 'Leave out',
          _ => 'Save as money back',
        },
        true,
      ),
      EntryMode.queue => ('', false),
    };
    final (String? second, VoidCallback? onSecond) = switch (m) {
      EntryMode.capture || EntryMode.edit || EntryMode.dup => ('Not an expense', _notExpense),
      EntryMode.gaps => ('Delete SMS', _deleteSms),
      _ => (null, null),
    };
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final keypad = m == EntryMode.manual && _pad && !_grid && !keyboard;

    return SheetFrame(
      title: title,
      heightFactor: .95,
      closeTooltip: m == EntryMode.manual || m == EntryMode.edit ? 'Close' : 'Close, keep for later',
      progress: queue == null ? null : (queue.pos - 1) / queue.n,
      headerTrailing: [
        if (queue != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('${queue.pos} of ${queue.n}', style: T.l.merge(T.num).copyWith(color: hc.muted)),
          ),
          TextButton.icon(
            onPressed: queue.skip,
            icon: const Icon(Icons.skip_next_outlined),
            label: const Text('Skip'),
            style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
          ),
        ],
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ?_attention(context),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: _facts(context)),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: _details(context, paise)),
        ],
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // In the sheet: a snackbar would sit under it.
          if (queue?.snack case final msg?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SnackPill(msg, onUndo: queue!.undo),
            ),
          if (keypad)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Keypad(onKey: (k) => setState(() => _typed = keypadInput(_typed, k))),
            ),
        ],
      ),
      actions: [
        if (second != null) OutlinedButton(onPressed: onSecond, child: Text(second)),
        Expanded(
          child: FilledButton(
            onPressed: ok ? _save : null,
            child: Text(q && ok ? 'Save & next' : label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }

  // Slot 2: attention.
  Widget? _attention(BuildContext context) {
    final t = this.t;
    switch (m) {
      case EntryMode.gaps:
        return const HBanner(
          tone: BannerTone.err,
          icon: Icons.warning_amber_rounded,
          title: 'Payee and direction not found',
        );
      case EntryMode.credit when _match != null:
        final mt = _match;
        return HBanner(
          tone: BannerTone.ok,
          icon: Icons.undo_rounded,
          title: 'Looks like a refund',
          text: 'Same payee and amount as your ${mt.name} spend on ${dowDayMon(mt.when)}.',
        );
      case EntryMode.dup:
        final undo = [('Undo', () => setState(() => _dup = null))];
        if (_dup == _Dup.merged) {
          return HBanner(tone: BannerTone.ok, icon: Icons.check_rounded, title: 'Merged · counted once', actions: undo);
        }
        if (_dup == _Dup.kept) {
          return HBanner(tone: BannerTone.info, icon: Icons.check_rounded, title: 'Kept both payments', actions: undo);
        }
        final f = _first;
        final mins = f == null ? 0 : t!.when.difference(f.when).inMinutes.abs();
        final sameRef = f != null && f.ref.isNotEmpty && f.ref == t!.ref;
        return HBanner(
          tone: BannerTone.warn,
          icon: Icons.content_copy_rounded,
          title: 'Same payment, reported twice?',
          text:
              '${t!.sender} sent the same amount${sameRef ? ' and UPI Ref' : ''} '
              '${mins == 0 ? 'in the same minute' : '$mins minute${mins == 1 ? '' : 's'} later'}.',
          actions: [('Keep both', () => _resolve(_Dup.kept)), ('Merge into one', () => _resolve(_Dup.merged))],
        );
      default:
        return null;
    }
  }

  /// Typed in: cash, or which account (a UPI payment the bank sent no SMS for).
  List<Widget> _paidWith(BuildContext context) => [
    Seg<bool>(
      label: 'Paid with',
      value: _cash,
      options: const [
        (true, 'Cash', Icons.payments_outlined),
        (false, 'Bank account', Icons.account_balance_outlined),
      ],
      onChanged: (v) => setState(() => _cash = v),
    ),
    if (!_cash)
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (id, label) in <(int?, String)>[
            for (final a in context.store.allAccounts) (a.id, a.label),
            (null, 'Not listed'),
          ])
            HChip(
              label,
              kind: _account == id ? ChipKind.tagSel : ChipKind.tag,
              onTap: () => setState(() => _account = id),
            ),
        ],
      ),
  ];

  // Slot 3: facts. Paper for what the SMS said, ink for what you type.
  List<Widget> _facts(BuildContext context) {
    final cs = context.cs, hc = context.hc, t = this.t;
    if (m == EntryMode.manual) {
      final dot = _typed.indexOf('.');
      final paise = keypadPaise(_typed);
      final ink = _typed.isEmpty ? hc.muted : cs.primary;
      return [
        Row(
          children: [
            const Expanded(child: InkHeading('Added by you')),
            FChip(
              // "Today", "Yesterday" or "Fri 06 Nov", then the time.
              '${dayLabel(_day, context.store.now()).split(' · ').first} · '
              '${time12(DateTime(2026, 1, 1, _time.hour, _time.minute))}',
              leading: Icons.calendar_today_outlined,
              onTap: () async {
                final now = context.store.now();
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: now,
                  initialDate: _day,
                  helpText: 'When did you pay?',
                );
                if (d == null || !context.mounted) return;
                setState(() => _day = d);
                final v = await showTimePicker(context: context, initialTime: _time);
                if (v != null && context.mounted) setState(() => _time = v);
              },
            ),
          ],
        ),
        Semantics(
          button: true,
          label: 'Amount ${rupees(paise)}',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() {
              _pad = true;
              _grid = false;
            }),
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 2,
                children: [
                  Text.rich(
                    TextSpan(
                      style: T.num.copyWith(
                        fontSize: 40,
                        height: 48 / 40,
                        letterSpacing: -.6,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                      children: [
                        const TextSpan(
                          text: '₹',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
                        ),
                        TextSpan(text: groupIN(dot < 0 ? paise ~/ 100 : int.parse(_typed.substring(0, dot)))),
                        TextSpan(
                          text: dot < 0 ? '' : _typed.substring(dot),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  if (_pad && !_grid)
                    Container(
                      width: 2,
                      height: 40,
                      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(1)),
                    ),
                ],
              ),
            ),
          ),
        ),
        ..._paidWith(context),
        InkField(
          icon: Icons.person_outline_rounded,
          label: 'Paid to',
          hint: 'Optional · e.g. vada pav stall',
          onChanged: (v) => _name = v,
        ),
      ];
    }
    if (t!.manual) {
      // Editing a spend you typed in: all ink.
      return [
        Row(
          children: [
            const Expanded(child: InkHeading('Added by you')),
            Text('${dowDayMon(t.when)} · ${time12(t.when)}', style: T.ls.copyWith(color: hc.muted)),
          ],
        ),
        Center(
          child: AmountText(t.paise, size: AmtSize.xl, color: cs.primary),
        ),
        ..._paidWith(context),
        InkField(
          icon: Icons.person_outline_rounded,
          label: 'Paid to',
          initial: t.name,
          onChanged: (v) => setState(() => _name = v),
        ),
      ];
    }
    final rename = m == EntryMode.capture || m == EntryMode.edit;
    return [
      TxnReceipt(
        _first ?? t,
        name: rename ? _name : null,
        onRename: rename ? (v) => setState(() => _name = v) : null,
        rawOpen: m == EntryMode.gaps || m == EntryMode.edit,
      ),
      if (m == EntryMode.dup)
        Receipt(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            spacing: 10,
            children: [
              const Icon(Icons.sms_outlined, size: 18),
              Expanded(
                child: Text(
                  '${t.sender} · ${time12(t.when)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.monoS.copyWith(color: hc.onPaper),
                ),
              ),
              switch (_dup) {
                null => const HBadge('2nd SMS', icon: Icons.content_copy_rounded, tone: Tone.dup),
                _Dup.merged => const HBadge('Duplicate', icon: Icons.content_copy_rounded, tone: Tone.ignored),
                _Dup.kept => const HBadge('Kept', icon: Icons.check_rounded),
              },
            ],
          ),
        ),
      if (m == EntryMode.gaps) ...[
        Seg<bool>(
          label: 'Direction',
          value: _out,
          options: const [(true, 'Paid out', Icons.north_east_rounded), (false, 'Received', Icons.south_west_rounded)],
          onChanged: (v) => setState(() => _out = v),
        ),
        InkField(
          icon: Icons.person_outline_rounded,
          label: _out ? 'Paid to' : 'Received from',
          hint: 'Name',
          initial: _name,
          onChanged: (v) => setState(() => _name = v),
        ),
      ],
    ];
  }

  // Slot 4: what it means to you.
  List<Widget> _details(BuildContext context, int paise) {
    final cs = context.cs, hc = context.hc, s = context.store, t = this.t;
    final hint = q
        ? (_ready ? 'tap to file & next' : '')
        : switch (m) {
            EntryMode.capture => _sel.isEmpty ? 'pick one or more' : 'now tap Save',
            EntryMode.credit => 'pick one',
            _ => '',
          };
    final noPicker = m == EntryMode.credit || (m == EntryMode.gaps && !_out);
    final showGrid = !noPicker && (m == EntryMode.capture || _grid);
    final showChips = !noPicker && m != EntryMode.edit && !(_grid && m != EntryMode.capture);
    final showField = m == EntryMode.edit && !_grid;

    final sugg = <Cat, String>{
      for (final g in switch (m) {
        EntryMode.manual => [
          for (final k in const ['food', 'trans', 'groc']) Sugg(catOf(k)!, ''),
        ],
        EntryMode.dup => (_first ?? t!).sugg,
        EntryMode.gaps when t!.sugg.isEmpty => [Sugg(catOf('home')!, ''), Sugg(catOf('other')!, '')],
        _ => t?.sugg ?? const <Sugg>[],
      })
        g.cat: g.why,
    };
    for (final c in _sel) {
      sugg.putIfAbsent(c, () => '');
    }

    final noteShown = m == EntryMode.edit || _noteOpen || _note.isNotEmpty;
    final tagsShown = m == EntryMode.edit || _tags.isNotEmpty || s.tagsInUse.isNotEmpty;
    final remember =
        (m == EntryMode.capture && t!.newPayee || m == EntryMode.edit) && t!.merchantId != null && _sel.length <= 1;
    final bank = t?.acct.split(' ').first ?? '';

    return [
      InkHeading('Your details', trailing: hint.isEmpty ? null : hint),
      if (m == EntryMode.credit) _moneyChoices(context),
      if (showChips)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final MapEntry(key: c, value: why) in sugg.entries)
              HChip(
                c.short,
                cat: c,
                why: why,
                kind: _sel.contains(c) ? ChipKind.sel : ChipKind.sugg,
                onTap: () => _pick(c),
              ),
            if (!showGrid) HChip('More', onTap: () => setState(() => _grid = true)),
          ],
        ),
      if (showGrid)
        CategoryGrid(
          selected: _sel,
          suggested: m == EntryMode.capture && t!.sugg.isNotEmpty ? t.sugg.first.cat : null,
          onPick: _pick,
          onNew: () => editCategory(context, null),
        ),
      if (showField)
        Glass(
          radius: 18,
          shadow: false,
          edge: cs.primary,
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            spacing: 12,
            children: [
              if (_sel.isNotEmpty)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: _sel.first.of(context).cc, shape: BoxShape.circle),
                  child: Icon(_sel.first.icon, size: 20, color: _sel.first.of(context).con),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sel.length > 1 ? 'Categories' : 'Category',
                      style: TextStyle(fontSize: 12, height: 16 / 12, color: hc.muted),
                    ),
                    Text(
                      _sel.isEmpty ? 'None yet' : catNames(_sel),
                      style: TextStyle(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w500, color: cs.primary),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _grid = true),
                style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
                child: const Text('Change'),
              ),
            ],
          ),
        ),
      if (_sel.length > 1 && paise > 0)
        Text('${rupees(paise)} counts in full under each.', style: T.b.copyWith(color: hc.muted)),
      if (noteShown)
        InkField(
          icon: Icons.notes_rounded,
          label: 'Note',
          hint: 'What was it for?',
          initial: _note,
          autofocus: _noteOpen,
          onChanged: (v) => _note = v,
        ),
      if (tagsShown) _tagsRow(context, s),
      if (!noteShown || !tagsShown)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!noteShown)
              HChip(
                'Note',
                kind: ChipKind.add,
                icon: Icons.notes_rounded,
                onTap: () => setState(() => _noteOpen = true),
              ),
            if (!tagsShown) HChip('Tag', kind: ChipKind.add, icon: Icons.tag_rounded, onTap: _addTag),
            Text(q ? 'add before you tap' : 'optional', style: T.lsReg.copyWith(color: hc.muted)),
          ],
        ),
      if (remember)
        SwitchRow(
          icon: Icons.push_pin_outlined,
          title: 'Remember for $_payee',
          sub: _sel.isEmpty
              ? 'Your pick becomes the 1-tap action'
              : (_remember ? 'Next time ${_sel.single.full} is 1 tap' : 'Ask again next time'),
          value: _remember,
          onChanged: (v) => setState(() => _remember = v),
        ),
      if (m == EntryMode.edit)
        SwitchRow(
          icon: Icons.undo_rounded,
          iconColor: cs.onSurfaceVariant,
          title: 'Reimbursable',
          sub: _reimb ? 'Kept out of spend until paid back' : 'Keep out of my spend until paid back',
          value: _reimb,
          onChanged: (v) => setState(() => _reimb = v),
        ),
      if (m == EntryMode.gaps)
        SwitchRow(
          icon: Icons.auto_awesome_outlined,
          title: 'Learn this message format',
          sub: _learn ? 'Read${bank.isEmpty ? '' : ' $bank'} SMS like this by itself' : 'Ask me again next time',
          value: _learn,
          onChanged: (v) => setState(() => _learn = v),
        ),
    ];
  }

  /// Tags already picked or used before, plus "Tag" to add a new one.
  Widget _tagsRow(BuildContext context, Store s) {
    final options = {..._tags, ...s.tagsInUse}.take(6);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        spacing: 8,
        children: [
          Icon(Icons.tag_rounded, size: 20, color: context.cs.primary),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in options)
                  HChip(
                    tag,
                    kind: _tags.contains(tag) ? ChipKind.tagSel : ChipKind.tag,
                    onTap: () => setState(() => _tags.remove(tag) || _tags.add(tag)),
                  ),
                HChip('Tag', kind: ChipKind.add, icon: Icons.add_rounded, onTap: _addTag),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Money in: what is this money?
  Widget _moneyChoices(BuildContext context) {
    final t = this.t!, mt = _match;
    final options = [
      if (mt != null)
        (
          'refund',
          'Refund of ${mt.name} · ${dayMon(mt.when)}',
          'Nets ${rupees(t.paise, dec: false)} out of ${mt.cat?.full ?? 'your spend'}',
          Icons.undo_rounded,
          mt.cat,
        ),
      ('moneyBack', 'Money back from someone', 'A split or repayment, not income', Icons.person_outline_rounded, null),
      ('income', 'Income', 'Salary, interest, cashback', Icons.payments_outlined, null),
      ('ignore', 'Not related', 'Leave it out of totals', Icons.do_not_disturb_on_outlined, null),
    ];
    return Column(
      spacing: 6,
      children: [
        for (final (k, l1, l2, icon, cat) in options)
          _Choice(on: _money == k, l1: l1, l2: l2, icon: icon, cat: cat, onTap: () => setState(() => _money = k)),
      ],
    );
  }
}

/// One radio choice on glass.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.on,
    required this.l1,
    required this.l2,
    required this.icon,
    this.cat,
    required this.onTap,
  });
  final bool on;
  final String l1, l2;
  final IconData icon;
  final Cat? cat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, hc = context.hc, g = context.glass, cc = cat?.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      child: Glass(
        radius: 16,
        shadow: false,
        color: on ? cs.primaryContainer.withValues(alpha: g.on ? .72 : 1) : null,
        edge: on ? cs.primary : null,
        edgeWidth: on ? 1.5 : 1,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
              child: Row(
                spacing: 12,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: cc?.cc ?? cs.surfaceContainerHigh, shape: BoxShape.circle),
                    child: Icon(icon, size: 18, color: cc?.con ?? cs.onSurfaceVariant),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l1,
                          style: T.b.copyWith(fontWeight: FontWeight.w600, color: on ? cs.onPrimaryContainer : null),
                        ),
                        Text(l2, style: T.lsReg.copyWith(color: hc.muted)),
                      ],
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: on ? cs.primary : cs.outline, width: 2),
                    ),
                    child: on
                        ? DecoratedBox(
                            decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
