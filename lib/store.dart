// The SQLite ledger and the business rules: capture, filing, payee rules,
// duplicates, refunds, own-account transfers and totals.
// ponytail: synchronous sqlite3 on the UI isolate; a personal ledger is a
// few thousand rows. Move to a background isolate (drift / sqlite_async)
// if a query ever shows up in a frame.
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Row;
import 'package:sqlite3/sqlite3.dart';

import 'data.dart';
import 'format.dart';
import 'sms.dart';

const _schema = '''
CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT;

-- The allowlist. dup_only: a wallet that echoes bank SMS (Amazon Pay).
CREATE TABLE senders (
  code TEXT PRIMARY KEY,
  bank TEXT NOT NULL,
  dup_only INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1
) STRICT;

CREATE TABLE accounts (
  id INTEGER PRIMARY KEY,
  bank TEXT NOT NULL,
  last4 TEXT NOT NULL,
  tracked INTEGER NOT NULL DEFAULT 1,
  UNIQUE (bank, last4)
) STRICT;

-- key: the VPA, or 'name:<payee>' when the SMS has no VPA.
-- rule_cat: the remembered category, the 1-tap action.
CREATE TABLE merchants (
  id INTEGER PRIMARY KEY,
  key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  rule_cat TEXT
) STRICT;

-- Raw SMS, kept 30 days (unreadable ones until filled in).
CREATE TABLE sms (
  id INTEGER PRIMARY KEY,
  sender TEXT NOT NULL,
  body TEXT NOT NULL,
  at INTEGER NOT NULL
) STRICT;
CREATE INDEX sms_at ON sms (at);

CREATE TABLE txns (
  id INTEGER PRIMARY KEY,
  status TEXT NOT NULL CHECK (status IN ('needs', 'filed', 'credit', 'ignored', 'dup', 'unread')),
  paise INTEGER NOT NULL CHECK (paise > 0),
  at INTEGER NOT NULL,
  inflow INTEGER NOT NULL DEFAULT 0,
  name TEXT NOT NULL,
  vpa TEXT NOT NULL DEFAULT '',
  ref TEXT NOT NULL DEFAULT '',
  sender TEXT NOT NULL DEFAULT '',
  cat TEXT,
  note TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT 'sms' CHECK (source IN ('sms', 'cash', 'other')),
  own INTEGER NOT NULL DEFAULT 0,
  reimb INTEGER NOT NULL DEFAULT 0,
  credit_kind TEXT CHECK (credit_kind IN ('refund', 'moneyBack', 'income')),
  account_id INTEGER REFERENCES accounts (id),
  merchant_id INTEGER REFERENCES merchants (id),
  sms_id INTEGER REFERENCES sms (id) ON DELETE SET NULL,
  dup_of INTEGER REFERENCES txns (id) ON DELETE CASCADE,
  refund_of INTEGER REFERENCES txns (id) ON DELETE SET NULL,
  CHECK (status <> 'filed' OR cat IS NOT NULL)
) STRICT;
CREATE INDEX txns_at ON txns (at);
CREATE INDEX txns_status ON txns (status);
CREATE INDEX txns_merchant ON txns (merchant_id);

CREATE TABLE tags (
  txn_id INTEGER NOT NULL REFERENCES txns (id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  PRIMARY KEY (txn_id, tag)
) STRICT, WITHOUT ROWID;
''';

/// v2: editable categories; payees that are you (own UPI IDs).
const _v2 = '''
CREATE TABLE categories (
  key TEXT PRIMARY KEY,
  short TEXT NOT NULL,
  full TEXT NOT NULL,
  style TEXT NOT NULL, -- the built-in category whose colours it uses
  icon TEXT NOT NULL,  -- a name in catIcons
  sort INTEGER NOT NULL
) STRICT;
ALTER TABLE merchants ADD COLUMN own INTEGER NOT NULL DEFAULT 0;
''';

/// v3: one payment across several categories. The shares add up to the
/// payment; its own cat is the biggest share.
const _v3 = '''
CREATE TABLE splits (
  txn_id INTEGER NOT NULL REFERENCES txns (id) ON DELETE CASCADE,
  cat TEXT NOT NULL,
  paise INTEGER NOT NULL CHECK (paise > 0),
  PRIMARY KEY (txn_id, cat)
) STRICT, WITHOUT ROWID;
''';

/// v4: SMS are matched by bank (sender ID or text), not by exact sender ID
/// and account. A row per bank switched off or added; words: what an added
/// bank is known by, comma-separated (null for built-in ones).
const _v4 = '''
CREATE TABLE banks (
  name TEXT PRIMARY KEY,
  enabled INTEGER NOT NULL DEFAULT 1,
  words TEXT
) STRICT;
''';

/// v5: message formats learned by filling in an unreadable SMS. shape: its
/// smsShape; SMS with that shape are read as going out (inflow 0) or in, to
/// or from name.
const _v5 = '''
CREATE TABLE formats (shape TEXT PRIMARY KEY, inflow INTEGER NOT NULL, name TEXT NOT NULL) STRICT;
''';

/// v6: a name you give an account, to tell two at one bank apart.
const _v6 = "ALTER TABLE accounts ADD COLUMN alias TEXT NOT NULL DEFAULT '';";

/// One of your accounts; [label] is how payments show it.
typedef Account = ({int id, String bank, String last4, String alias, String label});

/// "HDFC ••1111", then its name if you gave it one: "HDFC ••1111 · Salary".
/// Bank first: the Entry sheet reads the bank back as the label's first word.
String _acct(Row r) {
  final alias = r['alias'] as String? ?? '';
  return '${r['bank']} ••${r['last4']}${alias.isEmpty ? '' : ' · $alias'}';
}

/// Two SMS for the same amount this close together may be one payment.
const _dupWindow = Duration(minutes: 10);

/// How far back a credit is matched to the payment it refunds.
const _refundWindow = Duration(days: 60);

int _ms(DateTime d) => d.millisecondsSinceEpoch;

/// One summary row: a category (null = not categorised yet) or a payee.
typedef Bar = ({String name, Cat? cat, int paise, int n});

/// Spend in [ts]: refunds netted from the payment they refund; reimbursable,
/// own-account and duplicate rows left out. A payment under several
/// categories counts in full in each of them, and once in [spent]. [only]
/// keeps one category.
class Summary {
  Summary(Iterable<Txn> ts, Txn? Function(int id) byId, {Cat? only}) {
    final cats = <Cat?, (int, int)>{}, payees = <String, (Cat?, int, int)>{};
    var total = 0;
    // sign: 1 = a spend, -1 = a refund of one. Returns the paise counted.
    int add(Txn t, int paise, int sign) {
      final cs = t.splits.isEmpty ? [t.cat] : [for (final (c, _) in t.splits) c];
      if (only != null && !cs.contains(only)) return 0;
      for (final c in only == null ? cs : [only]) {
        final (cp, cn) = cats[c] ?? (0, 0);
        cats[c] = (cp + sign * paise, cn + (sign > 0 ? 1 : 0));
      }
      final (pc, pp, pn) = payees[t.name] ?? (null, 0, 0);
      payees[t.name] = (pc ?? only ?? cs.first, pp + sign * paise, pn + (sign > 0 ? 1 : 0));
      total += sign * paise;
      return paise;
    }

    for (final t in ts) {
      if ((t.status == TxnStatus.needs || t.status == TxnStatus.filed) && !t.reimb) {
        if (add(t, t.paise, 1) > 0) payments++;
      } else if (t.status == TxnStatus.credit) {
        final o = t.refundOf == null ? null : byId(t.refundOf!);
        final netted = o == null ? 0 : add(o, t.paise, -1);
        if (t.refundOf == null) {
          if (only == null) {
            inflow += t.paise;
            inCount++;
          }
        } else {
          refunds += only == null ? t.paise : netted;
        }
      }
      if (t.own && !t.inflow && only == null) own += t.paise;
    }
    // A refund never takes a category below zero.
    byCat = [
      for (final MapEntry(key: c, value: (p, n)) in cats.entries)
        if (c != null && p > 0) (name: c.full, cat: c, paise: p, n: n),
    ]..sort((a, b) => b.paise - a.paise);
    final (up, un) = cats[null] ?? (0, 0);
    unc = up > 0 ? (name: 'Not categorised', cat: null, paise: up, n: un) : null;
    this.payees = [
      for (final MapEntry(key: name, value: (c, p, n)) in payees.entries)
        if (p > 0) (name: name, cat: c, paise: p, n: n),
    ]..sort((a, b) => b.paise - a.paise);
    spent = total > 0 ? total : 0;
  }

