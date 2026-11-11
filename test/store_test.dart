import 'package:flutter/material.dart' hide Row;
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data.dart';
import 'package:tracker/capture.dart';
import 'package:tracker/sms.dart';
import 'package:tracker/store.dart';

final now = DateTime(2026, 11, 8, 14);

/// The sample inbox imported from 1 Nov, as onboarding does it.
Store imported({Set<String> off = const {}}) {
  final inbox = sampleInbox(now);
  return Store.memory(clock: () => now)
    ..finishOnboarding(sms: true, since: DateTime(2026, 11), found: scanInbox(inbox), off: off, inbox: inbox);
}

Summary stats(Store s, DateTime from, DateTime to) => Summary(s.between(from, to), s.txn);

Txn by(Store s, String name, {TxnStatus? status}) =>
    s.between(DateTime(2026), DateTime(2027)).firstWhere((t) => t.name == name && (status == null || t.status == status));

void main() {
  test('import: statuses, payees, skipped SMS', () {
    final s = imported();
    final all = s.between(DateTime(2026, 11), DateTime(2026, 12));
    expect(all.length, 15); // 17 SMS minus the OTP and the personal one
    expect(s.accounts, ['HDFC ••1111', 'ICICI ••2222']);
    expect(s.pendingCount, 11);
    expect(s.queue().map((t) => t.status).toSet().length, 3);

    expect(by(s, 'Swiggy').status, TxnStatus.needs);
    expect(by(s, 'Asha K').status, TxnStatus.credit);
    expect(by(s, 'BigBasket').acct, 'ICICI ••2222');
    expect(by(s, 'Uber India').ref, '631200000006');
    expect(by(s, 'Payee not found').status, TxnStatus.unread);
    expect(by(s, 'To ICICI ••2222').status, TxnStatus.ignored);
    expect(by(s, 'From HDFC ••1111').status, TxnStatus.ignored);

    final chai = by(s, 'Chai Point');
    expect((chai.newPayee, chai.sugg.first.cat, chai.sugg.first.why), (true, food, 'guess'));
    expect(chai.raw, contains('[chaipoint@axisbank]'));
  });

  test('the same SMS twice is read once; unknown senders never', () {
    final s = imported();
    const body = 'Rs.450.00 debited from A/c XX1111 on 08-11-26 to VPA swiggy@icici. UPI Ref 631200000008.';
    expect(s.ingest('VM-HDFCBK', body, DateTime(2026, 11, 8, 13, 42)), isNull);
    expect(s.ingest('BX-RANDOM', body.replaceAll('450', '451'), now), isNull);
  });

  test('switched-off banks and wallets are dropped', () {
    final s = imported(off: {'ICICI', 'Amazon Pay'});
    expect(s.bankList.where((b) => !b.on).map((b) => b.bank.name), ['ICICI', 'Amazon Pay']);
    expect(s.accounts, ['HDFC ••1111', 'ICICI ••2222']); // kept: a transfer to it is still yours
    expect(s.between(DateTime(2026, 11), DateTime(2026, 12)).where((t) => t.acct.startsWith('ICICI')), isEmpty);
    expect(s.queue().where((t) => t.status == TxnStatus.dup), isEmpty);
  });

  test('remember files the payee\'s waiting payments; the next is 1 tap, or 0 with auto-file', () {
    final s = imported();
    List<Txn> waiting() => s.queue().where((t) => t.name == 'Swiggy').toList();
    final swiggy = waiting();
    expect(swiggy.length, 3);
    expect(s.file(swiggy[0].id, food, remember: false), 0);
    expect((waiting().length, s.rules.$1), (2, 0));
    expect(s.file(swiggy[1].id, food), 1); // and the last one waiting
    expect(waiting(), isEmpty);
    expect(s.rules, (1, 'Swiggy → Food & dining'));

    String sms(int rs, String ref) => 'Rs.$rs.00 debited from A/c XX1111 on 08-11-26 to VPA swiggy@icici. UPI Ref $ref.';
    final next = s.txn(s.ingest('VM-HDFCBK', sms(300, '631200000010'), now)!)!;
    expect((next.status, next.newPayee, next.sugg.first.cat, next.sugg.first.why), (TxnStatus.needs, false, food, '3×'));
    s.autoFile = true;
    final auto = s.txn(s.ingest('VM-HDFCBK', sms(301, '631200000011'), now.add(const Duration(hours: 1)))!)!;
    expect((auto.status, auto.cat), (TxnStatus.filed, food));
  });

  test('duplicate: merge keeps the bank SMS; undo brings it back', () {
    final s = imported();
    final dup = s.queue().singleWhere((t) => t.status == TxnStatus.dup);
    final bank = s.txn(dup.dupOf!)!;
    expect((dup.sender, bank.sender, bank.status), ('AX-AMZPAY', 'VM-HDFCBK', TxnStatus.needs));
    expect(stats(s, DateTime(2026, 11), DateTime(2026, 12)).payments, 9); // the echo isn't counted

    final undo = s.undoPoint(dup.id);
    s.mergeDup(dup.id);
    expect(s.txn(dup.id), isNull);
    undo();
    expect(s.txn(dup.id)!.status, TxnStatus.dup);

    s.keepBoth(dup.id);
    expect(s.txn(dup.id)!.status, TxnStatus.needs);
    expect(stats(s, DateTime(2026, 11), DateTime(2026, 12)).payments, 10);
  });

  test('refund: matched to the order, netted from its category', () {
    final s = imported();
    final order = s.queue().singleWhere((t) => t.name == 'Myntra');
    s.file(order.id, shop);
    final refund = by(s, 'Myntra', status: TxnStatus.credit);
    expect(s.refundMatch(refund)!.id, order.id);

    final before = stats(s, DateTime(2026, 11), DateTime(2026, 12));
    expect(before.byCat.any((c) => c.cat == shop), isTrue);
    s.linkRefund(refund.id, order.id);
    final after = stats(s, DateTime(2026, 11), DateTime(2026, 12));
    expect(after.byCat.any((c) => c.cat == shop), isFalse);
    expect(before.spent - after.spent, 149900);
    expect((after.refunds, after.inflow, after.own), (149900, 120000, 500000));
    expect(s.refundMatch(s.txn(refund.id)!), isNull);
  });

  test('stats: spend, payments, categories, months', () {
    final s = imported();
    final m = DateTime(2026, 11), end = DateTime(2026, 12);
    // 9 spends: 1499 + 386 + 412 + 60 + 299 + 1326.40 + 212 + 180 + 450.
    expect(stats(s, m, end).spent, 482440);
    expect(stats(s, m, end).unc?.paise, 482440);
    s.file(by(s, 'BigBasket').id, groc);
    s.addManual(paise: 24000, cats: [food], at: DateTime(2026, 11, 8, 13, 15), note: 'Lunch, office canteen');
    final st = stats(s, m, end);
    expect((st.spent, st.payments, st.byCat.first.cat, st.byCat.first.paise), (506440, 10, groc, 132640));

    // Reimbursable spends are kept out.
    s.file(by(s, 'BigBasket').id, groc, reimb: true);
    expect(stats(s, m, end).spent, 506440 - 132640);
  });

  test('unreadable SMS: fill in the gaps, or delete it', () {
    final s = imported();
    final imps = s.queue().last;
    expect((imps.status, imps.paise, imps.acct), (TxnStatus.unread, 215000, 'HDFC ••1111'));
    final undo = s.undoPoint(imps.id);
    s.fillUnread(imps.id, out: true, name: 'Landlord', cats: [home]);
    expect((s.txn(imps.id)!.status, s.txn(imps.id)!.cat, s.txn(imps.id)!.name), (TxnStatus.filed, home, 'Landlord'));
    undo();
    s.deleteTxn(imps.id);
    expect(s.txn(imps.id), isNull);
    expect(s.db.select('SELECT COUNT(*) n FROM sms WHERE body LIKE ?', ['%IMPS Ref no%']).first['n'], 0);
  });

  test('learn a format: the ones like it are filled, the next is read by itself; undo forgets it', () {
    final s = imported();
    int nach(String rs, int day, int h) => s.ingest('JX-CBSSBI-S',
        'Dear Customer, Your A/C XXXXX654321 has a debit by NACH of Rs $rs on $day/11/26. Avl Bal Rs 50,123.45. Download YONO - SBI',
        DateTime(2026, 11, day, h))!;
    final a = nach('2,500.00', 6, 9), b = nach('1,000.00', 7, 9);
    expect((s.txn(a)!.status, s.txn(b)!.status), (TxnStatus.unread, TxnStatus.unread));

    final undo = s.undoPoint(a);
    expect(s.fillUnread(a, out: true, name: 'SIP', cats: [home], learn: true), 1);
    expect((s.txn(b)!.status, s.txn(b)!.name, s.txn(b)!.cat), (TxnStatus.filed, 'SIP', home));
    expect(by(s, 'Payee not found').status, TxnStatus.unread); // the HDFC IMPS is another format

    final c = s.txn(nach('300.00', 8, 9))!;
    expect((c.status, c.name, c.inflow, c.sugg.first.cat), (TxnStatus.needs, 'SIP', false, home));

    undo();
    expect((s.txn(a)!.status, s.txn(b)!.status, s.txn(b)!.name), (TxnStatus.unread, TxnStatus.unread, 'Payee not found'));
    expect(s.txn(nach('400.00', 8, 10))!.status, TxnStatus.unread);
  });

  test('raw SMS go after 30 days, unreadable ones stay', () {
    final s = imported();
    final later = Store(s.db, clock: () => now.add(const Duration(days: 40)));
    expect(later.db.select('SELECT COUNT(*) n FROM sms').first['n'], 1);
    expect(by(later, 'Swiggy').raw, contains('[swiggy@icici]')); // rebuilt from the facts
  });

  test('tags, notes, rename', () {
    final s = imported();
    final t = by(s, 'Chai Point');
    s.file(t.id, food, note: 'team chai', tags: {'office', 'team'});
    s.rename(t.id, 'Chai Point, office');
    final f = s.txn(t.id)!;
    expect((f.note, f.name), ('team chai', 'Chai Point, office'));
    expect(f.tags, {'office', 'team'});
    expect(s.tagsInUse.toSet(), {'office', 'team'});
  });

  test('sms off: nothing imported, nothing captured; turning it on catches up', () {
    final s = Store.memory(clock: () => now)..finishOnboarding(sms: false, since: DateTime(2026, 11));
    expect((s.onboarded, s.smsOn, s.isEmpty, s.captureOn), (true, false, true, false));
    s.turnOnSms(sampleInbox(now));
    expect((s.smsOn, s.captureOn, s.pendingCount), (true, true, 11));
    s.smsOff();
    expect(s.captureOn, false);
  });

  test('inbox re-reads overlap safely; the cursor moves on', () {
    final s = imported();
    expect(s.inboxFrom, DateTime(2026, 11, 8, 13, 32)); // newest SMS 1:42 pm, less 10 min
    final before = s.between(DateTime(2026), DateTime(2027)).length;
    s.catchUp(sampleInbox(now));
    expect(s.between(DateTime(2026), DateTime(2027)).length, before);

    // The receiver and the inbox stamp one SMS a moment apart: still one row.
    const body = 'Rs.450.00 debited from A/c XX1111 on 08-11-26 to VPA swiggy@icici. UPI Ref 631200000008.';
    expect(s.ingest('VM-HDFCBK', body, DateTime(2026, 11, 8, 13, 42, 3)), isNull);

    final later = DateTime(2026, 11, 8, 15, 5);
    s.catchUp([
      (sender: 'VM-HDFCBK', body: 'Rs.99.00 debited from A/c XX1111 on 08-11-26 to VPA zepto@ybl. UPI Ref 631200000016.', at: later),
    ]);
    expect(s.inboxFrom, later.subtract(const Duration(minutes: 10)));
    expect(by(s, 'Zepto').status, TxnStatus.needs);
  });

  test('upgrades a v1 ledger in place', () {
    final s = imported();
    // Back to v1: undo v2 to v6, and bring back v1's sender allowlist.
    s.db.execute('''
      DROP TABLE splits; DROP TABLE categories; ALTER TABLE merchants DROP COLUMN own;
      DROP TABLE banks; DROP TABLE formats; ALTER TABLE accounts DROP COLUMN alias;
      ALTER TABLE accounts ADD COLUMN tracked INTEGER NOT NULL DEFAULT 1;
      CREATE TABLE senders (code TEXT PRIMARY KEY, bank TEXT NOT NULL, dup_only INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1) STRICT;
      INSERT INTO senders (code, bank, enabled) VALUES ('HDFCBK', 'HDFC', 1), ('ICICIB', 'ICICI', 0), ('SARBNK', 'Saraswat', 1);
    ''');
    s.db.userVersion = 1;
    final up = Store(s.db, clock: () => now);
    expect((up.db.userVersion, up.pendingCount), (Store.version, 11));
    expect(cats.map((c) => c.key), builtInCats.map((c) => c.key));
    // v4: a switched-off sender's bank stays off; an added one is known by its sender ID.
    final on = {for (final b in up.bankList) b.bank.name: b.on};
    expect((on['HDFC'], on['ICICI'], on['Saraswat']), (true, false, true));
    expect(up.banks.last.ids, ['SARBNK']);
  });

  test('split: each share counts in its category; one category undoes it', () {
    final s = imported();
    final bb = by(s, 'BigBasket').id;
    s.split(bb, [(home, 32640), (groc, 100000)]);
    final t = s.txn(bb)!;
    expect((t.status, t.cat, t.catLabel), (TxnStatus.filed, groc, 'Groceries +1'));
    expect(t.splits, [(groc, 100000), (home, 32640)]);

    final st = stats(s, DateTime(2026, 11), DateTime(2026, 12));
    int inCat(Cat c) => st.byCat.firstWhere((x) => x.cat == c).paise; // the whole payment, in each
    expect((inCat(groc), inCat(home), st.payments, st.spent), (132640, 132640, 9, 482440));
    expect(s.csv(DateTime(2026, 11, 7), DateTime(2026, 11, 8)), contains(',Groceries; Rent & home,'));

    final undo = s.undoPoint(bb);
    s.file(bb, groc);
    expect(s.txn(bb)!.splits, isEmpty);
    undo();
    expect(s.txn(bb)!.splits.length, 2);

    expect(() => s.split(bb, [(groc, 100), (home, 100)]), throwsArgumentError); // doesn't add up
    expect(() => s.split(bb, [(groc, 132640), (home, 0)]), throwsArgumentError);
    s.saveDetails(bb, note: 'monthly shop');
    expect((s.txn(bb)!.note, s.txn(bb)!.splits.length), ('monthly shop', 2));

    // Several categories picked: shared equally, the first takes the odd paisa.
    s.fileAll(bb, [home, groc, food]);
    expect(s.txn(bb)!.splits, unorderedEquals([(home, 44214), (groc, 44213), (food, 44213)]));
    expect(s.txn(bb)!.cat, home);
    s.fileAll(bb, [groc]);
    expect(s.txn(bb)!.cat, groc);
    expect(s.txn(bb)!.splits, isEmpty);
  });

  test('a refund nets every share of a split payment', () {
    final s = imported();
    final order = s.queue().singleWhere((t) => t.name == 'Myntra');
    s.split(order.id, [(shop, 99900), (fun, 50000)]);
    s.linkRefund(by(s, 'Myntra', status: TxnStatus.credit).id, order.id);
    final inStats = stats(s, DateTime(2026, 11), DateTime(2026, 12)).byCat.map((c) => c.cat);
    expect(inStats, isNot(contains(shop)));
    expect(inStats, isNot(contains(fun)));
  });

  test('categories: rename, add, reorder; kept on reopen', () {
    final s = imported();
    s.saveCat(key: 'food', name: 'Eating out', style: food, icon: 'restaurant');
    expect((catOf('food')!.full, catOf('food')!.short), ('Eating out', 'Eating out'));
    s.saveCat(name: 'Pets and vet', style: travel, icon: 'pets');
    final pets = cats.last;
    expect((pets.full, pets.short, pets.icon, pets.light.cc), ('Pets and vet', 'Pets', Icons.pets_outlined, travel.light.cc));
    s.moveCat(pets, 0);
    expect(cats.first, pets);
    s.file(by(s, 'Chai Point').id, pets);
    expect(by(s, 'Chai Point').cat!.full, 'Pets and vet');
    Store(s.db, clock: () => now);
    expect((cats.first.full, cats.length), ('Pets and vet', 12));
  });

  test('delete a category: payments, shares and rules move; Other stays', () {
    final s = imported();
    final chai = by(s, 'Chai Point').id, bb = by(s, 'BigBasket').id, uber = by(s, 'Uber India').id;
    s.file(chai, food); // also remembers Chai Point → Food
    s.split(bb, [(groc, 100000), (food, 32640)]); // food merges into groc's share
    s.split(uber, [(trans, 12000), (food, 9200)]); // food becomes a home share
    expect(s.catUsage(food), (payments: 3, rules: 1));

    s.deleteCat(food, groc);
    expect(cats.map((c) => c.key), isNot(contains('food')));
    expect(s.txn(chai)!.cat, groc);
    expect(s.txn(bb)!.cat, groc);
    expect(s.txn(bb)!.splits, isEmpty); // one share left: plain filing
    expect(s.txn(uber)!.splits, [(trans, 12000), (groc, 9200)]);
    expect(s.rulesList.single.cat, groc);
    expect(stats(s, DateTime(2026, 11), DateTime(2026, 12)).spent, 482440); // nothing lost

    expect(() => s.deleteCat(catOf('other')!, groc), throwsArgumentError);
    Store(s.db, clock: () => now);
    expect(cats.length, 10);
  });

  test('merchant rules: change, forget', () {
    final s = imported();
    s.file(by(s, 'Chai Point').id, food);
    final r = s.rulesList.single;
    expect((r.name, r.cat, r.count), ('Chai Point', food, 1));
    s.setRule(r.id, groc);
    expect(s.rulesList.single.cat, groc);
    s.setRule(r.id, null);
    expect(s.rulesList, isEmpty);
  });

  test('a payee marked as you: past and new payments are transfers, and back', () {
    final s = imported();
    final m = DateTime(2026, 11), end = DateTime(2026, 12);
    final asha = s.payees(own: false).firstWhere((p) => p.name == 'Asha K');
    s.setOwnPayee(asha.id, true);
    // Left as money in: the Myntra refund (not linked to its order here).
    expect((by(s, 'Asha K').status, stats(s, m, end).inflow), (TxnStatus.ignored, 149900));
    const body = 'Rs.500.00 debited from A/c XX1111 on 08-11-26 to VPA asha.k@okhdfcbank. UPI Ref 631200000012.';
    final id = s.ingest('VM-HDFCBK', body, now)!;
    expect((s.txn(id)!.status, s.txn(id)!.own), (TxnStatus.ignored, true));
    s.setOwnPayee(asha.id, false);
    expect((s.txn(id)!.status, stats(s, m, end).inflow), (TxnStatus.needs, 269900));
  });

  test('banks and accounts: switch off, add', () {
    final s = imported();
    s.setBankOn('HDFC', false);
    expect(s.bankList.firstWhere((b) => b.bank.name == 'HDFC').on, false);
    const hdfc = 'Rs.10.00 debited from A/c XX1111 on 08-11-26 to VPA a@ybl. UPI Ref 631200000016.';
    expect(s.ingest('VM-HDFCBK', hdfc, now), isNull);
    s.setBankOn('HDFC', true);
    expect(s.ingest('VM-HDFCBK', hdfc, now), isNotNull);

    String sms(String rs, String to, String ref) => 'Rs.$rs debited from A/c XX5555 on 08-11-26 to $to. UPI Ref $ref.';
    expect(s.ingest('VM-SARBNK', sms('75.00', 'VPA chai@ybl', '631200000013'), now), isNull); // not a known bank
    s.addBank('Saraswat', 'Saraswat, SARBNK');
    final added = s.bankList.last;
    expect((added.bank.name, added.on, added.added, added.accounts.length), ('Saraswat', true, true, 0));
    expect(s.txn(s.ingest('VM-SARBNK', sms('75.00', 'VPA chai@ybl', '631200000013'), now)!)!.acct, 'Saraswat ••5555');

    s.addAccount('Paytm Bank', '7788');
    final t = s.ingest('VM-SARBNK', sms('200.00', 'A/c XX7788', '631200000014'), now)!;
    expect((s.txn(t)!.status, s.txn(t)!.name), (TxnStatus.ignored, 'To Paytm Bank ••7788'));

    s.removeBank('Saraswat');
    expect(s.banks.length, builtInBanks.length);
  });

  test('a phone number added as a bank is read; other numbers never', () {
    final s = imported();
    const body = 'Rs.99.00 debited from A/c XX1111 on 08-11-26 to VPA chai@ybl. UPI Ref 631200000015.';
    expect(s.ingest('+919000011111', body, now), isNull);
    s.addBank('Test', '9000011111');
    expect(s.ingest('+919000022222', body, now), isNull);
    expect(s.txn(s.ingest('+919000011111', body, now)!)!.status, TxnStatus.needs);
  });

  test('capture notification wording, by kind of row', () {
    final s = imported();
    Map<String, Object?> n(String name, [TxnStatus? st]) => s.captureNotice(by(s, name, status: st).id)!;
    List<Object?> labels(Map<String, Object?> m) => [for (final a in m['actions'] as List) (a as Map)['label']];

    final chai = n('Chai Point');
    expect((chai['title'], chai['text']), ('₹180.00 paid to Chai Point', 'New payee. What was it for?'));
    expect(labels(chai), ['Add details', 'Not an expense']);

    final swiggy = s.queue().where((t) => t.name == 'Swiggy').toList();
    s.file(swiggy[1].id, food, remember: false); // remembering would file swiggy[0] too
    s.file(swiggy[2].id, food, remember: false);
    final known = s.captureNotice(swiggy[0].id)!;
    expect(known['text'], 'Food & dining 2 times before.');
    expect(labels(known), ['Food & dining', 'Add details']); // 1 tap, no app
    s.file(swiggy[0].id, food); // the rule auto-file needs

    expect(n('Asha K')['title'], '₹1,200.00 received from Asha K');
    expect(n('Payee not found')['channel'], 'unread');
    expect(s.captureNotice(by(s, 'Zomato', status: TxnStatus.dup).id), isNull);
    expect(s.captureNotice(by(s, 'To ICICI ••2222').id), isNull);

    s.autoFile = true;
    const body = 'Rs.300.00 debited from A/c XX1111 on 08-11-26 to VPA swiggy@icici. UPI Ref 631200000010.';
    final auto = s.captureNotice(s.ingest('VM-HDFCBK', body, now)!)!;
    expect(auto['title'], '₹300.00 to Swiggy · Food & dining');
    expect(labels(auto), ['Undo']);
  });

  test('unfile: back to needs, payee rule as it was', () {
    final s = imported();
    final chai = by(s, 'Chai Point').id;
    s.file(chai, food);
    expect(s.ruleOf(chai), 'food');
    s.unfile(chai);
    expect((s.txn(chai)!.status, s.txn(chai)!.cat, s.ruleOf(chai)), (TxnStatus.needs, null, null));
  });

  test('CSV: a row per payment, quoted where needed', () {
    final s = imported();
    s.file(by(s, 'Chai Point').id, food, note: 'team, "chai"', tags: {'office'});
    final lines = s.csv(DateTime(2026, 11, 8), DateTime(2026, 11, 9)).trim().split('\r\n');
    expect(lines.first, startsWith('Date,Time,Payee,Amount,Direction'));
    expect(lines.length, 5); // header + Uber, Asha, Chai Point, Swiggy
    expect(lines[3],
        '2026-11-08,12:10,Chai Point,180.00,out,filed,Food & dining,"team, ""chai""",office,HDFC ••1111,chaipoint@axisbank,631200000009,sms');
  });

  test('check-in wording: pending, then caught up', () {
    final s = imported();
    final c = s.checkIn();
    expect((c.pending, c.title, c.summary), (true, '11 payments need details', 'Oldest from Mon'));
    expect(c.text, 'Swiggy, Chai Point and 6 more · ₹7,273'); // 9 spends + the echo + the IMPS SMS
    expect(c.lines, [
      'Swiggy  ₹450.00',
      'Chai Point  ₹180.00',
      'Uber India  ₹212.00',
      '+6 more to categorise',
      '+2 need a decision: duplicate or unreadable SMS',
    ]);
    for (final t in s.queue()) {
      t.status == TxnStatus.needs ? s.file(t.id, food) : s.deleteTxn(t.id);
    }
    final done = s.checkIn();
    expect((done.pending, done.title), (false, 'All caught up today'));
    expect(done.text, '3 payments filed · ₹842 out. Paid anything in cash or from another account?');
  });

  test('delete all data starts over', () {
    final s = imported();
    s.saveCat(name: 'Pets', style: other, icon: 'pets');
    s.addBank('Saraswat', 'SARBNK');
    s.setBankOn('HDFC', false);
    s.wipe();
    expect((s.onboarded, s.isEmpty, cats.length, s.banks.length, s.banksOn, s.allAccounts.isEmpty),
        (false, true, 11, builtInBanks.length, builtInBanks.length, true));
  });}
