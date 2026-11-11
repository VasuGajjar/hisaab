// Pure Dart formatting: en_IN money grouping, dates, keypad entry.

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// en_IN grouping: last three digits, then pairs. 125000 → "1,25,000".
String groupIN(int n) {
  final s = n.abs().toString();
  final sign = n < 0 ? '-' : '';
  if (s.length <= 3) return '$sign$s';
  final head = s.substring(0, s.length - 3);
  final b = StringBuffer();
  for (var i = 0; i < head.length; i++) {
    if (i > 0 && (head.length - i).isEven) b.write(',');
    b.write(head[i]);
  }
  return '$sign$b,${s.substring(s.length - 3)}';
}

/// Paise → ("14,366", ".90").
(String, String) money(int paise) =>
    (groupIN(paise.abs() ~/ 100), '.${(paise.abs() % 100).toString().padLeft(2, '0')}');

/// Paise → "₹1,326.40".
String rupees(int paise, {bool dec = true}) {
  final (i, d) = money(paise);
  return '₹$i${dec ? d : ''}';
}

String time12(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

String _pad(int n) => n.toString().padLeft(2, '0');

/// "08 Nov".
String dayMon(DateTime t) => '${_pad(t.day)} ${_months[t.month - 1]}';

/// "Sun 08 Nov".
String dowDayMon(DateTime t) => '${_days[t.weekday - 1]} ${dayMon(t)}';

/// "08-11-26", as bank SMS write it.
String smsDate(DateTime t) => '${_pad(t.day)}-${_pad(t.month)}-${_pad(t.year % 100)}';

const _monthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "November".
String monthName(DateTime t) => _monthsFull[t.month - 1];

/// "Nov".
String monthShort(DateTime t) => _months[t.month - 1];

/// "Sun".
String dow(DateTime t) => _days[t.weekday - 1];

DateTime monthStart(DateTime t) => DateTime(t.year, t.month);
DateTime nextMonth(DateTime t) => DateTime(t.year, t.month + 1);
DateTime dayStart(DateTime t) => DateTime(t.year, t.month, t.day);
bool sameDay(DateTime a, DateTime b) => dayStart(a) == dayStart(b);

/// "Today · Sun 08 Nov", "Yesterday · Sat 07 Nov", else "Fri 06 Nov".
String dayLabel(DateTime d, DateTime now) {
  // Hours / 24, rounded: a DST day is 23 or 25 hours long.
  final ago = (dayStart(now).difference(dayStart(d)).inHours / 24).round();
  return switch (ago) {
    0 => 'Today · ${dowDayMon(d)}',
    1 => 'Yesterday · ${dowDayMon(d)}',
    _ => dowDayMon(d),
  };
}

/// Keypad entry as typed text. Keys: digits, '.', '⌫' (delete), 'C' (clear).
/// At most 7 rupee digits, one '.', 2 decimals, no leading zeros.
String keypadInput(String cur, String key) {
  if (key == 'C') return '';
  if (key == '⌫') return cur.isEmpty ? '' : cur.substring(0, cur.length - 1);
  final dot = cur.indexOf('.');
  if (key == '.') return dot >= 0 ? cur : (cur.isEmpty ? '0.' : '$cur.');
  if (dot >= 0 && cur.length - dot > 2) return cur;
  if (dot < 0 && cur.length >= 7) return cur;
  if (cur == '0') return key;
  return cur + key;
}

/// Typed keypad text → paise. "12.5" → 1250.
int keypadPaise(String s) {
  if (s.isEmpty) return 0;
  final p = s.split('.');
  final r = int.parse(p[0]);
  final d = p.length > 1 ? p[1].padRight(2, '0') : '00';
  return r * 100 + int.parse(d);
}
