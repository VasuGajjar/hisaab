// Settings and the screens behind its rows.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../capture.dart';
import '../data.dart';
import '../format.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'entry.dart';
import 'home.dart';
import 'onboarding.dart';

String _plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Picks a range of days, then saves them as CSV where the user chooses.
Future<void> exportCsv(BuildContext context) async {
  final s = context.store, now = s.now();
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: now,
    initialDateRange: DateTimeRange(start: monthStart(now), end: now),
    helpText: 'Export which days?',
    saveText: 'Export',
  );
  if (range == null || !context.mounted) return;
  await saveCsv(context, range.start, dayStart(range.end).add(const Duration(days: 1)));
}

/// Saves [from, to) as CSV where the user chooses; [where] narrows the rows.
Future<void> saveCsv(BuildContext context, DateTime from, DateTime to, {bool Function(Txn)? where}) async {
  final name = 'hisaab-${_ymd(from)}-to-${_ymd(DateTime(to.year, to.month, to.day - 1))}.csv';
  final ok = await saveFile(name, utf8.encode(context.store.csv(from, to, where: where)));
  if (context.mounted) toast(context, ok ? 'Saved $name' : 'Not saved');
}

/// Saves everything (payments, categories, rules, settings) as one file
/// where the user picks. Uninstalling deletes the ledger; this file doesn't.
Future<void> backupData(BuildContext context) async {
  final s = context.store, name = 'hisaab-backup-${_ymd(s.now())}.db';
  final f = File('${(await getTemporaryDirectory()).path}/$name');
  if (f.existsSync()) f.deleteSync();
  s.backupTo(f.path);
  final ok = await saveFile(name, f.readAsBytesSync(), type: 'application/octet-stream');
  f.deleteSync();
  if (context.mounted) toast(context, ok ? 'Backed up to $name' : 'Not saved');
}

/// Replaces everything with a backup file the user picks (asking first if
/// there's a ledger to lose), reads the SMS that came in since, opens Home.
Future<void> importBackup(BuildContext context) async {
  final s = context.store;
  if (s.onboarded) {
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Import a backup?'),
        content: const Text("Everything on this phone is replaced with what's in the backup. Back up first to keep it."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Choose file')),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
  }
  final Uint8List? bytes;
  try {
    bytes = await openFile();
  } on PlatformException {
    if (context.mounted) toast(context, "Couldn't read that file");
    return;
  }
  if (bytes == null) return;
  final f = File('${(await getTemporaryDirectory()).path}/import.db')..writeAsBytesSync(bytes);
  try {
    await s.restoreFrom(f.path);
  } on FormatException catch (e) {
    if (context.mounted) toast(context, e.message);
    return;
  } finally {
    f.deleteSync();
  }
  await catchUp(s); // payments since the backup; notices SMS access not yet given on this install
  if (!context.mounted) return;
  toast(context, 'Backup imported');
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
}

Widget _catDot(BuildContext context, Cat c, {double size = 32}) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(color: c.of(context).cc, shape: BoxShape.circle),
  child: Icon(c.icon, size: size * .56, color: c.of(context).con),
);

