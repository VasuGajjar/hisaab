// Frame timings on a real phone: opens each kind of sheet and scrolls Home.
// WARNING: flutter drive UNINSTALLS the app when it ends, deleting the
// ledger on that phone. Back up data first (Settings › Back up data).
// flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart
// Results: build/integration_response_data.json (build and raster ms per frame).
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracker/capture.dart';
import 'package:tracker/screens/home.dart';
import 'package:tracker/sms.dart';
import 'package:tracker/store.dart';
import 'package:tracker/theme.dart';
import 'package:tracker/widgets.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('open sheets, scroll home', (tester) async {
    final now = DateTime(2026, 11, 8, 14), inbox = sampleInbox(now);
    final s = Store.memory(clock: () => now)
      ..finishOnboarding(sms: true, since: DateTime(2026, 11), found: scanInbox(inbox), inbox: inbox);
    await tester.pumpWidget(
      StoreScope(
        store: s,
        child: MaterialApp(
          theme: hisaabTheme(Brightness.light),
          darkTheme: hisaabTheme(Brightness.dark),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> sheet(Finder open) async {
      await tester.tap(open.first);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute(); // Android back
      await tester.pumpAndSettle();
    }

    Future<void> measure(String key, Future<void> Function() action) async {
      final frames = <FrameTiming>[];
      void grab(List<FrameTiming> ts) => frames.addAll(ts);
      SchedulerBinding.instance.addTimingsCallback(grab);
      await action();
      await tester.pump(const Duration(seconds: 1)); // timings arrive in batches
      SchedulerBinding.instance.removeTimingsCallback(grab);
      Map<String, num> stats(Iterable<Duration> ds) {
        final ms = [for (final d in ds) d.inMicroseconds / 1000]..sort();
        return {
          'avg': ms.reduce((a, b) => a + b) / ms.length,
          'p90': ms[(ms.length * .9).floor()],
          'max': ms.last,
          'over8ms': ms.where((m) => m > 8.3).length,
          'over16ms': ms.where((m) => m > 16.7).length,
        };
      }

      binding.reportData = {
        ...?binding.reportData,
        key: {
          'frames': frames.length,
          'build': stats(frames.map((f) => f.buildDuration)),
          'raster': stats(frames.map((f) => f.rasterDuration)),
        },
      };
    }

    await measure('sheets', () async {
      for (var i = 0; i < 3; i++) {
        await sheet(find.text('View all'));
        await sheet(find.text('Add cash'));
        await sheet(find.byType(TxnTile));
      }
    });
    await measure('scroll', () async {
      for (var i = 0; i < 2; i++) {
        await tester.fling(find.byType(ListView).first, const Offset(0, -500), 2500);
        await tester.pumpAndSettle();
        await tester.fling(find.byType(ListView).first, const Offset(0, 500), 2500);
        await tester.pumpAndSettle();
      }
    });
  });
}
