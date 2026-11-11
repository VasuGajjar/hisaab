// Home: the app's one top-level screen. What needs you, the filters, a spend
// summary of what they pick, and the payments themselves.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../capture.dart';
import '../data.dart';
import '../format.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'entry.dart';
import 'settings.dart';

String _amt(int p) => rupees(p, dec: p % 100 != 0);
String _plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
String _pct(int p, int of) => of == 0 ? '' : '${(p * 100 / of).round()}%';

/// Payee shares under one category fade by rank.
const _fade = [1.0, .7, .48, .32, .22];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _searching = false;
  String _q = '';
  String _period = 'This month';
  DateTimeRange? _range; // set = a custom range, overriding _period
  Cat? _cat;
  TxnStatus? _status;
  String? _acct;
  String? _tag;

  static const _statuses = {
    TxnStatus.needs: 'Needs details',
    TxnStatus.filed: 'Filed',
    TxnStatus.credit: 'Credit',
    TxnStatus.dup: 'Duplicate?',
    TxnStatus.unread: "Couldn't read",
    TxnStatus.ignored: 'Not an expense',
  };

  static const _custom = 'Custom range…';

  /// Preset periods as [from, to). "Last 3 months" = this month and the two before it.
  static Map<String, (DateTime, DateTime)> _presets(DateTime now) {
    final y = now.year, m = now.month;
    return {
      'This month': (DateTime(y, m), DateTime(y, m + 1)),
      'Last month': (DateTime(y, m - 1), DateTime(y, m)),
      'Last 3 months': (DateTime(y, m - 2), DateTime(y, m + 1)),
      'Last 6 months': (DateTime(y, m - 5), DateTime(y, m + 1)),
      'This year': (DateTime(y), DateTime(y + 1)),
      'Last year': (DateTime(y - 1), DateTime(y)),
    };
  }

  /// A preset, or the date range picker opened on the period showing now.
  Future<void> _pickPeriod(String v, DateTime from, DateTime to, DateTime now) async {
    if (v != _custom) {
      setState(() {
        _period = v;
        _range = null;
      });
      return;
    }
    final last = DateTime(to.year, to.month, to.day - 1);
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: DateTimeRange(start: from, end: last.isAfter(now) ? now : last),
    );
    if (r != null) setState(() => _range = r);
  }

  bool get _filtered => _cat != null || _status != null || _acct != null || _tag != null;

  /// Status, account and tag pick the rows the summary sums; category then keeps
  /// payments in that category (and refunds of them). Search only narrows the list.
  bool _picked(Txn t) =>
      (_status == null || t.status == _status) &&
      (_acct == null || t.acct == _acct) &&
      (_tag == null || t.tags.contains(_tag));
  bool _inCat(Txn t) => _cat == null || t.cat == _cat || t.splits.any((s) => s.$1 == _cat);

  bool _match(Txn t) {
    final q = _q.trim().toLowerCase();
    return q.isEmpty ||
        [
          t.name,
          t.vpa,
          t.ref,
          t.note,
          t.cat?.full ?? '',
          ...t.tags,
          for (final (c, _) in t.splits) c.full,
        ].any((s) => s.toLowerCase().contains(q));
  }

  /// A chip that opens a menu of [options]; the current [value] is ticked.
  Widget _menu<V>(String label, V value, List<(V, String)> options, ValueChanged<V> pick, {bool? on}) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: MenuAnchor(
      menuChildren: [
        GlassMenu(
          children: [
            for (final (v, l) in options)
              Semantics(
                selected: v == value,
                child: MenuItemButton(
                  leadingIcon: Icon(Icons.check_rounded, color: v == value ? null : Colors.transparent),
                  onPressed: () => pick(v),
                  child: Text(l),
                ),
              ),
          ],
        ),
      ],
      builder: (_, menu, _) =>
          FChip(label, on: on ?? value != null, onTap: () => menu.isOpen ? menu.close() : menu.open()),
    ),
  );

  Future<void> _turnOn() async {
    final s = context.store;
    if (await requestSmsPermission()) {
      s.turnOnSms(await readInbox(s.inboxFrom, now: s.now()));
    } else if (mounted) {
      toast(context, 'Allow SMS for Hisaab in Android settings, then tap Turn on again.');
    }
  }

  void _go(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, hc = context.hc, s = context.store, now = s.now();
    final smsOff = !s.smsOn, empty = s.isEmpty;
    final settings = GlassIconButton(
      tooltip: 'Settings',
      onPressed: () => _go(const SettingsScreen()),
      icon: Icons.settings_outlined,
    );
    if (empty && !smsOff) {
      return Scaffold(
        body: Ambient(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                TopBar('Hisaab', actions: [settings]),
                const Expanded(child: _Empty()),
              ],
            ),
          ),
        ),
      );
    }

    final presets = _presets(now), r = _range;
    String day(DateTime d) => d.year == now.year ? dayMon(d) : '${dayMon(d)} ${d.year}';
    final (from, to) = r == null ? presets[_period]! : (r.start, DateTime(r.end.year, r.end.month, r.end.day + 1));
    final period = r != null
        ? '${day(r.start)} – ${day(r.end)}'
        : switch (_period) {
            'This month' => monthName(now),
            'Last month' => monthName(DateTime(now.year, now.month - 1)),
            final p => p,
          };
    final when = r == null ? _period.toLowerCase() : period; // "Nothing from last month…"
    final rows = s.between(from, to);
    final picked = rows.where(_picked).toList();
    final all = Summary(picked, s.txn), view = _cat == null ? all : Summary(picked, s.txn, only: _cat);
    final scope = [
      period,
      _cat?.full ?? 'all categories',
      _acct ?? 'all accounts',
      ?_statuses[_status],
      if (_tag != null) '#$_tag',
    ].join(' · ');
    final tags = s.tagsInUse;
    final days = <DateTime, List<Txn>>{};
    for (final t in picked.where(_inCat)) {
      days.putIfAbsent(dayStart(t.when), () => []).add(t);
    }
    final groups = [
      for (final MapEntry(key: day, value: ts) in days.entries)
        if (ts.where(_match).toList() case final hits when hits.isNotEmpty) (dayLabel(day, now), ts, hits),
    ];
    final queue = s.queue();

    return GlassPage(
      barHeight: _searching ? 114 : 64,
      bar: Column(
        children: [
          TopBar(
            'Hisaab',
            actions: [
              if (!empty) ...[
                GlassIconButton(
                  tooltip: 'Search',
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    _q = '';
                  }),
                  icon: Icons.search_rounded,
                ),
                GlassIconButton(
                  tooltip: 'Export CSV of this view',
                  onPressed: () => saveCsv(context, from, to, where: (t) => _picked(t) && _inCat(t) && _match(t)),
                  icon: Icons.download_rounded,
                ),
              ],
              settings,
            ],
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Glass(
                radius: 24,
                shadow: false,
                padding: const EdgeInsets.only(left: 16, right: 4),
                child: SizedBox(
                  height: 46,
                  child: Row(
                    spacing: 12,
                    children: [
                      Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                      Expanded(
                        child: TextField(
                          autofocus: true,
                          onChanged: (v) => setState(() => _q = v),
                          style: const TextStyle(fontSize: 16),
                          decoration: InputDecoration.collapsed(
                            hintText: 'Payee, note, tag or UPI Ref',
                            hintStyle: TextStyle(color: hc.muted),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close search',
                        onPressed: () => setState(() {
                          _searching = false;
                          _q = '';
                        }),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: (_, top) => ListView(
        padding: EdgeInsets.only(top: top + 2, bottom: 88),
        children: [
          if (smsOff)
            _SmsOffCards(onTurnOn: _turnOn)
          else if (queue.isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(16, 2, 16, 0), child: _NeedsCard(queue, now)),
          if (!empty) ...[
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                children: [
                  _menu(
                    period,
                    r == null ? _period : _custom,
                    [for (final k in presets.keys) (k, k), (_custom, _custom)],
                    (v) => _pickPeriod(v, from, to, now),
                    on: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _cat == null
                        ? FChip('Category', onTap: () => _breakdown(view, all, scope))
                        : FChip(
                            _cat!.full,
                            on: true,
                            trailing: Icons.close_rounded,
                            semanticLabel: 'Clear category filter ${_cat!.full}',
                            onTap: () => setState(() => _cat = null),
                          ),
                  ),
                  _menu(_statuses[_status] ?? 'Status', _status, [
                    (null, 'Any status'),
                    ..._statuses.entries.map((e) => (e.key, e.value)),
                  ], (v) => setState(() => _status = v)),
                  _menu(_acct ?? 'Account', _acct, [
                    (null, 'All accounts'),
                    for (final a in [...s.accounts, 'Cash', 'Other account']) (a, a),
                  ], (v) => setState(() => _acct = v)),
                  if (tags.isNotEmpty || _tag != null)
                    _menu(_tag == null ? 'Tag' : '#$_tag', _tag, [
                      (null, 'Any tag'),
                      for (final t in tags) (t, '#$t'),
                    ], (v) => setState(() => _tag = v)),
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(16, 2, 16, 4), child: _summary(view, all, scope)),
            if (groups.isEmpty)
              EmptyState(
                title: rows.isEmpty ? 'Nothing yet' : 'No matches',
                text: rows.isEmpty
                    ? 'Payments from $when show up here.'
                    : 'Nothing from $when matches ${_q.trim().isEmpty ? 'these filters' : '“$_q”'}.',
                art: const SizedBox.shrink(),
                action: rows.isNotEmpty && _filtered
                    ? TextButton(
                        onPressed: () => setState(() {
                          _cat = null;
                          _status = null;
                          _acct = null;
                          _tag = null;
                        }),
                        child: const Text('Clear filters'),
                      )
                    : null,
              )
            else
              for (final (label, ts, hits) in groups) ...[
                DayHeader(label, _dayTotal(ts)),
                for (final t in hits) TxnTile(t, onTap: () => openTxn(context, t)),
              ],
          ],
        ],
      ),
      fab: smsOff
          ? null
          : GlassFab(icon: Icons.payments_outlined, label: 'Add cash', onPressed: () => addSpend(context)),
    );
  }

  String _dayTotal(List<Txn> ts) {
    var out = 0, inn = 0;
    for (final t in ts) {
      if (t.status == TxnStatus.credit) {
        inn += t.paise;
      } else if ((t.status == TxnStatus.needs || t.status == TxnStatus.filed) && !t.reimb) {
        out += t.paise;
      }
    }
    return '${_amt(out)} out${inn > 0 ? ' · ${_amt(inn)} in' : ''}';
  }

  /// Two stats, one snapshot bar, the top 3 as a legend. With a category
  /// picked, its payees instead. Counts and percentages are in the sheet.
  Widget _summary(Summary v, Summary all, String scope) {
    final cs = context.cs, hc = context.hc, c = _cat;
    final top = (c == null ? v.byCat : v.payees).take(3).toList();
    final parts = c == null ? [...v.byCat, ?v.unc] : v.payees;
    return Semantics(
      container: true,
      label: 'Spend summary · $scope',
      child: Glass(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Stats(v, compact: true),
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(c == null ? 'Top categories' : 'Top payees', style: T.ls.copyWith(color: hc.muted)),
                  ),
                  TextButton(
                    onPressed: () => _breakdown(v, all, scope),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.only(left: 8, right: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c == null ? 'View all' : 'All ${v.payees.length}'),
                        Icon(Icons.chevron_right_rounded, size: 16, color: cs.primary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (parts.isEmpty)
              Text('No spends yet', style: T.b.copyWith(color: hc.muted))
            else ...[
              _SnapBar(parts, cat: c),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: i >= top.length
                            ? const SizedBox.shrink()
                            : _TopCat(
                                top[i],
                                name: c == null ? top[i].cat!.short : top[i].name,
                                sub: _pct(top[i].paise, v.spent),
                                color: (c ?? top[i].cat)!.of(context).cs.withValues(alpha: c == null ? 1 : _fade[i]),
                                label: c == null
                                    ? '${top[i].cat!.full}, ${rupees(top[i].paise, dec: false)}, filter the list'
                                    : '${top[i].name}, ${rupees(top[i].paise, dec: false)}',
                                onTap: c == null
                                    ? () => setState(() => _cat = top[i].cat)
                                    : () => _breakdown(v, all, scope),
                              ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Every category (or payee). Tapping a category filters the list to it.
  void _breakdown(Summary v, Summary all, String scope) {
    final c = _cat;
    var byPayee = false;
    showHSheet<void>(
      context,
      (sheet) => StatefulBuilder(
        builder: (sheet, set) {
          void pick(VoidCallback f) {
            Navigator.pop(sheet);
            setState(f);
          }

          final payees = c != null || byPayee;
          final list = payees ? v.payees : [...v.byCat, ?v.unc];
          final max = list.fold(0, (m, b) => b.paise > m ? b.paise : m);
          final notCounted = [
            if (v.own > 0) '${rupees(v.own, dec: false)} to own accounts',
            if (v.refunds > 0) '${rupees(v.refunds, dec: false)} in refunds netted out',
          ];
          return SheetFrame(
            title: c?.full ?? 'Spending breakdown',
            heightFactor: .85,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Eyebrow(scope),
                _Stats(v, share: c == null ? null : '${_pct(v.spent, all.spent)} of spend'),
                if (c == null)
                  Seg<bool>(
                    label: 'Group by',
                    value: byPayee,
                    options: const [(false, 'By category', null), (true, 'By payee', null)],
                    onChanged: (v) => set(() => byPayee = v),
                  ),
                TabSwitch(
                  index: payees ? 1 : 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (list.isEmpty) Text('No spends yet', style: T.b.copyWith(color: context.hc.muted)),
                      for (final b in list)
                        _BarRow(
                          b,
                          of: max,
                          sub: payees ? '' : _pct(b.paise, v.spent),
                          meta: b.cat == null && !payees
                              ? '${_plural(b.n, 'payment')} waiting for a category'
                              : _plural(b.n, 'payment'),
                          onTap: payees
                              ? null
                              : () => pick(() => b.cat == null ? _status = TxnStatus.needs : _cat = b.cat),
                        ),
                    ],
                  ),
                ),
                Text(
                  c != null
                      ? 'Clear the Category filter to compare across categories.'
                      : [
                          if (notCounted.isNotEmpty) 'Not counted: ${notCounted.join(' · ')}.',
                          if (!payees) 'Tap a category to filter the list.',
                        ].join(' '),
                  style: T.lsReg.copyWith(color: context.hc.muted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Expense | Income, side by side. [compact]: the card's version, the
/// payment count as the label and no line under.
class _Stats extends StatelessWidget {
  const _Stats(this.v, {this.share, this.compact = false});
  final Summary v;

  /// "29% of spend", when one category is picked.
  final String? share;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    Widget stat(bool inn, int paise, String label, String sub) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Row(
          spacing: 6,
          children: [
            DirIcon(inflow: inn),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.ls.copyWith(color: hc.muted),
              ),
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AmountText(
            paise,
            size: AmtSize.ml,
            prefix: inn && paise > 0 ? '+₹' : '₹',
            color: inn ? (paise > 0 ? hc.teal : hc.muted) : null,
          ),
        ),
        if (!compact) Text(sub, style: T.lsReg.copyWith(color: hc.muted)),
      ],
    );
    final inSub = v.inflow == 0
        ? 'no money in'
        : [_plural(v.inCount, 'payment'), if (v.refunds > 0) 'refunds netted'].join(' · ');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: stat(
              false,
              v.spent,
              compact ? '${_plural(v.payments, 'payment')} out' : 'Expense',
              [_plural(v.payments, 'payment'), ?share].join(' · '),
            ),
          ),
          VerticalDivider(width: 29, thickness: 1, color: context.glass.line),
          Expanded(
            child: stat(
              true,
              v.inflow,
              compact ? (v.inCount == 0 ? 'Nothing in' : '${_plural(v.inCount, 'payment')} in') : 'Income',
              inSub,
            ),
          ),
        ],
      ),
    );
  }
}

/// One 8 dp bar split by share; uncategorised spend is striped.
class _SnapBar extends StatelessWidget {
  const _SnapBar(this.parts, {this.cat});
  final List<Bar> parts;
  final Cat? cat;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold(0, (s, b) => s + b.paise);
    return ExcludeSemantics(
      child: SizedBox(
        height: 8,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, // segments fill the 8 dp
            spacing: 2,
            children: [
              for (final (i, b) in parts.indexed)
                if (b.paise > 0)
                  Expanded(
                    flex: math.max(1, (b.paise * 1000 / total).round()),
                    child: cat == null && b.cat == null
                        ? const Stripes()
                        : ColoredBox(
                            color: (cat ?? b.cat)!
                                .of(context)
                                .cs
                                .withValues(alpha: cat == null ? 1 : _fade[math.min(i, 4)]),
                          ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A legend cell: swatch, name, amount and share. Tappable.
class _TopCat extends StatelessWidget {
  const _TopCat(
    this.b, {
    required this.name,
    required this.sub,
    required this.color,
    required this.label,
    required this.onTap,
  });
  final Bar b;
  final String name, sub, label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                    ),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.lsReg.copyWith(color: hc.muted),
                      ),
                    ),
                  ],
                ),
                Text.rich(
                  TextSpan(
                    style: T.b.merge(T.num).copyWith(fontWeight: FontWeight.w600),
                    children: [
                      TextSpan(text: rupees(b.paise, dec: false)),
                      if (sub.isNotEmpty)
                        TextSpan(
                          text: ' $sub',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: hc.muted),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A track filled to [b]'s share of [of], in its category's colour.
Widget _track(BuildContext context, Bar b, int of, double h) => Container(
  height: h,
  alignment: Alignment.centerLeft,
  decoration: BoxDecoration(color: context.cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(h / 2)),
  child: FractionallySizedBox(
    widthFactor: of == 0 ? 0 : (b.paise / of).clamp(0, 1),
    child: b.cat == null
        ? Stripes(radius: h / 2)
        : Container(
            decoration: BoxDecoration(color: b.cat!.of(context).cs, borderRadius: BorderRadius.circular(h / 2)),
          ),
  ),
);

/// The sheet's row: dot, name, amount, a bar, and a count.
class _BarRow extends StatelessWidget {
  const _BarRow(this.b, {required this.of, this.sub = '', this.meta, this.onTap});
  final Bar b;
  final int of;
  final String sub;
  final String? meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc, cc = b.cat?.of(context);
    const d = 32.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          spacing: 12,
          children: [
            cc == null
                ? Dashed(
                    color: hc.amber,
                    circle: true,
                    child: SizedBox.square(
                      dimension: d,
                      child: Icon(Icons.edit_outlined, size: 16, color: hc.amber),
                    ),
                  )
                : Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(color: cc.cc, shape: BoxShape.circle),
                    child: Icon(b.cat!.icon, size: 16, color: cc.con),
                  ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.l),
                        ),
                        Text.rich(
                          TextSpan(
                            style: T.l.merge(T.num),
                            children: [
                              TextSpan(text: _amt(b.paise)),
                              if (sub.isNotEmpty)
                                TextSpan(
                                  text: ' $sub',
                                  style: TextStyle(color: hc.muted, fontWeight: FontWeight.w400),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    _track(context, b, of, 4),
                    if (meta != null) Text(meta!, style: T.lsReg.copyWith(color: hc.muted)),
                  ],
                ),
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, size: 20, color: hc.muted),
          ],
        ),
      ),
    );
  }
}

class _NeedsCard extends StatelessWidget {
  const _NeedsCard(this.queue, this.now);
  final List<Txn> queue;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc, g = context.glass;
    final pending = queue.fold(0, (sum, t) => sum + t.paise);
    final oldest = queue.map((t) => t.when).reduce((a, b) => b.isBefore(a) ? b : a);
    return Glass(
      color: g.on ? hc.amberC.withValues(alpha: .8) : hc.amberC,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        spacing: 10,
        children: [
          Icon(Icons.edit_outlined, color: hc.onAmberC),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${queue.length} need${queue.length == 1 ? 's' : ''} details',
                  style: T.t.copyWith(color: hc.onAmberC),
                ),
                Text(
                  '${rupees(pending, dec: false)} · ${sameDay(oldest, now) ? 'all from today' : 'oldest from ${dow(oldest)}'}',
                  style: T.b.merge(T.num).copyWith(color: hc.onAmberC),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => openQueue(context),
            style: FilledButton.styleFrom(
              backgroundColor: hc.amber,
              foregroundColor: hc.onAmber,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }
}

/// SMS access is off: say so, and offer adding by hand. The list below still
/// shows everything captured before.
class _SmsOffCards extends StatelessWidget {
  const _SmsOffCards({required this.onTurnOn});
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, hc = context.hc, s = context.store;
    final last = s.lastCapture;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        spacing: 12,
        children: [
          HBanner(
            tone: BannerTone.err,
            icon: Icons.warning_amber_rounded,
            title: 'SMS access is off',
            text:
                "New UPI payments aren't being captured."
                '${last == null ? '' : ' Last capture: ${dowDayMon(last)}, ${time12(last)}.'}',
            actions: [
              (
                'Why we need it',
                () => toast(context, 'Bank SMS is how Hisaab sees UPI payments. It never leaves this phone.'),
              ),
              ('Turn on', onTurnOn),
            ],
          ),
          Glass(
            mat: Mat.thin,
            radius: 24,
            shadow: false,
            padding: const EdgeInsets.all(16),
            child: Column(
              spacing: 12,
              children: [
                Row(
                  spacing: 12,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.edit_outlined, color: cs.onPrimaryContainer),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Add spends by hand for now', style: T.t),
                          Text(
                            s.reminderOn
                                ? 'The ${time12(DateTime(2026, 1, 1, s.reminderAt.hour, s.reminderAt.minute))} check-in still reminds you.'
                                : 'Turn on the daily check-in in Settings for a nudge.',
                            style: T.b.copyWith(color: hc.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => addSpend(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add a spend'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final s = context.store, accounts = s.accounts, at = s.reminderAt;
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 16,
              children: [
                EmptyState(
                  art: const EmptyArt(icon: Icons.schedule_rounded, done: false),
                  title: 'Waiting for your first UPI payment',
                  text:
                      "Pay anyone from any UPI app. It shows up here, and as a notification, within seconds of the bank's SMS.",
                  action: FilledButton.tonalIcon(
                    onPressed: () => addSpend(context),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Add a cash spend'),
                  ),
                ),
                HCard(
                  child: Column(
                    children: [
                      Li(
                        icon: Icons.account_balance_outlined,
                        title: accounts.isEmpty
                            ? 'Watching for bank SMS'
                            : 'Watching ${accounts.length} account${accounts.length == 1 ? '' : 's'}',
                        sub: accounts.isEmpty ? 'Any bank on the allowlist is picked up' : accounts.join(' · '),
                        subMono: accounts.isNotEmpty,
                      ),
                      const LiDivider(),
                      Li(
                        icon: Icons.notifications_none_rounded,
                        title: s.reminderOn
                            ? 'Check-in at ${time12(DateTime(2026, 1, 1, at.hour, at.minute))}'
                            : 'Daily check-in is off',
                        sub: 'Daily, change in Settings',
                      ),
                      const LiDivider(),
                      const Li(
                        icon: Icons.shield_outlined,
                        title: 'On this phone only',
                        sub: 'No account, no internet permission',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