/// Pushed from Home's app bar.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.store, at = s.reminderAt, accounts = s.accounts;
    final (ruleCount, ruleExample) = s.rules;
    const chevron = Icon(Icons.chevron_right_rounded);
    void go(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    Li link(IconData icon, String title, String sub, VoidCallback onTap, {bool mono = false}) =>
        Li(icon: icon, title: title, sub: sub, subMono: mono, trailing: chevron, onTap: onTap);
    Li toggle(IconData icon, String title, String sub, bool v, ValueChanged<bool> set, {VoidCallback? onTap}) => Li(
      icon: icon,
      title: title,
      sub: sub,
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      onTap: onTap ?? () => set(!v),
      trailing: HSwitch(value: v, onChanged: set),
    );
    // A section: its label, then its rows on one glass card.
    List<Widget> section(String label, List<Widget> rows, {double top = 14}) => [
      Padding(
        padding: EdgeInsets.fromLTRB(4, top, 4, 6),
        child: Text(
          label,
          style: T.b.copyWith(fontWeight: FontWeight.w600, color: context.cs.primary),
        ),
      ),
      HCard(
        child: Column(
          children: [
            for (final (i, r) in rows.indexed) ...[if (i > 0) const LiDivider(), r],
          ],
        ),
      ),
    ];

    return GlassPage(
      bar: const TopBar('Settings', leading: BackBtn()),
      body: (c, top) => ListView(
        padding: EdgeInsets.fromLTRB(16, top, 16, 24 + MediaQuery.paddingOf(c).bottom),
        children: [
          ...section('Daily check-in', top: 4, [
            toggle(
              Icons.schedule_rounded,
              'Reminder time',
              '${time12(DateTime(2026, 1, 1, at.hour, at.minute))}, every day',
              s.reminderOn,
              (v) async {
                if (v && !await requestNotificationPermission()) {
                  if (context.mounted) toast(context, 'Allow notifications for Hisaab in Android settings first.');
                  return;
                }
                s.reminderOn = v;
              },
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: at,
                  initialEntryMode: TimePickerEntryMode.input,
                );
                if (t != null) s.reminderAt = t;
              },
            ),
          ]),
          ...section('Capture', [
            link(
              Icons.account_balance_outlined,
              'Banks',
              [...accounts, '${s.banksOn} banks read'].join(' · '),
              () => go(const BanksScreen()),
              mono: true,
            ),
            toggle(
              Icons.push_pin_outlined,
              'Auto-file remembered payees',
              '0 taps; you get “Filed · Undo” instead',
              s.autoFile,
              (v) => s.autoFile = v,
            ),
          ]),
          ...section('Display', [
            toggle(
              Icons.blur_on_rounded,
              'Glass effects',
              'Off = solid surfaces, easier on older phones',
              s.glass,
              (v) => s.glass = v,
            ),
          ]),
          ...section('Data & privacy', [
            link(
              Icons.shield_outlined,
              'On this phone only',
              'No account, no server, no internet permission',
              () => go(const PrivacyScreen()),
            ),
            toggle(
              Icons.receipt_long_outlined,
              'Keep raw SMS for 30 days',
              'Unreadable ones stay until you fill them in',
              s.keepRaw,
              (v) => s.keepRaw = v,
            ),
            link(
              Icons.backup_outlined,
              'Back up data',
              'Everything in one file · keep it off this phone',
              () => backupData(context),
            ),
            link(
              Icons.settings_backup_restore_rounded,
              'Import backup',
              'Replaces what is on this phone',
              () => importBackup(context),
            ),
            link(Icons.download_rounded, 'Export CSV', 'Pick a range · save it as a file', () => exportCsv(context)),
          ]),
          ...section('Organise', [
            link(
              Icons.grid_view_rounded,
              'Categories',
              '${cats.length} · rename, reorder, add, delete',
              () => go(const CategoriesScreen()),
            ),
            link(
              Icons.push_pin_outlined,
              'Merchant rules',
              ruleExample == null ? 'None yet · “Remember” on a payee adds one' : '$ruleCount · e.g. $ruleExample',
              () => go(const RulesScreen()),
            ),
            link(
              Icons.swap_horiz_rounded,
              'Own accounts',
              'Transfers between them are never spend',
              () => go(const OwnAccountsScreen()),
            ),
          ]),
        ],
      ),
    );
  }
}

/// A settings sub-page: back arrow, title, scrolling body.
class _Page extends StatelessWidget {
  const _Page(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassPage(
    bar: TopBar(title, small: true, leading: const BackBtn()),
    body: (c, top) => ListView(
      padding: EdgeInsets.only(top: top, bottom: 24 + MediaQuery.paddingOf(c).bottom),
      children: children,
    ),
  );
}

Widget _note(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
  child: Text(text, style: T.b.copyWith(color: context.hc.muted)),
);

// ---------------------------------------------------------------------------
// Banks

class BanksScreen extends StatelessWidget {
  const BanksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.store;
    return _Page('Banks', [
      _note(
        context,
        'An SMS is read when its sender ID or its text names one of these banks, like JD-AXISBK or “…your Axis Bank a/c”, and it reads as a payment. Everything else is dropped and never stored.',
      ),
      for (final b in s.bankList)
        Li(
          icon: b.bank.dupOnly ? Icons.content_copy_rounded : Icons.account_balance_outlined,
          title: b.bank.name,
          sub: b.bank.dupOnly
              ? 'Only used to spot duplicates'
              : b.accounts.isNotEmpty
              ? b.accounts.map((l) => '••$l').join(' · ')
              : b.added
              ? 'Known by ${b.bank.words.join(', ')}'
              : 'No SMS seen yet',
          subMono: b.accounts.isNotEmpty,
          onTap: () => s.setBankOn(b.bank.name, !b.on),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (b.added)
                IconButton(
                  tooltip: 'Remove ${b.bank.name}',
                  onPressed: () => s.removeBank(b.bank.name),
                  icon: const Icon(Icons.close_rounded),
                ),
              HSwitch(value: b.on, onChanged: (v) => s.setBankOn(b.bank.name, v)),
            ],
          ),
        ),
      Li(
        icon: Icons.add_rounded,
        title: 'Add a bank',
        sub: 'One not on this list',
        titleStyle: TextStyle(fontWeight: FontWeight.w600, color: context.cs.primary),
        onTap: () => addBank(context),
      ),
    ]);
  }
}

