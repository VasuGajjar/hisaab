// Renders every screen at the design's 360×800 frame, light and dark, with
// the real fonts and an in-memory ledger, and fails on any overflow or
// build error.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data.dart';
import 'package:tracker/capture.dart';
import 'package:tracker/screens/entry.dart';
import 'package:tracker/screens/home.dart';
import 'package:tracker/screens/onboarding.dart';
import 'package:tracker/screens/settings.dart';
import 'package:tracker/sms.dart';
import 'package:tracker/store.dart';
import 'package:tracker/theme.dart';
import 'package:tracker/widgets.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
  }
  await loader.load();
}

final now = DateTime(2026, 11, 8, 14);

/// Onboarded from the sample inbox; [since] null = SMS access refused.
Store store({DateTime? since}) {
  final inbox = since == null ? <Sms>[] : sampleInbox(now);
  return Store.memory(clock: () => now)
    ..finishOnboarding(sms: since != null, since: since ?? now, found: scanInbox(inbox), inbox: inbox);
}

Store imported() => store(since: DateTime(2026, 11));

Txn named(Store s, String name, [TxnStatus? status]) =>
    s.between(DateTime(2026), DateTime(2027)).firstWhere((t) => t.name == name && (status == null || t.status == status));

/// The Entry sheet as it sits in its modal: on thick glass at the bottom.
Widget sheet(EntryMode mode, [Txn? t]) =>
    Scaffold(body: Align(alignment: Alignment.bottomCenter, child: GlassSheet(child: EntrySheet(mode, t: t))));

/// A button that runs [open], for flows that pop with a message.
Widget opener(void Function(BuildContext) open) =>
    Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => open(c), child: const Text('open'))));

