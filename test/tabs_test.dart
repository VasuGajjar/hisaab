// Tab switches: Seg's thumb slides; TabSwitch brings the new tab in from its own side.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/theme.dart';
import 'package:tracker/widgets.dart';

void main() {
  Widget app(Widget child) => MaterialApp(theme: hisaabTheme(Brightness.light), home: Scaffold(body: child));

  testWidgets('TabSwitch: forward enters from the right, back from the left', (tester) async {
    Widget at(int i) => app(TabSwitch(index: i, child: Text('tab $i')));
    await tester.pumpWidget(at(0));
    final home = tester.getTopLeft(find.text('tab 0')).dx;

    await tester.pumpWidget(at(1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getTopLeft(find.text('tab 1')).dx, greaterThan(home));
    expect(tester.getTopLeft(find.text('tab 0')).dx, lessThan(home));
    await tester.pumpAndSettle();
    expect(find.text('tab 0'), findsNothing);

    await tester.pumpWidget(at(0));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getTopLeft(find.text('tab 0')).dx, lessThan(home));
    expect(tester.getTopLeft(find.text('tab 1')).dx, greaterThan(home));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('tab 0')).dx, home);
  });

  testWidgets('Seg: the thumb slides to the picked option', (tester) async {
    var cash = true;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (c, set) => Seg<bool>(
            value: cash,
            options: const [(true, 'Cash', null), (false, 'Other account', null)],
            onChanged: (v) => set(() => cash = v),
          ),
        ),
      ),
    );
    double thumbX() => tester.getTopLeft(find.byType(FractionallySizedBox)).dx;
    final left = thumbX();

    await tester.tap(find.text('Other account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final mid = thumbX();
    await tester.pumpAndSettle();
    expect(mid, greaterThan(left));
    expect(mid, lessThan(thumbX())); // in between: it slid, didn't jump
  });
}