/// Asks for a bank's name and what its SMS say, then reads them.
Future<void> addBank(BuildContext context) async {
  final s = context.store;
  final v = await askText(context, 'Add a bank', [
    ('Bank', 'e.g. Saraswat'),
    ('Known by', 'words or sender ID, e.g. Saraswat, SARBNK'),
  ]);
  if (v == null) return;
  if (v[0].isEmpty) {
    if (context.mounted) toast(context, 'Needs a bank name.');
    return;
  }
  s.addBank(v[0], v[1].isEmpty ? v[0] : v[1]);
  if (context.mounted) toast(context, 'SMS naming ${v[0]} will be read');
}
// ---------------------------------------------------------------------------
// On this phone only

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.store, n = s.counts;
    Widget point(IconData icon, String title, String text) => Li(icon: icon, title: title, sub: text);
    return _Page('On this phone only', [
      point(
        Icons.cloud_off_outlined,
        'No internet permission',
        "The installed app can't reach the internet, so nothing can be uploaded.",
      ),
      point(Icons.person_off_outlined, 'No account, no server', 'Everything is one database on this phone.'),
      point(
        Icons.backup_outlined,
        'No cloud backup',
        'Android backup is off for Hisaab, so nothing is copied to Google Drive, and uninstalling deletes '
            'everything. Back up data to a file to keep a copy.',
      ),
      point(
        Icons.sms_outlined,
        'Only bank payment SMS are kept',
        'Each SMS with an amount is checked for a bank name; anything else is dropped and never stored. OTPs are skipped.',
      ),
      point(
        Icons.receipt_long_outlined,
        s.keepRaw ? 'Raw SMS kept for 30 days' : 'Raw SMS not kept',
        'Unreadable ones stay until you fill them in.',
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: HCard(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Stored now: ${_plural(n.txns, 'transaction')} · ${_plural(n.sms, 'raw SMS')} · ${_plural(n.payees, 'payee')}'
                .replaceAll('raw SMSs', 'raw SMS'),
            style: T.b.merge(T.num),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: context.cs.error,
            side: BorderSide(color: context.cs.error),
          ),
          onPressed: () => _wipe(context),
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Delete all data'),
        ),
      ),
    ]);
  }

  Future<void> _wipe(BuildContext context) async {
    final s = context.store;
    final sure = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          "Every transaction, rule, category change and setting is deleted from this phone. It can't be undone; back up data first to keep a copy.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(d).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    s.wipe();
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const OnboardingScreen()), (_) => false);
  }
}

// ---------------------------------------------------------------------------
// Categories

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.store, list = cats;
    return GlassPage(
      bar: const TopBar('Categories', small: true, leading: BackBtn()),
      body: (c, top) => ReorderableListView.builder(
        header: _note(context, 'Tap to rename or delete. Drag the handle to reorder; the grid follows this order.'),
        buildDefaultDragHandles: false,
        padding: EdgeInsets.only(top: top, bottom: 96),
        itemCount: list.length,
        onReorderItem: (from, to) => s.moveCat(list[from], to),
        itemBuilder: (_, i) {
          final c = list[i];
          return Material(
            key: ValueKey(c.key),
            type: MaterialType.transparency,
            child: Li(
              leading: _catDot(context, c),
              title: c.full,
              sub: c.short == c.full ? null : 'Shown as “${c.short}” in the grid',
              onTap: () => editCategory(context, c),
              trailing: ReorderableDragStartListener(
                index: i,
                child: Semantics(
                  label: 'Reorder ${c.full}',
                  child: const SizedBox.square(dimension: 48, child: Icon(Icons.drag_handle_rounded)),
                ),
              ),
            ),
          );
        },
      ),
      fab: GlassFab(onPressed: () => editCategory(context, null), icon: Icons.add_rounded, label: 'New category'),
    );
  }
}