void main() {
  setUpAll(() async {
    await _font('Inter', ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf', 'Inter-Bold.ttf']);
    await _font('IBMPlexMono', ['IBMPlexMono-Regular.ttf', 'IBMPlexMono-Medium.ttf', 'IBMPlexMono-SemiBold.ttf']);
  });

  final screens = <String, (Store, Widget) Function()>{
    'home': () => (imported(), const HomeScreen()),
    'home empty': () => (store(since: now), const HomeScreen()),
    'home sms off': () => (store(), const HomeScreen()),
    'home sms off, with history': () {
      final s = imported();
      s.smsOff();
      return (s, const HomeScreen());
    },
    'home, glass off': () => (imported()..glass = false, const HomeScreen()),
    'settings': () => (imported(), const SettingsScreen()),
    'entry: queue': () => (imported(), sheet(EntryMode.queue)),
    'entry: manual': () => (imported(), sheet(EntryMode.manual)),
    'entry: manual, glass off': () => (imported()..glass = false, sheet(EntryMode.manual)),
    'entry: gaps': () {
      final s = imported();
      return (s, sheet(EntryMode.gaps, named(s, 'Payee not found')));
    },
    'entry: capture, new payee': () {
      final s = imported();
      return (s, sheet(EntryMode.capture, named(s, 'Chai Point')));
    },
    'entry: edit': () {
      final s = imported();
      s.file(named(s, 'Uber India').id, trans, tags: {'office'});
      return (s, sheet(EntryMode.edit, named(s, 'Uber India')));
    },
    'entry: edit, typed in': () {
      final s = imported();
      s.addManual(paise: 24000, cats: [food], at: now, payee: 'Canteen');
      return (s, sheet(EntryMode.edit, named(s, 'Canteen')));
    },
    'entry: duplicate': () {
      final s = imported();
      return (s, sheet(EntryMode.dup, named(s, 'Zomato', TxnStatus.dup)));
    },
    'entry: money in, refund': () {
      final s = imported();
      s.file(named(s, 'Myntra', TxnStatus.needs).id, shop);
      return (s, sheet(EntryMode.credit, named(s, 'Myntra', TxnStatus.credit)));
    },
    'entry: edit, split': () {
      final s = imported();
      s.split(named(s, 'BigBasket').id, [(groc, 100000), (home, 32640)]);
      return (s, sheet(EntryMode.edit, named(s, 'BigBasket')));
    },
    'settings: banks & senders': () => (imported(), const BanksScreen()),
    'settings: privacy': () => (imported(), const PrivacyScreen()),
    'settings: categories': () => (imported(), const CategoriesScreen()),
    'settings: rules': () {
      final s = imported();
      s.file(named(s, 'Chai Point').id, food);
      return (s, const RulesScreen());
    },
    'settings: rules, none': () => (imported(), const RulesScreen()),
    'settings: own accounts': () {
      final s = imported();
      s.setOwnPayee(s.payees(own: false).firstWhere((p) => p.name == 'Asha K').id, true);
      s.setAlias(s.allAccounts.first.id, 'Salary');
      return (s, const OwnAccountsScreen());
    },
  };

  test('summary: refunds netted, transfers and money in kept apart', () {
    final s = imported();
    final order = named(s, 'Myntra', TxnStatus.needs).id;
    s.file(order, shop);
    s.linkRefund(named(s, 'Myntra', TxnStatus.credit).id, order);
    s.split(named(s, 'BigBasket').id, [(groc, 100000), (home, 32640)]);
    s.file(named(s, 'Uber India').id, trans);
    final m = DateTime(2026, 11), end = DateTime(2026, 12);
    final sum = Summary(s.between(m, end), s.txn);
    // 9 spends, ₹4,824.40, less the ₹1,499 Myntra refund.
    expect((sum.spent, sum.payments, sum.inflow, sum.own, sum.refunds, sum.unc?.paise),
        (332540, 9, 120000, 500000, 149900, 178700));
    expect(sum.byCat.any((b) => b.cat == shop), isFalse); // refunded in full
    // One category: the whole of each payment under it.
    final g = Summary(s.between(m, end), s.txn, only: home);
    expect((g.spent, g.payments, g.inflow), (132640, 1, 0));
  });

  test('a named account labels its payments, bank first', () {
    final s = imported(), a = s.allAccounts.first, plain = '${a.bank} ••${a.last4}';
    s.setAlias(a.id, ' Salary ');
    expect(s.accounts.first, '$plain · Salary');
    expect(s.between(DateTime(2026), DateTime(2027)).where((t) => t.acct == '$plain · Salary'), isNotEmpty);
    s.addAccount('SBI', '1234', 'Joint');
    s.addAccount('SBI', '1234'); // re-adding without a name keeps it
    expect(s.accounts.last, 'SBI ••1234 · Joint');
    s.setAlias(a.id, '');
    expect(s.accounts.first, plain);
  });

  test('a payment under several categories counts in full in each', () {
    final s = store();
    s.addManual(paise: 10000, cats: [home, groc], at: DateTime(2026, 11, 2));
    s.addManual(paise: 20000, cats: [home, bills], at: DateTime(2026, 11, 3));
    final m = DateTime(2026, 11), end = DateTime(2026, 12);
    final sum = Summary(s.between(m, end), s.txn);
    expect([for (final b in sum.byCat) (b.cat, b.paise)], [(home, 30000), (bills, 20000), (groc, 10000)]);
    expect((sum.spent, sum.payments), (30000, 2));
    expect(Summary(s.between(m, end), s.txn, only: home).spent, 30000);
  });

  testWidgets('seg: selected thumb sits 3 dp inside the track on every side', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hisaabTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: Seg<bool>(value: true, options: const [(true, 'A', null), (false, 'B', null)], onChanged: (_) {}),
          ),
        ),
      ),
    );
    final track = tester.getRect(find.byType(Seg<bool>));
    final thumb = tester.getRect(find.ancestor(of: find.text('A'), matching: find.byType(InkWell)));
    expect([thumb.left - track.left, thumb.top - track.top, track.bottom - thumb.bottom], [3, 3, 3]);
  });

  for (final b in Brightness.values) {
    Future<Store> pump(WidgetTester tester, (Store, Widget) sw) async {
      final (s, w) = sw;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(StoreScope(store: s, child: MaterialApp(theme: hisaabTheme(b, glass: s.glass), home: w)));
      await tester.pumpAndSettle();
      return s;
    }

    for (final MapEntry(:key, :value) in screens.entries) {
      testWidgets('$key (${b.name})', (tester) => pump(tester, value()));
    }

    testWidgets('home: breakdown sheet filters to a category, chip clears it (${b.name})', (tester) async {
      final s = imported();
      s.file(named(s, 'BigBasket').id, groc);
      await pump(tester, (s, const HomeScreen()));
      expect(find.text('Top categories'), findsOneWidget);
      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();
      expect(find.text('Spending breakdown'), findsOneWidget);
      await tester.tap(find.text('By payee'));
      await tester.pumpAndSettle();
      expect(find.text('Myntra'), findsWidgets);
      await tester.tap(find.text('By category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').last); // the sheet's row
      await tester.pumpAndSettle();
      expect(find.text('Top payees'), findsOneWidget);
      expect(find.byType(TxnTile), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Clear category filter Groceries'));
      await tester.pumpAndSettle();
      expect(find.text('Top categories'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Top categories'), findsOneWidget);
    });

    testWidgets('home: filter chips narrow, clear and change month (${b.name})', (tester) async {
      await pump(tester, (imported(), const HomeScreen()));
      Future<void> pick(String chip, String option) async {
        final c = find.text(chip, skipOffstage: false).first; // the chip row scrolls sideways
        await tester.ensureVisible(c);
        await tester.pumpAndSettle();
        // ensureVisible also scrolled the page, parking the chips under the app bar: back to the top.
        await tester.drag(find.byType(ListView).first, const Offset(0, 600));
        await tester.pumpAndSettle();
        await tester.tap(c);
        await tester.pumpAndSettle();
        await tester.tap(find.text(option).last); // the menu's, above any badge
        await tester.pumpAndSettle();
      }

      await pick('Status', "Couldn't read");
      expect(find.byType(TxnTile), findsOneWidget);
      expect(find.text('Payee not found'), findsOneWidget);
      await pick('Account', 'Cash');
      expect(find.text('Nothing from this month matches these filters.'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.byType(TxnTile), findsWidgets);
      await pick('November', 'Last month');
      expect(find.text('Payments from last month show up here.'), findsOneWidget);
      await pick('October', 'Custom range…'); // opens on October
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('01 Oct – 31 Oct'), findsOneWidget);
      await pick('01 Oct – 31 Oct', 'This year');
      expect(find.byType(TxnTile), findsWidgets);
    });

    testWidgets('home: tag filter keeps only tagged payments (${b.name})', (tester) async {
      final s = imported();
      s.saveDetails(named(s, 'Chai Point').id, tags: {'office'});
      await pump(tester, (s, const HomeScreen()));
      final chip = find.text('Tag', skipOffstage: false).first; // last in the sideways chip row
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 600)); // page back to the top
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.tap(find.text('#office').last);
      await tester.pumpAndSettle();
      expect(find.byType(TxnTile), findsOneWidget);
      expect(find.descendant(of: find.byType(TxnTile), matching: find.text('Chai Point')), findsOneWidget);
      expect(find.text('#office'), findsWidgets); // the chip now names it
    });

    testWidgets('onboarding, all steps, importing the month (${b.name})', (tester) async {
      final s = await pump(tester, (Store.memory(clock: () => now), const OnboardingScreen()));
      for (final next in ['Get started', 'Allow SMS access', 'Allow notifications', 'Remind me at 9:30 pm']) {
        await tester.tap(find.text(next));
        await tester.pumpAndSettle();
      }
      expect(find.text('We found 2 banks'), findsOneWidget);
      await tester.tap(find.text('1 Nov · 14 payments'));
      await tester.tap(find.text('Finish setup'));
      await tester.pumpAndSettle();
      expect(s.pendingCount, 11);
      expect(find.text('11 need details'), findsOneWidget);
    });

    testWidgets('review queue to the end, with undo (${b.name})', (tester) async {
      final s = await pump(tester, (imported(), opener(openQueue)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 11'), findsOneWidget);
      await tester.tap(find.text('Food').first); // Swiggy, today: a category tap files and moves on
      await tester.pumpAndSettle();
      expect(s.pendingCount, 8); // Swiggy remembered: its other two went with it
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 11'), findsOneWidget);
      expect(s.pendingCount, 11);

      for (var i = 0; i < 20 && find.text('All caught up').evaluate().isEmpty; i++) {
        if (find.text('Merge into one').evaluate().isNotEmpty) {
          await tester.tap(find.text('Merge into one'));
        } else if (find.text('Payee and direction not found').evaluate().isNotEmpty) {
          await tester.tap(find.text('Skip'));
        } else if (find.text('Food').evaluate().isNotEmpty) {
          await tester.ensureVisible(find.text('Food').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Food').first);
        } else {
          await tester.tap(find.text('More'));
        }
        await tester.pumpAndSettle();
      }
      expect(find.text('All caught up'), findsOneWidget);
      expect(s.pendingCount, 1); // the skipped IMPS SMS
      expect(Summary(s.between(DateTime(2026, 11), DateTime(2026, 12)), s.txn).byCat.single.cat, food);
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('fill in the gaps, then money in (${b.name})', (tester) async {
      final s = imported();
      final imps = named(s, 'Payee not found').id, myntra = named(s, 'Myntra', TxnStatus.credit).id;
      await pump(tester, (s, opener((c) => openTxn(c, s.txn(imps)!))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Add who it was'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Ravi K');
      await tester.pumpAndSettle();
      expect(find.text('Pick a category'), findsOneWidget);
      await tester.tap(find.text('Home').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((s.txn(imps)!.name, s.txn(imps)!.status, s.txn(imps)!.cat), ('Ravi K', TxnStatus.filed, home));

      await pump(tester, (s, opener((c) => openTxn(c, s.txn(myntra)!))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as income'));
      await tester.pumpAndSettle();
      expect(s.txn(myntra)!.creditKind, 'income');
      expect(find.text('Saved as income'), findsOneWidget);
    });

    testWidgets('settings: every row opens, toggles save (${b.name})', (tester) async {
      final s = await pump(tester, (imported(), const SettingsScreen()));
      await tester.tap(find.text('Reminder time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel')); // the time picker
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(s.reminderOn, isFalse);
      for (final row in ['Banks', 'On this phone only', 'Categories', 'Merchant rules', 'Own accounts']) {
        await tester.scrollUntilVisible(find.text(row), 100);
        await tester.tap(find.text(row));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(find.text('Glass effects'), -100); // back up
      await Scrollable.ensureVisible(tester.element(find.text('Glass effects')), alignment: .5); // clear of the bar
      await tester.pumpAndSettle();
      await tester.tap(find.text('Glass effects'));
      await tester.pumpAndSettle();
      expect(s.glass, isFalse);
    });

    testWidgets('file a payment under two categories (${b.name})', (tester) async {
      final s = imported();
      final bb = named(s, 'BigBasket').id;
      s.file(bb, groc);
      await pump(tester, (s, opener((c) => openTxn(c, s.txn(bb)!))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Edit payment'), findsOneWidget);
      await tester.ensureVisible(find.text('Change'));
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Home').last);
      await tester.tap(find.text('Home').last); // the grid tile; Groceries stays picked
      await tester.pumpAndSettle();
      expect(find.text('₹1,326.40 counts in full under each.'), findsOneWidget);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(s.txn(bb)!.splits, unorderedEquals([(groc, 66320), (home, 66320)]));
      expect(find.text('Changes saved · BigBasket'), findsOneWidget);

      await tester.tap(find.text('open')); // the category field: names, the total once, no shares
      await tester.pumpAndSettle();
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Groceries + Home'), findsOneWidget);
      expect(find.textContaining('663.20'), findsNothing);
      expect(find.text('−₹1,326.40'), findsOneWidget);
    });

    testWidgets('payee and note: set when filing, editable after saving (${b.name})', (tester) async {
      final s = imported();
      final chai = named(s, 'Chai Point').id;
      await pump(tester, (s, opener((c) => openTxn(c, s.txn(chai)!))));
      Future<void> open() async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      Future<void> tap(String text) async {
        await tester.ensureVisible(find.text(text).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(text).last);
        await tester.pumpAndSettle();
      }

      await open(); // capture: the receipt's Edit renames, flipping the payee to ink
      await tap('Edit');
      await tester.enterText(find.byType(TextFormField), 'Chai Point Office');
      await tester.pumpAndSettle();
      expect(find.text('Remember for Chai Point Office'), findsOneWidget);
      await tap('Note');
      await tester.enterText(find.byType(InkField), 'team chai');
      await tap('Tag');
      await tester.enterText(find.byType(TextField).last, 'Office');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tap('Food'); // the grid tile
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((s.txn(chai)!.name, s.txn(chai)!.note, s.txn(chai)!.cat), ('Chai Point Office', 'team chai', food));
      expect(s.txn(chai)!.tags, {'office'});
      expect(find.text('Chai Point Office filed as Food & dining'), findsOneWidget);

      await open(); // filed: edit mode, note and tags showing
      expect(find.text('Edit payment'), findsOneWidget);
      await tap('Edit');
      await tester.enterText(find.byType(TextFormField), 'Chai Point');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect((s.txn(chai)!.name, s.txn(chai)!.note), ('Chai Point', 'team chai'));
    });

    testWidgets("remember files the payee's other pending payments (${b.name})", (tester) async {
      final s = imported();
      final swiggy = [for (final t in s.queue()) if (t.name == 'Swiggy') t.id];
      expect(swiggy, hasLength(3));
      await pump(tester, (s, opener((c) => openTxn(c, s.txn(swiggy.first)!))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Food').last);
      await tester.tap(find.text('Food').last); // the grid tile; Remember is on
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect([for (final id in swiggy) s.txn(id)!.cat], [food, food, food]);
      expect(find.text('Swiggy filed as Food & dining, with 2 more from them'), findsOneWidget);
    });

    testWidgets('new category from the editor (${b.name})', (tester) async {
      await pump(tester, (imported(), const CategoriesScreen()));
      await tester.tap(find.text('New category'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Pets');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('pets icon'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((cats.last.full, cats.last.icon), ('Pets', Icons.pets_outlined));
      expect(find.text('Pets', skipOffstage: false), findsOneWidget); // 12th row, just below the fold
    });

    testWidgets('delete a category, moving its payments (${b.name})', (tester) async {
      final s = imported();
      final chai = named(s, 'Chai Point').id;
      s.file(chai, food);
      await pump(tester, (s, const CategoriesScreen()));
      await tester.tap(find.text('Food & dining'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('1 payment and 1 payee rule move to:'), findsOneWidget);
      await tester.tap(find.text('Delete').last); // the dialog's
      await tester.pumpAndSettle();
      expect((cats.contains(food), s.txn(chai)!.cat), (false, other));
      expect(find.text('Food & dining deleted · moved to Other'), findsOneWidget);
    });

    testWidgets('Other has no delete button (${b.name})', (tester) async {
      await pump(tester, (imported(), const CategoriesScreen()));
      await tester.scrollUntilVisible(find.text('Other'), 100);
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(find.text('Edit category'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('delete all data goes back to onboarding (${b.name})', (tester) async {
      final s = await pump(tester, (imported(), const PrivacyScreen()));
      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect((s.isEmpty, s.onboarded), (true, false));
      expect(find.text('Get started'), findsOneWidget);
    });

    testWidgets('manual add saves a filed cash spend (${b.name})', (tester) async {
      final s = await pump(tester, (store(), opener(addSpend)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final k in ['2', '4', '0']) {
        await tester.tap(find.text(k).last);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save ₹240 · Food'));
      await tester.pumpAndSettle();
      final t = s.between(DateTime(2026), DateTime(2027)).single;
      expect((t.paise, t.status, t.cat, t.source), (24000, TxnStatus.filed, food, 'cash'));
      expect(find.text('₹240 cash added · Food & dining'), findsOneWidget);
    });

    testWidgets('manual add from one of your accounts (${b.name})', (tester) async {
      final s = await pump(tester, (imported(), opener(addSpend)));
      final a = s.allAccounts.first;
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final k in ['2', '4', '0']) {
        await tester.tap(find.text(k).last);
      }
      await tester.tap(find.text('Bank account'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(a.label));
      await tester.tap(find.text(a.label));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Save ₹240'));
      await tester.pumpAndSettle();
      final t = s.between(DateTime(2026), DateTime(2027)).singleWhere((t) => t.manual);
      expect((t.source, t.acct), ('other', a.label));
      expect(t.metaLine(), contains(a.label));
    });

    testWidgets('edit a typed-in spend: cash to one of your accounts (${b.name})', (tester) async {
      final s = imported(), a = s.allAccounts.first;
      final id = s.addManual(paise: 24000, cats: [food], at: now, payee: 'Canteen');
      await pump(tester, (s, opener((c) => openTxn(c, s.txn(id)!))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank account'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(a.label));
      await tester.tap(find.text(a.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect((s.txn(id)!.source, s.txn(id)!.acct), ('other', a.label));
    });

    testWidgets('manual add on an earlier day (${b.name})', (tester) async {
      final s = await pump(tester, (store(), opener(addSpend)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Today · 2:00 pm'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('7')));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel')); // the time picker: keep 2:00 pm
      await tester.pumpAndSettle();
      expect(find.text('Yesterday · 2:00 pm'), findsOneWidget);
      for (final k in ['2', '4', '0']) {
        await tester.tap(find.text(k).last);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save ₹240 · Food'));
      await tester.pumpAndSettle();
      expect(s.between(DateTime(2026), DateTime(2027)).single.when, DateTime(2026, 11, 7, 14));
    });

    testWidgets('manual add under two categories (${b.name})', (tester) async {
      final s = await pump(tester, (store(), opener(addSpend)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final k in ['2', '4', '0']) {
        await tester.tap(find.text(k).last);
      }
      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save ₹240 · Food + Transport'));
      await tester.pumpAndSettle();
      final t = s.between(DateTime(2026), DateTime(2027)).single;
      expect(t.splits, unorderedEquals([(food, 12000), (trans, 12000)]));
    });
  }
}
