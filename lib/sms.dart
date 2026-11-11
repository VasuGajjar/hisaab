// Bank SMS → payment facts. Pure Dart (no Flutter), so the headless isolate
// the SMS receiver will start can run the same parser.

typedef Sms = ({String sender, String body, DateTime at});

/// A bank, known by [ids] inside a sender ID ('JD-AXISBK-S' has AXIS) or
/// by [words] in an SMS's text ('…your Axis Bank a/c').
class Bank {
  const Bank(this.name, this.ids, this.words, {this.dupOnly = false});
  final String name;

  /// Letters (or digits, for a phone number) a sender ID contains.
  final List<String> ids;

  /// Whole words in the text, any case.
  final List<String> words;

  /// A wallet that echoes a bank's SMS: read only to spot duplicates.
  final bool dupOnly;
}

const builtInBanks = [
  Bank('HDFC', ['HDFC'], ['HDFC']),
  Bank('ICICI', ['ICICI'], ['ICICI']),
  Bank('SBI', ['SBI'], ['SBI', 'State Bank']),
  Bank('Axis', ['AXIS'], ['Axis Bank']),
  Bank('Kotak', ['KOTAK'], ['Kotak']),
  Bank('Yes', ['YESBNK', 'YESBK'], ['Yes Bank']),
  Bank('IDFC First', ['IDFC'], ['IDFC']),
  Bank('IndusInd', ['INDUS'], ['IndusInd']),
  Bank('PNB', ['PNB'], ['PNB', 'Punjab National']),
  Bank('BoB', ['BOB', 'BARODA'], ['Bank of Baroda']),
  Bank('Canara', ['CANARA', 'CANBNK'], ['Canara']),
  Bank('Union', ['UNIONB', 'UBOI'], ['Union Bank']),
  Bank('RBL', ['RBL'], ['RBL']),
  Bank('Federal', ['FEDBNK', 'FEDERAL'], ['Federal Bank']),
  Bank('AU', ['AUBANK', 'AUSFB'], ['AU Bank', 'AU Small Finance']),
  Bank('IDBI', ['IDBI'], ['IDBI']),
  Bank('Central Bank', ['CBOI', 'CENTBK'], ['Central Bank of India']),
  Bank('Bank of India', ['BOIIND'], ['Bank of India']),
  Bank('Indian Bank', ['INDBNK'], ['Indian Bank']),
  Bank('UCO', ['UCOBNK'], ['UCO Bank']),
  Bank('Amazon Pay', ['AMZPAY', 'AMAZONPAY'], ['Amazon Pay'], dupOnly: true),
];

final _wordRe = <String, RegExp>{};

/// The bank an SMS is from: a bank in the sender ID first ('JD-AXISBK-S' →
/// Axis), else the first bank its text names. UPI IDs are left out of the
/// text: 'swiggy@icici' names the payee's bank, not yours.
Bank? bankOf(String sender, String body, [List<Bank> banks = builtInBanks]) {
  final id = sender.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  // Longest first: CBOI is Central Bank, not Bank of India.
  final ids = [for (final b in banks) for (final i in b.ids) (b, i.toUpperCase())]
    ..sort((x, y) => y.$2.length - x.$2.length);
  for (final (b, i) in ids) {
    if (i.isNotEmpty && id.contains(i)) return b;
  }
  final text = body.replaceAll(RegExp(r'\S+@\S+'), ' ');
  (Bank, int, int)? best; // bank, where, how long
  for (final b in banks) {
    for (final w in b.words) {
      final m = _wordRe.putIfAbsent(w, () => RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false)).firstMatch(text);
      if (m != null && (best == null || m.start < best.$2 || (m.start == best.$2 && w.length > best.$3))) {
        best = (b, m.start, w.length);
      }
    }
  }
  return best?.$1;
}

/// What one payment SMS says.
class Parsed {
  Parsed(this.body, this.paise, this.inflow, this.accts, this.vpa, this.ref, this.name, this._spans);

  final String body, vpa, ref, name;
  final int paise;

  /// null = couldn't tell which way the money went.
  final bool? inflow;

  /// Masked account numbers in order; the first is the one debited or credited.
  final List<String> accts;
  final List<(int, int)> _spans;

  String get last4 => accts.isEmpty ? '' : accts.first;

  /// This SMS read with a learned format's direction and payee.
  Parsed taught(bool inflow, String name) => Parsed(body, paise, inflow, accts, vpa, ref, name, _spans);

