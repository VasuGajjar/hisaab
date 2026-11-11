# Hisaab

A UPI expense tracker for Android. Hisaab reads your bank SMS as they arrive, files each payment in a SQLite ledger on the phone, and lets you categorise it straight from the notification.

Nothing leaves the phone. Release builds don't have the `INTERNET` permission, and Android cloud backup is turned off.

Built with Flutter. Android only.

## Features

- **Capture from bank SMS.** 20 Indian banks are built in (HDFC, ICICI, SBI, Axis, Kotak and others; see `builtInBanks` in [lib/sms.dart](lib/sms.dart)). You can add more in Settings. Amazon Pay SMS are read only to spot duplicates.
- **Inbox import.** During onboarding you can import this month's payments from the inbox.
- **One-tap filing.** Each capture notification has category buttons. Hisaab remembers the category you pick for a payee, so the next payment to them is filed with no taps.
- **Ledger rules.** Duplicates, refunds and transfers between your own accounts are detected and left out of spend totals. A payment can be split across categories, and categories can be edited.
- **Unreadable SMS.** When Hisaab can't read an SMS, you fill in the details once. It then reads later SMS in the same format.
- **Daily check-in.** An optional reminder to review the day's payments.
- **Export and backup.** Export a date range as CSV, or back up and restore the whole ledger as a SQLite file.
- **Raw SMS retention.** The original SMS text is deleted after 30 days, or straight away if you turn that setting off. Unreadable SMS are kept until you fill them in.

## Privacy

| Permission | Why |
|---|---|
| `RECEIVE_SMS`, `READ_SMS` | Capture new bank SMS and import from the inbox |
| `POST_NOTIFICATIONS` | Capture notifications and the daily check-in |
| `RECEIVE_BOOT_COMPLETED` | Reschedule the check-in alarm after a reboot |

SMS go through two filters before anything is stored. The native receiver passes on only messages that mention an amount. The Dart side then keeps only messages from a known bank that read as a payment. Everything else is dropped. Fonts are bundled in the app, not downloaded.

The debug and profile manifests add `INTERNET`, because the Flutter tool needs it for hot reload and debugging. The release manifest doesn't have it.

## Build and run

Requires Flutter 3.44.2 (stable) and Dart 3.12.2.

```sh
flutter pub get
flutter analyze
flutter test        # logic, plus every screen at 360×800 in light and dark
flutter run         # on an Android device or emulator
```

When the app isn't running on Android (tests, desktop debug runs), a sample inbox in [lib/capture.dart](lib/capture.dart) stands in for the phone's SMS.

> [!WARNING]
> `integration_test/perf_test.dart` measures frame timings on a real device. When `flutter drive` finishes, it **uninstalls the app, which deletes the ledger**. Back up first (Settings › Back up data) or use a device that doesn't have your data.

Release builds are signed with the debug key (see [android/app/build.gradle.kts](android/app/build.gradle.kts)). Set up your own signing key before you distribute an APK.

`android/gradle.properties` sets `kotlin.incremental=false`. Kotlin incremental compilation fails with `this and base files have different roots` when the pub cache and the project are on different drives.

## Project layout

| Path | Contents |
|---|---|
| [lib/main.dart](lib/main.dart) | App entry, plus the headless entry points that Android starts in the background (`captureMain`, `reminderMain`, `actionMain`) |
| [lib/sms.dart](lib/sms.dart) | Pure-Dart bank SMS parser: bank matching, amount, direction, accounts, UPI ID, reference, payee name |
| [lib/capture.dart](lib/capture.dart) | The `hisaab/capture` platform channel: permissions, inbox, live SMS, notifications, file save and open. Also holds the sample inbox. |
| [lib/store.dart](lib/store.dart) | SQLite schema and migrations, and the ledger rules: filing, payee rules, duplicates, refunds, own-account transfers, totals, CSV, backup |
| [lib/data.dart](lib/data.dart) | Categories and the transaction model |
| [lib/format.dart](lib/format.dart) | en_IN number grouping (₹1,25,000), dates, keypad entry |
| [lib/theme.dart](lib/theme.dart), [lib/widgets.dart](lib/widgets.dart) | Design tokens, light and dark themes, and shared components (glass surfaces, sheets, receipts, keypad) |
| [lib/screens/](lib/screens/) | Onboarding, Home, Settings, and the Entry sheet (capture, edit, manual add, review queue) |
| [android/app/src/main/kotlin/](android/app/src/main/kotlin/) | `MainActivity` (channel), `SmsReceiver`, `Notices` (capture notifications), `Reminder` (daily check-in) |
| [test/](test/) | Unit and widget tests |

## Contributing

Issues and pull requests are welcome. Before you open a PR, make sure `flutter analyze` and `flutter test` both pass.

To add a bank or a new SMS format, add an entry to `builtInBanks` in [lib/sms.dart](lib/sms.dart), and add a parsing test in [test/sms_test.dart](test/sms_test.dart). **Anonymise every SMS you paste:** replace account digits, UPI IDs, names, reference numbers and balances.

To report a security problem, use GitHub's private vulnerability reporting (**Security › Report a vulnerability**). Don't open a public issue for it.

## License

[MIT](LICENSE).

The bundled fonts, Inter and IBM Plex Mono, are licensed under the SIL Open Font License 1.1 ([assets/fonts/OFL.txt](assets/fonts/OFL.txt)).