  /// Categorised spend and payees, biggest first.
  late final List<Bar> byCat, payees;
  late final Bar? unc;
  late final int spent;
  int payments = 0, inflow = 0, inCount = 0, own = 0, refunds = 0;
}

class Store extends ChangeNotifier {
  Store(this.db, {DateTime Function()? clock}) : now = clock ?? DateTime.now {
    db.execute('PRAGMA foreign_keys = ON');
    _migrate();
    _loadCats();
    purgeRaw();
  }

  /// The schema this build writes; older ledgers (and backups) are upgraded.
  static const version = 6;

  void _migrate() {
    if (db.userVersion == 0) {
      db.execute(_schema);
      db.userVersion = 1;
    }
    if (db.userVersion == 1) {
      _tx(() {
        db.execute(_v2);
        _seedCats();
      });
      db.userVersion = 2;
    }
    if (db.userVersion == 2) {
      db.execute(_v3);
      db.userVersion = 3;
    }
    if (db.userVersion == 3) {
      _tx(() {
        db.execute(_v4);
        final builtIn = {for (final b in builtInBanks) b.name};
        for (final r in db.select('SELECT bank, MAX(enabled) on_, group_concat(code) codes FROM senders GROUP BY bank')) {
          final name = r['bank'] as String, on = r['on_'] == 1;
          if (builtIn.contains(name)) {
            if (!on) _setBankOn(name, false); // a bank you switched off stays off
          } else {
            _insert('banks', {'name': name, 'enabled': on ? 1 : 0, 'words': r['codes']}); // one you added
          }
        }
        db.execute('DROP TABLE senders; ALTER TABLE accounts DROP COLUMN tracked;');
      });
      db.userVersion = 4;
    }
    if (db.userVersion == 4) {
      db.execute(_v5);
      db.userVersion = 5;
    }
    if (db.userVersion == 5) {
      db.execute(_v6);
      db.userVersion = 6;
    }
  }

  void _seedCats() {
    for (final (i, c) in builtInCats.indexed) {
      _insert('categories', {'key': c.key, 'short': c.short, 'full': c.full, 'style': c.key, 'icon': builtInIcons[c.key], 'sort': i});
    }
  }

  void _loadCats() {
    cats = [
      for (final r in db.select('SELECT * FROM categories ORDER BY sort, rowid'))
        () {
          final style = builtInCats.firstWhere((c) => c.key == r['style'], orElse: () => other);
          return Cat(r['key'] as String, r['short'] as String, r['full'] as String,
              catIcons[r['icon']] ?? Icons.label_outline_rounded, style.light, style.dark);
        }(),
    ];
  }

  /// WAL plus a busy timeout: an SMS arriving with the app closed is filed
  /// from a second connection.
  factory Store.open(String path) =>
      Store(sqlite3.open(path)..execute('PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;'));
  factory Store.memory({DateTime Function()? clock}) => Store(sqlite3.openInMemory(), clock: clock);

  final Database db;
  final DateTime Function() now;

  @override
  void dispose() {
    db.close();
    super.dispose();
  }

  T _tx<T>(T Function() body) {
    db.execute('SAVEPOINT tx');
    try {
      final r = body();
      db.execute('RELEASE tx');
      return r;
    } catch (_) {
      db.execute('ROLLBACK TO tx');
      db.execute('RELEASE tx');
      rethrow;
    }
  }

  int _insert(String table, Map<String, Object?> row) {
    db.execute(
      'INSERT INTO $table (${row.keys.join(', ')}) VALUES (${List.filled(row.length, '?').join(', ')})',
      [...row.values],
    );
    return db.lastInsertRowId;
  }

  void _upsert(String table, Map<String, Object?> row) => db.execute(
        'INSERT INTO $table (${row.keys.join(', ')}) VALUES (${List.filled(row.length, '?').join(', ')}) '
        'ON CONFLICT (id) DO UPDATE SET ${row.keys.map((c) => '$c = excluded.$c').join(', ')}',
        [...row.values],
      );

  int _count(String sql, [List<Object?> args = const []]) => db.select(sql, args).first.columnAt(0) as int? ?? 0;

  // -------------------------------------------------------------------------
  // Settings

  String? _get(String key) => db.select('SELECT value FROM settings WHERE key = ?', [key]).firstOrNull?['value'] as String?;

  void _put(String key, Object value) => db.execute(
      'INSERT INTO settings VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value', [key, '$value']);

  void _set(String key, Object value) {
    _put(key, value);
    notifyListeners();
  }

  bool get onboarded => _get('onboarded') == '1';
  bool get smsOn => _get('sms') == '1';

  /// SMS access was taken away (in Android settings).
  void smsOff() => _set('sms', 0);

  /// Whether the SMS receiver should pass anything on: after onboarding,
  /// with SMS on.
  bool get captureOn => onboarded && smsOn;

