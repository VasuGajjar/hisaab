import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'capture.dart';
import 'screens/entry.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'store.dart';
import 'theme.dart';

Future<Store> openStore() async => Store.open('${(await getApplicationSupportDirectory()).path}/hisaab.db');

final _nav = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await openStore();
  startCapture(store, open: (route) {
    // 'txn:<id>': a capture notification's payment, in the Entry sheet.
    final ctx = _nav.currentState?.overlay?.context;
    if (ctx == null) return;
    final txn = route.startsWith('txn:') ? store.txn(int.tryParse(route.substring(4)) ?? 0) : null;
    if (txn != null) {
      openTxn(ctx, txn);
    } else if (route == 'review') {
      openQueue(ctx);
    } else if (route == 'add') {
      addSpend(ctx);
    }
  });
  runApp(HisaabApp(store));
}

/// Runs [job] on the ledger with no UI, for Android code that starts Dart
/// in the background (SmsReceiver.kt, Reminder.kt).
Future<void> _headless(Future<void> Function(Store) job) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized(); // plugins aren't registered for entry points other than main
  final store = await openStore();
  try {
    await job(store);
  } finally {
    store.dispose();
  }
}

/// An SMS arrived while the app was closed.
@pragma('vm:entry-point')
Future<void> captureMain() => _headless(captureOne);

/// The daily check-in alarm went off.
@pragma('vm:entry-point')
Future<void> reminderMain() => _headless(postReminder);

/// A capture notification's button, tapped while the app was closed.
@pragma('vm:entry-point')
Future<void> actionMain() => _headless(actionOne);

class HisaabApp extends StatelessWidget {
  HisaabApp(this.store, {super.key}) : home = store.onboarded ? const HomeScreen() : const OnboardingScreen();
  final Store store;

  /// Picked once at launch; onboarding moves on to Home by itself.
  final Widget home;

  @override
  Widget build(BuildContext context) => StoreScope(
        store: store,
        // Rebuilds with the store; the themes are cached, so only Glass effects changes them.
        child: Builder(
          builder: (c) => MaterialApp(
            navigatorKey: _nav,
            title: 'Hisaab',
            debugShowCheckedModeBanner: false,
            scrollBehavior: const HisaabScroll(),
            theme: hisaabTheme(Brightness.light, glass: c.store.glass),
            darkTheme: hisaabTheme(Brightness.dark, glass: c.store.glass),
            home: home,
          ),
        ),
      );
}