/// Adds a category ([c] null) or edits one: name, colour, icon.
Future<void> editCategory(BuildContext context, Cat? c) {
  final look = c == null ? ('other', 'grid') : context.store.catLook(c);
  return showHSheet<void>(context, (_) => _CatEditor(c, look.$1, look.$2));
}

class _CatEditor extends StatefulWidget {
  const _CatEditor(this.cat, this.style, this.icon);
  final Cat? cat;
  final String style, icon;

  @override
  State<_CatEditor> createState() => _CatEditorState();
}

class _CatEditorState extends State<_CatEditor> {
  late final _name = TextEditingController(text: widget.cat?.full);
  late Cat _style = builtInCats.firstWhere((c) => c.key == widget.style, orElse: () => other);
  late String _icon = widget.icon;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Asks where its payments go, then deletes the category.
  Future<void> _delete() async {
    final s = context.store, c = widget.cat!, use = s.catUsage(c);
    final used = use.payments + use.rules > 0;
    var to = catOf('other')!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Delete ${c.full}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text(
                used
                    ? '${_plural(use.payments, 'payment')}${use.rules > 0 ? ' and ${_plural(use.rules, 'payee rule')}' : ''} move to:'
                    : 'Nothing is filed under it.',
              ),
              if (used)
                DropdownButton<Cat>(
                  value: to,
                  isExpanded: true,
                  items: [
                    for (final x in cats)
                      if (x != c) DropdownMenuItem(value: x, child: Text(x.full)),
                  ],
                  onChanged: (v) => set(() => to = v!),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(d, true),
              style: TextButton.styleFrom(foregroundColor: Theme.of(d).colorScheme.error),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    s.deleteCat(c, to);
    toast(context, used ? '${c.full} deleted · moved to ${to.full}' : '${c.full} deleted');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, s = context.store;
    Widget pick(bool on, String label, Widget child, VoidCallback onTap) => Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: on ? cs.primary : Colors.transparent, width: 2),
          ),
          child: child,
        ),
      ),
    );
    final cc = _style.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text(widget.cat == null ? 'New category' : 'Edit category', style: T.tl),
          TextField(
            controller: _name,
            autofocus: widget.cat == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Pets'),
          ),
          const Eyebrow('Colour'),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final b in builtInCats)
                pick(
                  b == _style,
                  '${b.full} colour',
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: b.of(context).cs, shape: BoxShape.circle),
                  ),
                  () => setState(() => _style = b),
                ),
            ],
          ),
          const Eyebrow('Icon'),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final MapEntry(key: name, value: icon) in catIcons.entries)
                pick(
                  name == _icon,
                  '$name icon',
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: name == _icon ? cc.cc : null, shape: BoxShape.circle),
                    child: Icon(icon, size: 20, color: name == _icon ? cc.con : cs.onSurfaceVariant),
                  ),
                  () => setState(() => _icon = name),
                ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 8,
            children: [
              if (widget.cat != null && widget.cat!.key != 'other') ...[
                TextButton.icon(
                  onPressed: _delete,
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
                const Spacer(),
              ],
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ListenableBuilder(
                listenable: _name,
                builder: (_, _) => FilledButton(
                  onPressed: _name.text.trim().isEmpty
                      ? null
                      : () {
                          s.saveCat(key: widget.cat?.key, name: _name.text, style: _style, icon: _icon);
                          Navigator.pop(context);
                        },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Merchant rules

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.store, rules = s.rulesList;
    return _Page('Merchant rules', [
      _note(
        context,
        s.autoFile
            ? 'Payments to these payees are filed with no tap (Auto-file is on).'
            : 'Payments to these payees offer their category as the 1-tap choice.',
      ),
      if (rules.isEmpty)
        const EmptyState(
          art: SizedBox.shrink(),
          title: 'No rules yet',
          text: 'Leave “Remember” on when you file a payment and its payee shows up here.',
        ),
      for (final r in rules)
        Li(
          leading: _catDot(context, r.cat),
          title: r.name,
          sub: '→ ${r.cat.full} · ${_plural(r.count, 'payment')}',
          onTap: () async {
            final c = await pickCategory(context, selected: r.cat);
            if (c != null) s.setRule(r.id, c);
          },
          trailing: IconButton(
            tooltip: 'Forget rule',
            onPressed: () => s.setRule(r.id, null),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Own accounts

class OwnAccountsScreen extends StatelessWidget {
  const OwnAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.store, accounts = s.allAccounts, mine = s.payees(own: true);
    return _Page('Own accounts', [
      _note(context, 'Money moving between these is a transfer: never spend, never income.'),
      const SecLabel('Bank accounts'),
      for (final a in accounts)
        Li(
          icon: Icons.account_balance_outlined,
          title: a.alias.isEmpty ? '${a.bank} ••${a.last4}' : a.alias,
          titleStyle: a.alias.isEmpty ? T.mono : null,
          sub: a.alias.isEmpty ? null : '${a.bank} ••${a.last4}',
          subMono: true,
          onTap: () => _rename(context, a),
          trailing: IconButton(
            tooltip: a.alias.isEmpty ? 'Name it' : 'Rename',
            onPressed: () => _rename(context, a),
            icon: const Icon(Icons.edit_outlined),
          ),
        ),
      Li(
        icon: Icons.add_rounded,
        title: 'Add an account',
        sub: 'One with no SMS here: another bank, a wallet',
        titleStyle: TextStyle(fontWeight: FontWeight.w600, color: context.cs.primary),
        onTap: () => _addAccount(context),
      ),
      const SecLabel('Your UPI IDs'),
      for (final p in mine)
        Li(
          icon: Icons.person_outline_rounded,
          title: p.name,
          sub: p.key.startsWith('name:') ? 'By name in the SMS' : p.key,
          subMono: !p.key.startsWith('name:'),
          trailing: IconButton(
            tooltip: 'Not me',
            onPressed: () => s.setOwnPayee(p.id, false),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      Li(
        icon: Icons.add_rounded,
        title: 'Mark a payee as you',
        sub: 'e.g. your own UPI ID in another app',
        titleStyle: TextStyle(fontWeight: FontWeight.w600, color: context.cs.primary),
        onTap: () => _pickPayee(context),
      ),
    ]);
  }

  Future<void> _addAccount(BuildContext context) async {
    final s = context.store;
    // Digits last: askText gives the last field the number keyboard.
    final v = await askText(context, 'Add an account', [
      ('Bank or wallet', 'e.g. SBI'),
      ('Name (optional)', 'e.g. Salary, Joint'),
      ('Last digits', 'e.g. 1234'),
    ], keyboard: TextInputType.number);
    if (v == null) return;
    if (v[0].isEmpty || !RegExp(r'^\d{3,4}$').hasMatch(v[2])) {
      if (context.mounted) toast(context, 'Needs a bank and the last 3 or 4 digits.');
      return;
    }
    s.addAccount(v[0], v[2], v[1]);
  }

  /// A name to tell two accounts at one bank apart; blank clears it.
  Future<void> _rename(BuildContext context, Account a) async {
    final s = context.store;
    final v = await askText(
      context,
      '${a.bank} ••${a.last4}',
      [('Name', 'e.g. Salary, Joint')],
      action: 'Save',
      initial: [a.alias],
    );
    if (v != null) s.setAlias(a.id, v.first);
  }

  Future<void> _pickPayee(BuildContext context) async {
    final s = context.store, list = s.payees(own: false);
    final id = await showHSheet<int>(
      context,
      (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        maxChildSize: .95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Which payee is you?', style: T.tl),
            ),
            if (list.isEmpty) _note(c, 'No payees yet.'),
            for (final p in list)
              Li(
                icon: Icons.person_outline_rounded,
                title: p.name,
                sub: '${p.key.startsWith('name:') ? 'By name' : p.key} · ${_plural(p.count, 'payment')}',
                onTap: () => Navigator.pop(c, p.id),
              ),
          ],
        ),
      ),
    );
    if (id == null) return;
    s.setOwnPayee(id, true);
    if (context.mounted) toast(context, 'Payments with them now count as transfers');
  }
}