  /// The banks SMS are matched against: built-in ones, then ones you added.
  List<Bank> get banks => [
        ...builtInBanks,
        for (final r in db.select('SELECT name, words FROM banks WHERE words IS NOT NULL ORDER BY rowid'))
          () {
            final words = [for (final w in (r['words'] as String).split(',')) if (w.trim().isNotEmpty) w.trim()];
            return Bank(r['name'] as String, [for (final w in words) w.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '')], words);
          }(),
      ];

  Set<String> get _banksOff => {for (final r in db.select('SELECT name FROM banks WHERE enabled = 0')) r['name'] as String};

  /// Where the next inbox read starts: a little before the newest SMS read
  /// so far, as the inbox isn't always written in order.
  DateTime get inboxFrom => DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(_get('seen') ?? '') ?? int.tryParse(_get('since') ?? '') ?? 0)
      .subtract(const Duration(minutes: 10));

  bool get reminderOn => _get('remind') != '0';
  set reminderOn(bool v) => _set('remind', v ? 1 : 0);

  TimeOfDay get reminderAt {
    final [h, m] = (_get('remindAt') ?? '21:30').split(':').map(int.parse).toList();
    return TimeOfDay(hour: h, minute: m);
  }

  set reminderAt(TimeOfDay t) => _set('remindAt', '${t.hour}:${t.minute}');

  /// File payees with a remembered category on capture: 0 taps.
  bool get autoFile => _get('autoFile') == '1';
  set autoFile(bool v) => _set('autoFile', v ? 1 : 0);

  /// Settings › Glass effects: off = solid surfaces, no blur.
  bool get glass => _get('glass') != '0';
  set glass(bool v) => _set('glass', v ? 1 : 0);

  bool get keepRaw => _get('keepRaw') != '0';
  set keepRaw(bool v) {
    _put('keepRaw', v ? 1 : 0);
    purgeRaw();
    notifyListeners();
  }

  /// Raw SMS go after 30 days, or at once with keepRaw off. Unreadable ones
  /// stay until filled in: the SMS is all there is.
  void purgeRaw() => db.execute(
        "DELETE FROM sms WHERE at < ? AND id NOT IN (SELECT sms_id FROM txns WHERE status = 'unread' AND sms_id IS NOT NULL)",
        [keepRaw ? _ms(now().subtract(const Duration(days: 30))) : 1 << 62],
      );

  // -------------------------------------------------------------------------
  // Capture

  /// Onboarding's last step: the banks found (those named in [off] switched
  /// off) and their accounts, then the inbox imported from [since] on.
  void finishOnboarding({
    required bool sms,
    required DateTime since,
    List<Found> found = const [],
    Set<String> off = const {},
    Iterable<Sms> inbox = const [],
  }) {
    _tx(() {
      _addFound(found, off);
      _put('since', _ms(since));
      _put('sms', sms ? 1 : 0);
      _put('onboarded', 1);
      _ingestAll(inbox);
    });
    notifyListeners();
  }

  /// SMS access is back: catch up on the inbox since the last read.
  void turnOnSms(Iterable<Sms> inbox) {
    _put('sms', 1);
    catchUp(inbox);
  }

  /// Files whatever in [inbox] is new. Reading overlapping stretches is fine:
  /// an SMS already read is skipped.
  void catchUp(Iterable<Sms> inbox) {
    _tx(() {
      _addFound(scanInbox(inbox, banks), const {});
      _ingestAll(inbox);
    });
    notifyListeners();
  }

  /// Every account up front, so a transfer to one whose own SMS comes later
  /// still reads as a transfer. Banks named in [off] are switched off.
  void _addFound(List<Found> found, Set<String> off) {
    for (final f in found) {
      if (off.contains(f.bank.name)) _setBankOn(f.bank.name, false);
      for (final l in f.accounts) {
        db.execute('INSERT OR IGNORE INTO accounts (bank, last4) VALUES (?, ?)', [f.bank.name, l]);
      }
    }
  }

  void _ingestAll(Iterable<Sms> inbox) {
    final sorted = [...inbox]..sort((a, b) => a.at.compareTo(b.at));
    for (final s in sorted) {
      _ingest(s.sender, s.body, s.at);
    }
    if (sorted.isNotEmpty && _ms(sorted.last.at) > (int.tryParse(_get('seen') ?? '') ?? 0)) {
      _put('seen', _ms(sorted.last.at));
    }
  }

  /// Reads one SMS. Returns the new transaction's id, or null when it isn't
  /// a payment, names no bank (or one switched off), or was seen before.
  int? ingest(String sender, String body, DateTime at) {
    final id = _tx(() => _ingest(sender, body, at));
    if (id != null) notifyListeners();
    return id;
  }

  int? _ingest(String header, String body, DateTime at) {
    // A phone number is kept as its last 10 digits, however the carrier wrote it.
    final digits = header.replaceAll(RegExp(r'[\s-]'), '');
    header = RegExp(r'^\+?\d{10,}$').hasMatch(digits) ? digits.substring(digits.length - 10) : header.trim().toUpperCase();
    if (_ms(at) < (int.tryParse(_get('since') ?? '') ?? 0)) return null;
    final b = bankOf(header, body, banks);
    if (b == null || _banksOff.contains(b.name)) return null;
    final raw = parseSms(body);
    if (raw == null) return null;
    final f = raw.complete ? null : db.select('SELECT * FROM formats WHERE shape = ?', [smsShape(body)]).firstOrNull;
    final p = f == null ? raw : raw.taught(f['inflow'] == 1, f['name'] as String);
    // Seen before: same sender and text within a day. Not an exact time
    // match: the receiver and the inbox can stamp one SMS a moment apart.
    if (db.select('SELECT 1 FROM sms WHERE sender = ? AND body = ? AND ABS(at - ?) < ?',
        [header, body, _ms(at), const Duration(days: 1).inMilliseconds]).isNotEmpty) {
      return null;
    }
    final bank = b.name, dupOnly = b.dupOnly;

    Row? acct(String last4) =>
        db.select('SELECT * FROM accounts WHERE last4 = ? ORDER BY bank = ? DESC LIMIT 1', [last4, bank]).firstOrNull;
    var a = p.last4.isEmpty ? null : acct(p.last4);
    if (a == null && p.last4.isNotEmpty && !dupOnly) {
      _insert('accounts', {'bank': bank, 'last4': p.last4});
      a = acct(p.last4);
    }

    // A second masked account that is also ours: a transfer, never spend.
    final own = p.inflow == null ? null : p.accts.skip(1).where((l) => l != p.last4).map(acct).nonNulls.firstOrNull;
    if (own == null && !p.complete && dupOnly) return null;

    // Same amount and direction within minutes, and no UPI Ref that says otherwise.
    final twin = p.inflow == null
        ? null
        : db.select(
            "SELECT id FROM txns WHERE source = 'sms' AND paise = ? AND inflow = ? AND ABS(at - ?) <= ? "
            "AND status NOT IN ('dup', 'unread') AND (ref = ? OR ref = '' OR ? = '') ORDER BY ABS(at - ?) LIMIT 1",
            [p.paise, p.inflow! ? 1 : 0, _ms(at), _dupWindow.inMilliseconds, p.ref, p.ref, _ms(at)],
          ).firstOrNull;
    // ponytail: a wallet SMS that beats the bank's is dropped, not held for
    // matching; the bank SMS is the source either way.
    if (twin == null && dupOnly) return null;

    final row = <String, Object?>{
      'paise': p.paise,
      'at': _ms(at),
      'inflow': p.inflow == true ? 1 : 0,
      'vpa': p.vpa,
      'ref': p.ref,
      'sender': header,
      'account_id': a?['id'],
      'sms_id': _insert('sms', {'sender': header, 'body': body, 'at': _ms(at)}),
      'dup_of': twin?['id'],
    };
    if (own != null) {
      return _insert('txns', {
        ...row,
        'status': twin == null ? 'ignored' : 'dup',
        'own': 1,
        'name': '${p.inflow! ? 'From' : 'To'} ${_acct(own)}',
      });
    }
    if (!p.complete) return _insert('txns', {...row, 'status': 'unread', 'name': 'Payee not found'});

    final parsedName = p.name.isNotEmpty ? p.name : payeeFromVpa(p.vpa);
    final (mid, name, rule, isYou) =
        _merchant(p.vpa.isNotEmpty ? p.vpa.toLowerCase() : 'name:${parsedName.toLowerCase()}', parsedName);
    final (status, cat) = twin != null
        ? ('dup', null)
        : isYou
            ? ('ignored', null)
            : _fresh(p.inflow!, rule);
    return _insert('txns', {...row, 'status': status, 'cat': cat, 'name': name, 'merchant_id': mid, 'own': isYou ? 1 : 0});
  }

  /// Status for a payment nobody has looked at yet.
  (String, String?) _fresh(bool inflow, String? rule) => inflow
      ? ('credit', null)
      : rule != null && autoFile
          ? ('filed', rule)
          : ('needs', null);

  /// (id, display name, remembered category, is you); created on first sight.
  (int, String, String?, bool) _merchant(String key, String name) {
    db.execute('INSERT INTO merchants (key, name) VALUES (?, ?) ON CONFLICT (key) DO NOTHING', [key, name]);
    final r = db.select('SELECT id, name, rule_cat, own FROM merchants WHERE key = ?', [key]).first;
    return (r['id'] as int, r['name'] as String, r['rule_cat'] as String?, r['own'] == 1);
  }

  // -------------------------------------------------------------------------
  // Reading

  static const _select = '''
SELECT t.*, a.bank, a.last4, a.alias, m.rule_cat, s.body AS sms_body,
  (SELECT group_concat(tag, char(31)) FROM tags WHERE txn_id = t.id) AS tag_list,
  (SELECT group_concat(cat || ':' || paise) FROM splits WHERE txn_id = t.id) AS split_list
FROM txns t
LEFT JOIN accounts a ON a.id = t.account_id
LEFT JOIN merchants m ON m.id = t.merchant_id
LEFT JOIN sms s ON s.id = t.sms_id''';

  List<Txn> _txns(String where, [List<Object?> args = const []]) =>
      [for (final r in db.select('$_select $where', args)) _txn(r)];

  Txn _txn(Row r) {
    final id = r['id'] as int, mid = r['merchant_id'] as int?;
    final status = TxnStatus.values.byName(r['status'] as String);
    final source = r['source'] as String, bank = r['bank'] as String?, body = r['sms_body'] as String?;
    final name = r['name'] as String, vpa = r['vpa'] as String;
    final needs = status == TxnStatus.needs;
    return Txn(
      id: id,
      name: name,
      paise: r['paise'] as int,
      when: DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
      vpa: vpa,
      ref: r['ref'] as String,
      sender: r['sender'] as String,
      note: r['note'] as String,
      source: source,
      acct: switch (source) {
        'cash' => 'Cash',
        'other' => bank == null ? 'Other account' : _acct(r),
        _ => bank == null ? '' : _acct(r),
      },
      cat: catOf(r['cat'] as String?),
      status: status,
      inflow: r['inflow'] == 1,
      own: r['own'] == 1,
      reimb: r['reimb'] == 1,
      merchantId: mid,
      accountId: r['account_id'] as int?,
      dupOf: r['dup_of'] as int?,
      refundOf: r['refund_of'] as int?,
      creditKind: r['credit_kind'] as String?,
      sms: body == null ? null : (parseSms(body)?.marked ?? body),
      tags: {...?(r['tag_list'] as String?)?.split('\x1f')},
      splits: [
        for (final part in (r['split_list'] as String?)?.split(',') ?? const <String>[])
          (catOf(part.substring(0, part.lastIndexOf(':')))!, int.parse(part.substring(part.lastIndexOf(':') + 1))),
      ]..sort((a, b) => b.$2 - a.$2),
      newPayee: needs &&
          mid != null &&
          db.select("SELECT 1 FROM txns WHERE merchant_id = ? AND status = 'filed' AND id <> ? LIMIT 1", [mid, id]).isEmpty,
      sugg: needs ? _suggest(id, mid, '$vpa $name', r['rule_cat'] as String?) : const [],
    );
  }

  /// Up to two categories: this payee's history, its remembered rule, a
  /// guess from its name, then what you file most.
  List<Sugg> _suggest(int id, int? mid, String payee, String? rule) {
    final out = <Sugg>[];
    void add(String? key, String why) {
      final c = catOf(key);
      if (c != null && out.length < 2 && !out.any((s) => s.cat == c)) out.add(Sugg(c, why));
    }

    if (mid != null) {
      for (final r in db.select(
          "SELECT cat, COUNT(*) n FROM txns WHERE merchant_id = ? AND status = 'filed' AND id <> ? "
          'GROUP BY cat ORDER BY n DESC, MAX(at) DESC LIMIT 2',
          [mid, id])) {
        add(r['cat'] as String, '${r['n']}×');
      }
    }
    add(rule, 'saved');
    add(guessCat(payee), 'guess');
    for (final r in db.select(
        "SELECT cat FROM txns WHERE status = 'filed' AND at >= ? GROUP BY cat ORDER BY COUNT(*) DESC LIMIT 2",
        [_ms(now().subtract(const Duration(days: 90)))])) {
      add(r['cat'] as String, 'often');
    }
    return out;
  }

  Txn? txn(int id) => _txns('WHERE t.id = ?', [id]).firstOrNull;

  /// Everything waiting on you: spends without a category first, newest
  /// first; possible duplicates and unreadable SMS last.
  List<Txn> queue() => _txns("WHERE t.status IN ('needs', 'dup', 'unread') "
      "ORDER BY CASE t.status WHEN 'needs' THEN 0 WHEN 'dup' THEN 1 ELSE 2 END, t.at DESC");

  int get pendingCount => _count("SELECT COUNT(*) FROM txns WHERE status IN ('needs', 'dup', 'unread')");

  /// Every row in [from, to), newest first.
  List<Txn> between(DateTime from, DateTime to) =>
      _txns('WHERE t.at >= ? AND t.at < ? ORDER BY t.at DESC', [_ms(from), _ms(to)]);

  bool get isEmpty => _count('SELECT COUNT(*) FROM txns') == 0;

  DateTime? get lastCapture {
    final v = db.select("SELECT MAX(at) FROM txns WHERE source = 'sms'").first.columnAt(0) as int?;
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  /// Accounts seen or added: "HDFC ••1111 · Salary".
  List<String> get accounts => [for (final r in db.select('SELECT * FROM accounts ORDER BY id')) _acct(r)];

  /// Remembered payees, and one as an example: "Swiggy → Food & dining".
  (int, String?) get rules {
    final r = db.select('SELECT name, rule_cat FROM merchants WHERE rule_cat IS NOT NULL ORDER BY id LIMIT 1').firstOrNull;
    return (
      _count('SELECT COUNT(*) FROM merchants WHERE rule_cat IS NOT NULL'),
      r == null ? null : '${r['name']} → ${catOf(r['rule_cat'] as String)!.full}',
    );
  }

  /// Every tag, most used first.
  List<String> get tagsInUse =>
      [for (final r in db.select('SELECT tag FROM tags GROUP BY tag ORDER BY COUNT(*) DESC')) r['tag'] as String];

  /// The payment a credit probably refunds: same payee, same amount, earlier,
  /// not refunded yet.
  Txn? refundMatch(Txn t) => !t.inflow || t.merchantId == null || t.refundOf != null
      ? null
      : _txns(
          "WHERE t.merchant_id = ? AND t.inflow = 0 AND t.status IN ('needs', 'filed') AND t.paise = ? "
          'AND t.at < ? AND t.at >= ? AND NOT EXISTS (SELECT 1 FROM txns r WHERE r.refund_of = t.id) '
          'ORDER BY t.at DESC LIMIT 1',
          [t.merchantId, t.paise, _ms(t.when), _ms(t.when.subtract(_refundWindow))],
        ).firstOrNull;

  // -------------------------------------------------------------------------
  // Changes. Callers that offer Undo take an undoPoint first.

  /// Puts [id] back as it is now: the row, its tags, its raw SMS, its
  /// payee's name and rule, and the payee's other payments waiting for a
  /// category (filing with remember files those too). For an unreadable SMS:
  /// its format, and the others in it (filling in with learn fills those).
  VoidCallback undoPoint(int id) {
    final t = db.select('SELECT * FROM txns WHERE id = ?', [id]).firstOrNull;
    if (t == null) return () {};
    final shape = t['status'] == 'unread' ? _shapeOf(id) : null;
    final format = shape == null ? null : db.select('SELECT * FROM formats WHERE shape = ?', [shape]).firstOrNull;
    final others = [
      ...db.select("SELECT * FROM txns WHERE merchant_id = ? AND status = 'needs' AND id <> ?", [t['merchant_id'], id]),
      if (shape != null)
        for (final o in _unreadLike(shape, id)) db.select('SELECT * FROM txns WHERE id = ?', [o]).first,
    ];
    final tags = [for (final r in db.select('SELECT tag FROM tags WHERE txn_id = ?', [id])) r['tag'] as String];
    final splits = db.select('SELECT * FROM splits WHERE txn_id = ?', [id]).toList();
    final sms = t['sms_id'] == null ? null : db.select('SELECT * FROM sms WHERE id = ?', [t['sms_id']]).firstOrNull;
    final m = t['merchant_id'] == null ? null : db.select('SELECT * FROM merchants WHERE id = ?', [t['merchant_id']]).first;
    return () {
      _tx(() {
        if (sms != null) _upsert('sms', sms);
        if (m != null) _upsert('merchants', m);
        _upsert('txns', t);
        for (final o in others) {
          _upsert('txns', o);
          db.execute('DELETE FROM splits WHERE txn_id = ?', [o['id']]);
        }
        if (shape != null) {
          db.execute('DELETE FROM formats WHERE shape = ?', [shape]);
          if (format != null) db.execute('INSERT INTO formats VALUES (?, ?, ?)', [shape, format['inflow'], format['name']]);
        }
        _setTags(id, tags);
        db.execute('DELETE FROM splits WHERE txn_id = ?', [id]);
        for (final s in splits) {
          _insert('splits', s);
        }
      });
      notifyListeners();
    };
  }

  void _setTags(int id, Iterable<String> tags) {
    db.execute('DELETE FROM tags WHERE txn_id = ?', [id]);
    for (final tag in tags) {
      db.execute('INSERT INTO tags VALUES (?, ?)', [id, tag]);
    }
  }

  void _update(int id, String set, [List<Object?> args = const []]) {
    db.execute('UPDATE txns SET $set WHERE id = ?', [...args, id]);
    notifyListeners();
  }

  /// Files a spend under one category (undoing any split). [remember] makes
  /// [cat] this payee's 1-tap action and files their other payments still
  /// waiting for a category; false forgets it. Null fields stay as they are.
  /// Returns how many other payments were filed.
  int file(int id, Cat cat, {bool remember = true, String? note, Set<String>? tags, bool? reimb}) {
    final more = _tx(() {
      db.execute("UPDATE txns SET status = 'filed', cat = ? WHERE id = ?", [cat.key, id]);
      db.execute('DELETE FROM splits WHERE txn_id = ?', [id]);
      _details(id, note, tags, reimb);
      db.execute('UPDATE merchants SET rule_cat = ? WHERE id = (SELECT merchant_id FROM txns WHERE id = ?)',
          [remember ? cat.key : null, id]);
      if (!remember) return 0;
      db.execute(
          "UPDATE txns SET status = 'filed', cat = ? WHERE status = 'needs' "
          'AND merchant_id = (SELECT merchant_id FROM txns WHERE id = ?)',
          [cat.key, id]);
      return db.updatedRows;
    });
    notifyListeners();
    return more;
  }

  /// Back to waiting for a category: a notification's Undo. [rule] is the
  /// payee's rule as it was before the filing.
  void unfile(int id, {String? rule}) {
    _tx(() {
      db.execute("UPDATE txns SET status = 'needs', cat = NULL WHERE id = ? AND status = 'filed'", [id]);
      db.execute('DELETE FROM splits WHERE txn_id = ?', [id]);
      db.execute('UPDATE merchants SET rule_cat = ? WHERE id = (SELECT merchant_id FROM txns WHERE id = ?)', [rule, id]);
    });
    notifyListeners();
  }

  /// The remembered category of [id]'s payee.
  String? ruleOf(int id) => db.select(
      'SELECT m.rule_cat FROM txns t JOIN merchants m ON m.id = t.merchant_id WHERE t.id = ?', [id]).firstOrNull?['rule_cat'] as String?;

  /// Files a spend across categories. [parts] are (category, paise) and
  /// must add up to the payment; a single part is plain filing. The payee's
  /// rule is left alone: a rule is one category.
  void split(int id, List<(Cat, int)> parts, {String? note, Set<String>? tags, bool? reimb}) {
    final paise = _count('SELECT paise FROM txns WHERE id = ?', [id]);
    if (parts.isEmpty ||
        parts.any((p) => p.$2 <= 0) ||
        parts.map((p) => p.$1).toSet().length != parts.length ||
        parts.fold(0, (s, p) => s + p.$2) != paise) {
      throw ArgumentError('Shares must be positive, one per category, and add up to $paise paise');
    }
    final main = parts.reduce((a, b) => b.$2 > a.$2 ? b : a).$1;
    _tx(() {
      db.execute("UPDATE txns SET status = 'filed', cat = ? WHERE id = ?", [main.key, id]);
      db.execute('DELETE FROM splits WHERE txn_id = ?', [id]);
      if (parts.length > 1) {
        for (final (c, p) in parts) {
          _insert('splits', {'txn_id': id, 'cat': c.key, 'paise': p});
        }
      }
      _details(id, note, tags, reimb);
    });
    notifyListeners();
  }

  /// Files a spend under every category in [cs], the payment shared equally
  /// (the first takes the odd paise). One category is [file]; several leave
  /// the payee's rule alone, as [split] does. Returns how many other
  /// payments [file] filed.
  int fileAll(int id, List<Cat> cs, {bool remember = true, String? note, Set<String>? tags, bool? reimb}) {
    if (cs.length == 1) return file(id, cs.single, remember: remember, note: note, tags: tags, reimb: reimb);
    final paise = _count('SELECT paise FROM txns WHERE id = ?', [id]);
    // ponytail: under a paisa a share, the extra categories are dropped.
    final n = math.min(cs.length, paise);
    split(id, [for (var i = 0; i < n; i++) (cs[i], paise ~/ n + (i == 0 ? paise % n : 0))],
        note: note, tags: tags, reimb: reimb);
    return 0;
  }

  /// Note, tags and reimbursable, keeping the category or split as it is.
  void saveDetails(int id, {String? note, Set<String>? tags, bool? reimb}) {
    _tx(() => _details(id, note, tags, reimb));
    notifyListeners();
  }

  void _details(int id, String? note, Set<String>? tags, bool? reimb) {
    db.execute('UPDATE txns SET note = COALESCE(?, note), reimb = COALESCE(?, reimb) WHERE id = ?',
        [note?.trim(), reimb == null ? null : (reimb ? 1 : 0), id]);
    if (tags != null) _setTags(id, tags);
  }

  /// Not an expense, or a credit that isn't income: kept, never counted.
  void ignore(int id) => _update(id, "status = 'ignored'");

  /// Corrects the payee, for this row and every later one from them.
  void rename(int id, String name) {
    name = name.trim();
    if (name.isEmpty) return;
    _tx(() {
      db.execute('UPDATE txns SET name = ? WHERE id = ?', [name, id]);
      db.execute('UPDATE merchants SET name = ? WHERE id = (SELECT merchant_id FROM txns WHERE id = ?)', [name, id]);
    });
    notifyListeners();
  }

  /// Same payment, twice: drop the second SMS's row; the first stays the source.
  void mergeDup(int id) {
    db.execute("DELETE FROM txns WHERE id = ? AND status = 'dup'", [id]);
    notifyListeners();
  }

  /// Two real payments after all.
  void keepBoth(int id) {
    final r = db.select('SELECT t.inflow, t.own, m.rule_cat FROM txns t LEFT JOIN merchants m ON m.id = t.merchant_id '
        'WHERE t.id = ?', [id]).firstOrNull;
    if (r == null) return;
    final (status, cat) = r['own'] == 1 ? ('ignored', null) : _fresh(r['inflow'] == 1, r['rule_cat'] as String?);
    _update(id, 'status = ?, cat = ?, dup_of = NULL', [status, cat]);
  }

  /// Links a credit to the payment it refunds; totals net it out.
  void linkRefund(int id, int paymentId) => _update(id, "refund_of = ?, credit_kind = 'refund'", [paymentId]);

  /// moneyBack (a split or repayment) or income.
  void explainCredit(int id, String kind) => _update(id, 'credit_kind = ?, refund_of = NULL', [kind]);

  /// The gaps the parser left in an unreadable SMS. Several [cats] share
  /// the payment equally. [learn]: SMS in this format are read this way from
  /// now on, and the unreadable ones waiting now are filled in the same.
  /// Returns how many of those.
  int fillUnread(int id, {required bool out, required String name, List<Cat> cats = const [], bool learn = false}) {
    name = name.trim();
    final ids = _tx(() {
      final shape = learn ? _shapeOf(id) : null;
      if (shape != null) db.execute('INSERT OR REPLACE INTO formats VALUES (?, ?, ?)', [shape, out ? 0 : 1, name]);
      final ids = [id, if (shape != null) ..._unreadLike(shape, id)];
      final (mid, _, _, _) = _merchant('name:${name.toLowerCase()}', name);
      for (final i in ids) {
        db.execute('UPDATE txns SET status = ?, inflow = ?, name = ?, cat = ?, merchant_id = ? WHERE id = ?', [
          out ? (cats.isEmpty ? 'needs' : 'filed') : 'credit',
          out ? 0 : 1,
          name,
          out ? cats.firstOrNull?.key : null,
          mid,
          i,
        ]);
      }
      return ids;
    });
    if (out && cats.length > 1) {
      for (final i in ids) {
        fileAll(i, cats);
      }
    }
    notifyListeners();
    return ids.length - 1;
  }

  /// The smsShape of [id]'s SMS; null once the raw SMS is gone.
  String? _shapeOf(int id) {
    final body = db.select('SELECT s.body FROM txns t JOIN sms s ON s.id = t.sms_id WHERE t.id = ?', [id]).firstOrNull;
    return body == null ? null : smsShape(body['body'] as String);
  }

  /// Unreadable rows other than [id] whose SMS has [shape].
  // ponytail: shapes every unread SMS in Dart; there are only ever a handful.
  List<int> _unreadLike(String shape, int id) => [
        for (final r in db.select(
            "SELECT t.id, s.body FROM txns t JOIN sms s ON s.id = t.sms_id WHERE t.status = 'unread' AND t.id <> ?", [id]))
          if (smsShape(r['body'] as String) == shape) r['id'] as int,
      ];

  /// Deletes a row and its raw SMS.
  void deleteTxn(int id) {
    _tx(() {
      final sms = db.select('SELECT sms_id FROM txns WHERE id = ?', [id]).firstOrNull?['sms_id'];
      db.execute('DELETE FROM txns WHERE id = ?', [id]);
      if (sms != null) db.execute('DELETE FROM sms WHERE id = ? AND NOT EXISTS (SELECT 1 FROM txns WHERE sms_id = ?)', [sms, sms]);
    });
    notifyListeners();
  }

  /// A cash or account spend, typed in (a UPI payment the bank sent no SMS
  /// for). [account]: which of yours, if known. Filed as entered; several
  /// [cats] share it equally. Named after [payee], else the note, else the category.
  // ponytail: not matched against SMS; one that turns up late is a second entry.
  int addManual(
      {required int paise,
      required List<Cat> cats,
      required DateTime at,
      bool cash = true,
      int? account,
      String note = '',
      String payee = ''}) {
    final id = _insert('txns', {
      'status': 'filed',
      'paise': paise,
      'at': _ms(at),
      'name': payee.trim().isNotEmpty ? payee.trim() : (note.trim().isEmpty ? cats.first.full : note.trim()),
      'note': payee.trim().isNotEmpty ? note.trim() : '',
      'cat': cats.first.key,
      'source': cash ? 'cash' : 'other',
      'account_id': cash ? null : account,
    });
    if (cats.length > 1) fileAll(id, cats);
    notifyListeners();
    return id;
  }

  /// A typed-in spend, paid in cash or from [account] (null = not listed).
  /// SMS payments keep the account their SMS named.
  void setPaidWith(int id, {required bool cash, int? account}) {
    db.execute("UPDATE txns SET source = ?, account_id = ? WHERE id = ? AND source <> 'sms'",
        [cash ? 'cash' : 'other', cash ? null : account, id]);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Settings: accounts, senders, categories, payees, export, check-in

  /// What's stored, for the privacy page.
  ({int txns, int sms, int payees}) get counts => (
        txns: _count('SELECT COUNT(*) FROM txns'),
        sms: _count('SELECT COUNT(*) FROM sms'),
        payees: _count('SELECT COUNT(*) FROM merchants'),
      );

  /// Every account seen or added. They only label payments and spot
  /// transfers between your own accounts; they don't decide what's read.
  List<Account> get allAccounts => [
        for (final r in db.select('SELECT * FROM accounts ORDER BY id'))
          (
            id: r['id'] as int,
            bank: r['bank'] as String,
            last4: r['last4'] as String,
            alias: r['alias'] as String,
            label: _acct(r),
          ),
      ];

  /// One of yours with no bank SMS (another bank, a wallet): transfers to it
  /// stop counting as spend. Adding one that's already there names it.
  void addAccount(String bank, String last4, [String alias = '']) {
    db.execute(
      "INSERT INTO accounts (bank, last4, alias) VALUES (?, ?, ?) "
      "ON CONFLICT (bank, last4) DO UPDATE SET alias = excluded.alias WHERE excluded.alias <> ''",
      [bank.trim(), last4.trim(), alias.trim()],
    );
    notifyListeners();
  }

  /// Names an account ('' clears it), to tell two at one bank apart.
  void setAlias(int id, String alias) {
    db.execute('UPDATE accounts SET alias = ? WHERE id = ?', [alias.trim(), id]);
    notifyListeners();
  }

  /// Every bank SMS are matched against, whether it's read, and the
  /// accounts seen for it.
  List<({Bank bank, bool on, bool added, List<String> accounts})> get bankList {
    final off = _banksOff;
    final added = {for (final r in db.select('SELECT name FROM banks WHERE words IS NOT NULL')) r['name'] as String};
    final seen = <String, List<String>>{};
    for (final r in db.select('SELECT bank, last4 FROM accounts ORDER BY id')) {
      seen.putIfAbsent(r['bank'] as String, () => []).add(r['last4'] as String);
    }
    return [
      for (final b in banks)
        (bank: b, on: !off.contains(b.name), added: added.contains(b.name), accounts: seen[b.name] ?? const []),
    ];
  }

  int get banksOn => banks.length - _banksOff.length;

  void _setBankOn(String name, bool on) => db.execute(
      'INSERT INTO banks (name, enabled) VALUES (?, ?) ON CONFLICT (name) DO UPDATE SET enabled = excluded.enabled',
      [name, on ? 1 : 0]);

  /// Off: SMS from or naming this bank are dropped.
  void setBankOn(String name, bool on) {
    _setBankOn(name, on);
    notifyListeners();
  }

  /// A bank the built-in list doesn't have, known by [words]: names in its
  /// SMS, its sender ID, or a phone number ('Saraswat, SARBNK').
  void addBank(String name, String words) {
    name = name.trim();
    if (name.isEmpty || words.trim().isEmpty) return;
    db.execute(
      'INSERT INTO banks (name, enabled, words) VALUES (?, 1, ?) ON CONFLICT (name) DO UPDATE SET enabled = 1, words = excluded.words',
      [name, words.trim()],
    );
    notifyListeners();
  }

  /// Removes a bank you added.
  void removeBank(String name) {
    db.execute('DELETE FROM banks WHERE name = ? AND words IS NOT NULL', [name]);
    notifyListeners();
  }

  /// Adds a category ([key] null) or changes one. The grid shows a short
  /// name: the first word of a long one.
  void saveCat({String? key, required String name, required Cat style, required String icon}) {
    name = name.trim();
    if (name.isEmpty) return;
    final short = name.length <= 10 ? name : name.split(' ').first;
    if (key == null) {
      _insert('categories', {
        'key': 'c${now().microsecondsSinceEpoch}',
        'short': short,
        'full': name,
        'style': style.key,
        'icon': icon,
        'sort': _count('SELECT MAX(sort) + 1 FROM categories'),
      });
    } else {
      db.execute('UPDATE categories SET short = ?, full = ?, style = ?, icon = ? WHERE key = ?', [short, name, style.key, icon, key]);
    }
    _loadCats();
    notifyListeners();
  }

  /// Payments (whole or a share) and payee rules filed under [c].
  ({int payments, int rules}) catUsage(Cat c) => (
        payments: _count('SELECT COUNT(*) FROM (SELECT id FROM txns WHERE cat = ? UNION SELECT txn_id FROM splits WHERE cat = ?)',
            [c.key, c.key]),
        rules: _count('SELECT COUNT(*) FROM merchants WHERE rule_cat = ?', [c.key]),
      );

  /// Deletes [c]. Its payments, split shares and payee rules move to [to];
  /// a split that already has [to] merges the two shares. Other can't go:
  /// unknown categories fall back to it.
  void deleteCat(Cat c, Cat to) {
    if (c.key == 'other' || c == to) throw ArgumentError("Other stays, and a category can't move into itself");
    _tx(() {
      db.execute(
        'UPDATE splits SET paise = paise + (SELECT d.paise FROM splits d WHERE d.txn_id = splits.txn_id AND d.cat = ?) '
        'WHERE cat = ? AND txn_id IN (SELECT txn_id FROM splits WHERE cat = ?)',
        [c.key, to.key, c.key],
      );
      db.execute('DELETE FROM splits WHERE cat = ? AND txn_id IN (SELECT txn_id FROM splits WHERE cat = ?)', [c.key, to.key]);
      db.execute('UPDATE splits SET cat = ? WHERE cat = ?', [to.key, c.key]);
      // A split down to one share is plain filing.
      db.execute('DELETE FROM splits WHERE txn_id IN (SELECT txn_id FROM splits GROUP BY txn_id HAVING COUNT(*) = 1)');
      db.execute('UPDATE txns SET cat = ? WHERE cat = ?', [to.key, c.key]);
      db.execute('UPDATE txns SET cat = (SELECT s.cat FROM splits s WHERE s.txn_id = txns.id ORDER BY s.paise DESC LIMIT 1) '
          'WHERE id IN (SELECT txn_id FROM splits)');
      db.execute('UPDATE merchants SET rule_cat = ? WHERE rule_cat = ?', [to.key, c.key]);
      db.execute('DELETE FROM categories WHERE key = ?', [c.key]);
    });
    _loadCats();
    notifyListeners();
  }

  /// The stored style and icon names of [c], for the editor.
  (String style, String icon) catLook(Cat c) {
    final r = db.select('SELECT style, icon FROM categories WHERE key = ?', [c.key]).first;
    return (r['style'] as String, r['icon'] as String);
  }

  /// Moves [c] to [index] in the list.
  void moveCat(Cat c, int index) {
    final order = [...cats]..remove(c);
    order.insert(index.clamp(0, order.length), c);
    _tx(() {
      for (final (i, x) in order.indexed) {
        db.execute('UPDATE categories SET sort = ? WHERE key = ?', [i, x.key]);
      }
    });
    _loadCats();
    notifyListeners();
  }

  /// Payees with a remembered category, most used first.
  List<({int id, String name, Cat cat, int count})> get rulesList => [
        for (final r in db.select('SELECT m.id, m.name, m.rule_cat, COUNT(t.id) n FROM merchants m '
            'LEFT JOIN txns t ON t.merchant_id = m.id WHERE m.rule_cat IS NOT NULL GROUP BY m.id ORDER BY n DESC, m.name'))
          (id: r['id'] as int, name: r['name'] as String, cat: catOf(r['rule_cat'] as String)!, count: r['n'] as int),
      ];

  /// null forgets the rule: the next payment asks again.
  void setRule(int merchantId, Cat? cat) {
    db.execute('UPDATE merchants SET rule_cat = ? WHERE id = ?', [cat?.key, merchantId]);
    notifyListeners();
  }

  /// Payees, most paid first. [own]: only those that are you, or only those that aren't.
  List<({int id, String name, String key, int count})> payees({required bool own}) => [
        for (final r in db.select('SELECT m.id, m.name, m.key, COUNT(t.id) n FROM merchants m '
            'LEFT JOIN txns t ON t.merchant_id = m.id WHERE m.own = ? GROUP BY m.id ORDER BY n DESC, m.name', [own ? 1 : 0]))
          (id: r['id'] as int, name: r['name'] as String, key: r['key'] as String, count: r['n'] as int),
      ];

  /// A payee that is you (your own UPI ID elsewhere): payments to and from
  /// it are transfers, never spend. Applies to past payments too.
  void setOwnPayee(int merchantId, bool own) {
    _tx(() {
      db.execute('UPDATE merchants SET own = ? WHERE id = ?', [own ? 1 : 0, merchantId]);
      if (own) {
        db.execute("UPDATE txns SET status = 'ignored', own = 1 WHERE merchant_id = ? AND status IN ('needs', 'filed', 'credit')",
            [merchantId]);
      } else {
        db.execute(
          "UPDATE txns SET own = 0, status = CASE WHEN inflow = 1 THEN 'credit' WHEN cat IS NOT NULL THEN 'filed' ELSE 'needs' END "
          "WHERE merchant_id = ? AND own = 1 AND status = 'ignored'",
          [merchantId],
        );
      }
    });
    notifyListeners();
  }

  /// Every row in [from, to) as CSV, oldest first.
  String csv(DateTime from, DateTime to, {bool Function(Txn)? where}) {
    String cell(Object? v) {
      final s = '${v ?? ''}';
      return RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final rows = [
      ['Date', 'Time', 'Payee', 'Amount', 'Direction', 'Status', 'Category', 'Note', 'Tags', 'Account', 'UPI ID', 'UPI Ref', 'Source'],
      for (final t in between(from, to).reversed.where(where ?? (_) => true))
        [
          '${t.when.year}-${t.when.month.toString().padLeft(2, '0')}-${t.when.day.toString().padLeft(2, '0')}',
          '${t.when.hour.toString().padLeft(2, '0')}:${t.when.minute.toString().padLeft(2, '0')}',
          t.name,
          (t.paise / 100).toStringAsFixed(2),
          t.inflow ? 'in' : 'out',
          t.own ? 'transfer' : t.status.name,
          t.splits.length < 2 ? t.cat?.full : t.splits.map((s) => s.$1.full).join('; '),
          t.note,
          (t.tags.toList()..sort()).join(' '),
          t.acct,
          t.vpa,
          t.ref,
          t.source,
        ],
    ];
    return '${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
  }

  /// The notification for a payment just captured, as Notices.kt posts it;
  /// null for rows that need no nudge (duplicates, own-account transfers).
  /// Known payee: its top categories file in 1 tap. New payee: Add details
  /// or Not an expense. Never more than 3 actions.
  Map<String, Object?>? captureNotice(int id) {
    final t = txn(id);
    if (t == null) return null;
    final amt = rupees(t.paise), open = 'txn:$id';
    switch (t.status) {
      case TxnStatus.needs:
        final known = !t.newPayee && t.sugg.isNotEmpty;
        final g = t.sugg.firstOrNull;
        return {
          'id': id,
          'channel': 'capture',
          'title': '$amt paid to ${t.name}',
          'text': !known
              ? 'New payee. What was it for?'
              : g!.why == 'saved'
                  ? 'Saved as ${g.cat.full}.'
                  : '${g.cat.full} ${g.why.replaceAll('×', '')} time${g.why == '1×' ? '' : 's'} before.',
          'route': open,
          'actions': [
            if (known)
              for (final s in t.sugg.take(2)) {'label': s.cat.full, 'cat': s.cat.key},
            {'label': 'Add details', 'route': open},
            if (!known) {'label': 'Not an expense', 'ignore': true},
          ],
        };
      case TxnStatus.filed:
        return {
          'id': id,
          'channel': 'capture',
          'title': '$amt to ${t.name} · ${t.catLabel}',
          'text': 'Filed by your rule for ${t.name}.',
          'route': open,
          'actions': [
            {'label': 'Undo', 'undo': true, 'rule': ruleOf(id)},
          ],
        };
      case TxnStatus.credit:
        final m = refundMatch(t);
        return {
          'id': id,
          'channel': 'capture',
          'title': '$amt received from ${t.name}',
          'text': m != null ? 'Looks like a refund for ${m.name}. Tap to link it.' : 'Money in. Tap to say what it is.',
          'route': open,
          'actions': const [],
        };
      case TxnStatus.unread:
        return {
          'id': id,
          'channel': 'unread',
          'title': "Couldn't read an SMS from ${t.sender}",
          'text': '${rupees(t.paise)} found, not who it was to. Tap to fill in the gaps.',
          'route': open,
          'actions': const [],
        };
      case TxnStatus.dup || TxnStatus.ignored:
        return null;
    }
  }

  /// The daily check-in notification's words.
  ({bool pending, String title, String text, List<String> lines, String summary}) checkIn() {
    final q = queue(), at = now();
    if (q.isNotEmpty) {
      final needs = q.where((t) => t.status == TxnStatus.needs).toList();
      final hard = q.length - needs.length;
      final total = q.fold(0, (s, t) => s + t.paise);
      final oldest = q.map((t) => t.when).reduce((a, b) => a.isBefore(b) ? a : b);
      final names = q.map((t) => t.name).toSet().toList();
      return (
        pending: true,
        title: '${q.length} payment${q.length == 1 ? '' : 's'} need${q.length == 1 ? 's' : ''} details',
        text: '${names.take(2).join(', ')}${names.length > 2 ? ' and ${names.length - 2} more' : ''} · ${rupees(total, dec: false)}',
        lines: [
          for (final t in needs.take(3)) '${t.name}  ${rupees(t.paise)}',
          if (needs.length > 3) '+${needs.length - 3} more to categorise',
          if (hard > 0) '+$hard need a decision: duplicate or unreadable SMS',
        ],
        summary: sameDay(oldest, at) ? 'All from today' : 'Oldest from ${dow(oldest)}',
      );
    }
    final st = Summary(between(dayStart(at), dayStart(at).add(const Duration(days: 1))), txn);
    return (
      pending: false,
      title: 'All caught up today',
      text: '${st.payments == 0 ? '' : '${st.payments} payment${st.payments == 1 ? '' : 's'} filed · ${rupees(st.spent, dec: false)} out. '}'
          'Paid anything in cash or from another account?',
      lines: const [],
      summary: '',
    );
  }

  // -------------------------------------------------------------------------
  // Backup

  /// Writes the whole ledger to [path] (a new file) as a plain SQLite
  /// database, consistent even while an SMS is being filed.
  void backupTo(String path) => db.execute('VACUUM INTO ?', [path]);

  /// Replaces everything with the backup at [path], upgrading one from an
  /// older build. Throws [FormatException], changing nothing, if [path]
  /// isn't a Hisaab backup this build can read.
  Future<void> restoreFrom(String path) async {
    const notOurs = FormatException("That file isn't a Hisaab backup.");
    final Database src;
    try {
      src = sqlite3.open(path, mode: OpenMode.readOnly);
    } on SqliteException {
      throw notOurs;
    }
    try {
      final tables = {for (final r in src.select("SELECT name FROM sqlite_master WHERE type = 'table'")) r['name']};
      if (!tables.containsAll(['txns', 'settings']) || src.select('PRAGMA quick_check').first.columnAt(0) != 'ok') {
        throw notOurs;
      }
      if (src.userVersion > version) throw const FormatException('That backup is from a newer Hisaab. Update the app first.');
      await src.backup(db, nPage: -1).drain<void>();
    } on SqliteException {
      throw notOurs; // not a database at all
    } finally {
      src.close();
    }
    _migrate();
    _loadCats();
    notifyListeners();
  }

  /// Deletes everything; the app starts over at onboarding.
  void wipe() {
    _tx(() {
      for (final t in ['splits', 'tags', 'txns', 'sms', 'merchants', 'accounts', 'banks', 'settings', 'categories', 'formats']) {
        db.execute('DELETE FROM $t');
      }
      _seedCats();
    });
    _loadCats();
    notifyListeners();
  }
}

/// Puts a [Store] above the app; widgets that read it rebuild when it changes.
class StoreScope extends InheritedNotifier<Store> {
  const StoreScope({super.key, required Store store, required super.child}) : super(notifier: store);
}

extension StoreContext on BuildContext {
  Store get store => dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
