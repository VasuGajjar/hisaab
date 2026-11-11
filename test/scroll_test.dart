// HisaabScroll: elastic physics, and the edge fade only where content lies past an edge.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/theme.dart';

void main() {
  Future<void> pumpList(WidgetTester tester, int n) => tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const HisaabScroll(),
      home: ListView(children: [for (var i = 0; i < n; i++) SizedBox(height: 100, child: Text('$i'))]),
    ),
  );

  bool masked(WidgetTester tester) => tester.layers.any((l) => l is ShaderMaskLayer);

  testWidgets('content that fits is not masked', (tester) async {
    await pumpList(tester, 2);
    await tester.pump(); // the first ScrollMetricsNotification lands after layout
    expect(masked(tester), isFalse);
  });

  testWidgets('a long list fades, bounces past its ends, and settles back', (tester) async {
    await pumpList(tester, 50);
    await tester.pump();
    expect(masked(tester), isTrue); // more below

    final pos = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pump();
    expect(pos.pixels, lessThan(0)); // overscrolled, elastic
    await tester.pumpAndSettle();
    expect(pos.pixels, 0);
  });
}