  /// Direction and a payee: enough to file without asking what happened.
  bool get complete => inflow != null && (vpa.isNotEmpty || name.isNotEmpty);

  /// The body with [brackets] round each fact that was read.
  String get marked {
    final b = StringBuffer();
    var i = 0;
    for (final (s, e) in [..._spans]..sort((x, y) => x.$1 - y.$1)) {
      if (s < i) continue;
      b
        ..write(body.substring(i, s))
        ..write('[${body.substring(s, e)}]');
      i = e;
    }
    return (b..write(body.substring(i))).toString();
  }
}

final _skip = RegExp(
    r'\bOTP\b|one[- ]time password|\brequest(?:ed|ing)\b|will be (?:debited|deducted|charged)|\bdue (?:on|by|date)\b|\bfailed\b|\bdeclined\b',
    caseSensitive: false);
final _amount = RegExp(
    r'(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)|\b(?:debited|credited)\s+(?:by|for|with)\s+([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false);
// 'debit by' / 'credit by': SBI's "Your A/C XXXXX4321 has a debit by NACH of Rs 2,500.00".
final _out = RegExp(r'\b(?:debited|debit by|sent|paid|spent|withdrawn|trf to|transferred to)\b', caseSensitive: false);
final _in = RegExp(r'\b(?:credited|credit by|received|deposited|refunded)\b', caseSensitive: false);
final _acct = RegExp(r'(?<![A-Za-z0-9])[Xx*]+(\d{3,6})(?!\d)');
final _vpa = RegExp(r'[A-Za-z0-9][\w.\-]*@[A-Za-z][A-Za-z0-9]*(?![\w@]|\.\w)');
final _ref = RegExp(r'\b(?:UPI|Ref|Refno|RRN)\b[^\d\n]{0,12}?(\d{12})(?!\d)', caseSensitive: false);
final _ref12 = RegExp(r'(?<![\dXx*])(\d{12})(?!\d)');
final _date = RegExp(r'\b\d{1,2}[-/]?[A-Za-z]{3}[-/]?\d{2,4}\b|\b\d{2}[-/]\d{2}[-/]\d{2,4}\b');

/// Payee name, by bank format; the first that matches wins.
final _names = [
  RegExp(r'\bto\s+([^\n]+?)\s+using\b', caseSensitive: false), // wallet: "Paid Rs.X to Swiggy using Amazon Pay UPI"
  RegExp(r';\s*([^;\n]+?)\s+credited\b', caseSensitive: false), // ICICI: "debited for Rs X on 08-Nov-26; SWIGGY credited"
  RegExp(r'\btrf to\s+(.+?)\s+Ref', caseSensitive: false), // SBI
  RegExp(r'\btransfer from\s+(.+?)\s+Ref', caseSensitive: false), // SBI credit
  RegExp(r'\bUPI/P2[AM]/\d+/([A-Za-z0-9 .&-]+?)(?:\s+Not\b|/|\n|$)', caseSensitive: false), // Axis
  RegExp(r'^To\s+(.+)$', multiLine: true), // HDFC: "Sent Rs.X\nFrom HDFC Bank A/C *1234\nTo Swiggy\nOn 05/11/26"
  RegExp(r'\bfrom\s+([A-Za-z][A-Za-z .]{0,40}?)\.?\s+(?:UPI|Ref)\b', caseSensitive: false), // ICICI credit
];

/// A group's position, which Dart's RegExpMatch doesn't expose.
(int, int)? _span(RegExpMatch m, int g) {
  final s = m[g];
  if (s == null) return null;
  final i = m.start + m[0]!.indexOf(s);
  return (i, i + s.length);
}

/// null when the SMS isn't a payment: OTPs, requests, reminders, promos.
Parsed? parseSms(String body) {
  if (_skip.hasMatch(body)) return null;
  final a = _amount.firstMatch(body);
  if (a == null) return null;
  final amount = a[1] ?? a[2]!;
  final paise = (double.parse(amount.replaceAll(',', '')) * 100).round();
  if (paise <= 0) return null;
  final spans = [_span(a, a[1] != null ? 1 : 2)!];

  final o = _out.firstMatch(body), n = _in.firstMatch(body);
  final inflow = switch ((o, n)) {
    (null, null) => null,
    (_, null) => false,
    (null, _) => true,
    (final o?, final n?) => n.start < o.start,
  };

  final accts = <String>[];
  for (final m in _acct.allMatches(body)) {
    final d = m[1]!;
    accts.add(d.length > 4 ? d.substring(d.length - 4) : d);
    spans.add(_span(m, 1)!);
  }

  final v = _vpa.firstMatch(body);
  if (v != null) spans.add((v.start, v.end));

  final r = _ref.firstMatch(body) ?? _ref12.firstMatch(body);
  if (r != null) spans.add(_span(r, 1)!);

  if (inflow == null && v == null && r == null) return null; // a balance alert or a promo

  var name = '';
  for (final re in _names) {
    final m = re.firstMatch(body);
    final clean = m == null ? '' : _cleanName(m[1]!);
    if (clean.isEmpty) continue;
    name = clean;
    spans.add(_span(m!, 1)!);
    break;
  }

  final d = _date.firstMatch(body);
  if (d != null) spans.add((d.start, d.end));

  return Parsed(body, paise, inflow, accts, v?[0] ?? '', r?[1] ?? '', name, spans);
}

final _time = RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?\b'), _numDate = RegExp(r'\b\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b');

/// What SMS in one format share: the text with your account, amounts,
/// dates, times and refs masked. A payee's masked mobile or account stays,
/// so IMPS to two people are two formats.
String smsShape(String body) {
  final a = _acct.firstMatch(body);
  var s = a == null ? body : body.replaceRange(a.start, a.end, '#');
  for (final re in [_amount, _date, _numDate, _time, RegExp(r'\d{6,}')]) {
    s = s.replaceAll(re, '#');
  }
  return s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _title(String s) =>
    s.toLowerCase().split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

String _letters(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

String _cleanName(String s) {
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll(RegExp(r'[\s.,;:]+$'), '');
  if (s.isEmpty ||
      s.contains('@') ||
      RegExp(r'\d{6,}').hasMatch(s) ||
      RegExp(r'^(?:VPA|A/?c|Acct|UPI)\b', caseSensitive: false).hasMatch(s)) {
    return '';
  }
  return _brands[_letters(s)]?.$1 ?? (s == s.toUpperCase() ? _title(s) : s);
}

/// Keyword in a VPA or payee name → (display name when it is the brand, category key).
const _brands = <String, (String?, String)>{
  'swiggy': ('Swiggy', 'food'), 'zomato': ('Zomato', 'food'), 'chaipoint': ('Chai Point', 'food'),
  'starbucks': ('Starbucks', 'food'), 'dominos': ("Domino's", 'food'), 'eatsure': ('EatSure', 'food'),
  'cafe': (null, 'food'), 'coffee': (null, 'food'), 'restaurant': (null, 'food'), 'bakery': (null, 'food'),
  'chai': (null, 'food'), 'kitchen': (null, 'food'), 'food': (null, 'food'),
  'bigbasket': ('BigBasket', 'groc'), 'blinkit': ('Blinkit', 'groc'), 'zepto': ('Zepto', 'groc'),
  'dmart': ('DMart', 'groc'), 'jiomart': ('JioMart', 'groc'), 'instamart': (null, 'groc'), 'kirana': (null, 'groc'),
  'uber': ('Uber', 'trans'), 'olacabs': ('Ola', 'trans'), 'rapido': ('Rapido', 'trans'), 'irctc': ('IRCTC', 'trans'),
  'redbus': ('redBus', 'trans'), 'fastag': (null, 'trans'), 'metro': (null, 'trans'), 'petrol': (null, 'trans'),
  'fuel': (null, 'trans'),
  'amazon': ('Amazon', 'shop'), 'flipkart': ('Flipkart', 'shop'), 'myntra': ('Myntra', 'shop'), 'ajio': ('AJIO', 'shop'),
  'meesho': ('Meesho', 'shop'), 'nykaa': ('Nykaa', 'shop'),
  'airtel': ('Airtel', 'bills'), 'jio': ('Jio', 'bills'), 'bescom': ('BESCOM', 'bills'), 'torrentpower': (null, 'bills'),
  'electricity': (null, 'bills'), 'broadband': (null, 'bills'), 'recharge': (null, 'bills'), 'bill': (null, 'bills'),
  'nobroker': ('NoBroker', 'home'), 'rent': (null, 'home'), 'society': (null, 'home'), 'maintenance': (null, 'home'),
  'apollo': ('Apollo', 'health'), 'pharmeasy': ('PharmEasy', 'health'), 'netmeds': ('Netmeds', 'health'),
  'medplus': ('MedPlus', 'health'), 'pharma': (null, 'health'), 'clinic': (null, 'health'), 'hospital': (null, 'health'),
  'bookmyshow': ('BookMyShow', 'fun'), 'netflix': ('Netflix', 'fun'), 'spotify': ('Spotify', 'fun'),
  'hotstar': ('Hotstar', 'fun'), 'pvr': ('PVR', 'fun'), 'inox': ('INOX', 'fun'),
  'makemytrip': ('MakeMyTrip', 'travel'), 'goibibo': ('Goibibo', 'travel'), 'cleartrip': ('Cleartrip', 'travel'),
  'indigo': ('IndiGo', 'travel'), 'airbnb': ('Airbnb', 'travel'), 'ixigo': ('ixigo', 'travel'),
  'udemy': ('Udemy', 'edu'), 'coursera': ('Coursera', 'edu'), 'school': (null, 'edu'), 'college': (null, 'edu'),
  'tuition': (null, 'edu'),
};

/// Longest first, so 'jiomart' wins over 'jio'.
final _brandKeys = _brands.keys.toList()..sort((a, b) => b.length - a.length);

/// Category key guessed from a payee's VPA or name: 'swiggy@icici' → 'food'.
String? guessCat(String text) {
  final s = _letters(text);
  for (final k in _brandKeys) {
    if (s.contains(k)) return _brands[k]!.$2;
  }
  return null;
}

const _apps = {
  'ybl': 'PhonePe', 'ibl': 'PhonePe', 'axl': 'PhonePe',
  'okhdfcbank': 'Google Pay', 'okaxis': 'Google Pay', 'okicici': 'Google Pay', 'oksbi': 'Google Pay',
  'paytm': 'Paytm', 'ptyes': 'Paytm', 'ptaxis': 'Paytm', 'pthdfc': 'Paytm', 'ptsbi': 'Paytm',
  'apl': 'Amazon Pay', 'yapl': 'Amazon Pay',
};

/// A readable payee from a VPA: 'asha.k@okhdfcbank' → 'Asha K',
/// 'q000000113@ybl' → 'PhonePe merchant ••0113'.
String payeeFromVpa(String vpa) {
  final at = vpa.indexOf('@');
  final local = at < 0 ? vpa : vpa.substring(0, at);
  final handle = at < 0 ? '' : vpa.substring(at + 1).toLowerCase();
  final digits = local.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 6) {
    final kind = RegExp(r'^\d').hasMatch(local) ? 'payee' : 'merchant';
    return '${_apps[handle] ?? 'UPI'} $kind ••${digits.substring(digits.length - 4)}';
  }
  final key = _letters(local);
  for (final k in _brandKeys) {
    final name = _brands[k]!.$1;
    if (name != null && key.startsWith(k)) return name;
  }
  return _title(local.split(RegExp(r'[._\-]')).where((w) => w.isNotEmpty).join(' '));
}

/// One bank (or wallet) seen in an inbox, for onboarding.
class Found {
  Found(this.bank);
  final Bank bank;

  /// Account numbers (last digits) its SMS mention.
  final accounts = <String>{};
  int count = 0;
}

/// Bank payment SMS in [inbox], grouped by bank; most SMS first, wallets last.
List<Found> scanInbox(Iterable<Sms> inbox, [List<Bank> banks = builtInBanks]) {
  final out = <String, Found>{};
  for (final s in inbox) {
    final bank = bankOf(s.sender, s.body, banks);
    final p = bank == null ? null : parseSms(s.body);
    if (p == null) continue;
    final f = out.putIfAbsent(bank!.name, () => Found(bank));
    if (!bank.dupOnly && p.last4.isNotEmpty) f.accounts.add(p.last4);
    f.count++;
  }
  return out.values.toList()
    ..sort((a, b) => a.bank.dupOnly != b.bank.dupOnly ? (a.bank.dupOnly ? 1 : -1) : b.count - a.count);
}

/// Bank payment SMS from [since] on: what an import would add.
int paymentsSince(Iterable<Sms> inbox, DateTime since, [List<Bank> banks = builtInBanks]) => inbox.where((s) {
      final bank = bankOf(s.sender, s.body, banks);
      return !s.at.isBefore(since) && bank != null && !bank.dupOnly && parseSms(s.body) != null;
    }).length;
