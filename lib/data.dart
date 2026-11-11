// Categories and the transaction model. Rows come from store.dart.
import 'package:flutter/material.dart';

import 'format.dart';

class CatColors {
  const CatColors(this.cc, this.con, this.cs);

  /// Container, on-container, solid (charts).
  final Color cc, con, cs;
}

/// A category. Equal by [key]: a renamed one is still the same category.
class Cat {
  const Cat(this.key, this.short, this.full, this.icon, this.light, this.dark);

  final String key, short, full;
  final IconData icon;
  final CatColors light, dark;

  CatColors of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? dark : light;

  @override
  bool operator ==(Object other) => other is Cat && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

const food = Cat('food', 'Food', 'Food & dining', Icons.restaurant_rounded,
    CatColors(Color(0xFFFFDFCB), Color(0xFF6A2C00), Color(0xFFD9661F)),
    CatColors(Color(0xFF5A2A0C), Color(0xFFFFD8C0), Color(0xFFF2914F)));
const groc = Cat('groc', 'Groceries', 'Groceries', Icons.shopping_basket_outlined,
    CatColors(Color(0xFFE2ECC2), Color(0xFF33420A), Color(0xFF6E8F14)),
    CatColors(Color(0xFF313F17), Color(0xFFD8E8AC), Color(0xFFA6C64A)));
const trans = Cat('trans', 'Transport', 'Transport', Icons.directions_car_outlined,
    CatColors(Color(0xFFD7E3FF), Color(0xFF0B3A7A), Color(0xFF2F6BD3)),
    CatColors(Color(0xFF173459), Color(0xFFD2E1FF), Color(0xFF7FA8F0)));
const shop = Cat('shop', 'Shopping', 'Shopping', Icons.shopping_bag_outlined,
    CatColors(Color(0xFFFBD8EB), Color(0xFF6B1847), Color(0xFFC2377F)),
    CatColors(Color(0xFF561C3E), Color(0xFFFFD5EA), Color(0xFFEE85BC)));
const bills = Cat('bills', 'Bills', 'Bills & utilities', Icons.bolt_outlined,
    CatColors(Color(0xFFFFEFB3), Color(0xFF574500), Color(0xFFB88E00)),
    CatColors(Color(0xFF463A00), Color(0xFFFFE793), Color(0xFFE2BC2E)));
const home = Cat('home', 'Home', 'Rent & home', Icons.home_outlined,
    CatColors(Color(0xFFEEDFD1), Color(0xFF4C3222), Color(0xFF8D5B3B)),
    CatColors(Color(0xFF44332A), Color(0xFFF1DCCA), Color(0xFFC99A78)));
const health = Cat('health', 'Health', 'Health', Icons.monitor_heart_outlined,
    CatColors(Color(0xFFFFDAD7), Color(0xFF77191B), Color(0xFFCF3E3E)),
    CatColors(Color(0xFF5B2220), Color(0xFFFFD8D4), Color(0xFFF08A82)));
const fun = Cat('fun', 'Fun', 'Entertainment', Icons.confirmation_number_outlined,
    CatColors(Color(0xFFE9DDFF), Color(0xFF43207A), Color(0xFF7A4FD0)),
    CatColors(Color(0xFF3A2961), Color(0xFFE9DDFF), Color(0xFFB79AF5)));
const travel = Cat('travel', 'Travel', 'Travel', Icons.flight_rounded,
    CatColors(Color(0xFFCBEEF0), Color(0xFF00464A), Color(0xFF0F8C92)),
    CatColors(Color(0xFF12424A), Color(0xFFC1EDF0), Color(0xFF5CC9CF)));
const edu = Cat('edu', 'Education', 'Education', Icons.school_outlined,
    CatColors(Color(0xFFD3EED9), Color(0xFF0E4C24), Color(0xFF2E8A55)),
    CatColors(Color(0xFF1A4229), Color(0xFFCCEED5), Color(0xFF6CCB8F)));
const other = Cat('other', 'Other', 'Other', Icons.grid_view_rounded,
    CatColors(Color(0xFFE6E8EF), Color(0xFF383C4A), Color(0xFF787E90)),
    CatColors(Color(0xFF2C3040), Color(0xFFE3E6EE), Color(0xFFA4AABB)));

/// The built-in categories; their colours are also the palette new ones pick from.
const builtInCats = [food, groc, trans, shop, bills, home, health, fun, travel, edu, other];

/// Icons a category can have, by the name stored for it. Const, so icon
/// tree-shaking keeps them.
const catIcons = <String, IconData>{
  'restaurant': Icons.restaurant_rounded,
  'basket': Icons.shopping_basket_outlined,
  'car': Icons.directions_car_outlined,
  'bag': Icons.shopping_bag_outlined,
  'bolt': Icons.bolt_outlined,
  'home': Icons.home_outlined,
  'heart': Icons.monitor_heart_outlined,
  'ticket': Icons.confirmation_number_outlined,
  'flight': Icons.flight_rounded,
  'school': Icons.school_outlined,
  'grid': Icons.grid_view_rounded,
  'coffee': Icons.local_cafe_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'phone': Icons.smartphone_outlined,
  'wifi': Icons.wifi_rounded,
  'pets': Icons.pets_outlined,
  'child': Icons.child_care_outlined,
  'gift': Icons.card_giftcard_outlined,
  'fitness': Icons.fitness_center_outlined,
  'beauty': Icons.face_retouching_natural_outlined,
  'savings': Icons.savings_outlined,
  'work': Icons.work_outline_rounded,
  'people': Icons.people_outline_rounded,
  'volunteer': Icons.volunteer_activism_outlined,
};

/// The icon name each built-in starts with.
const builtInIcons = {
  'food': 'restaurant', 'groc': 'basket', 'trans': 'car', 'shop': 'bag', 'bills': 'bolt', 'home': 'home',
  'health': 'heart', 'fun': 'ticket', 'travel': 'flight', 'edu': 'school', 'other': 'grid',
};

/// The categories in the user's order, as renamed and added. The store
/// reloads it from the database.
// ponytail: a global the store writes; widgets read it on their next build.
List<Cat> cats = builtInCats;

/// A stored category key → its category; unknown keys read as Other.
Cat? catOf(String? key) =>
    key == null ? null : cats.firstWhere((c) => c.key == key, orElse: () => cats.firstWhere((c) => c.key == 'other', orElse: () => other));

/// needs = a spend without a category; credit = money in; ignored = not
/// counted; dup = maybe a second SMS for one payment; unread = the parser
/// found an amount but not who or which way.
enum TxnStatus { needs, filed, credit, ignored, dup, unread }

class Sugg {
  const Sugg(this.cat, this.why);
  final Cat cat;
  final String why;
}

class Txn {
  const Txn({
    required this.name,
    required this.paise,
    required this.when,
    this.id = 0,
    this.vpa = '',
    this.acct = '',
    this.sender = '',
    this.ref = '',
    this.note = '',
    this.source = 'sms',
    this.cat,
    this.status = TxnStatus.filed,
    this.inflow = false,
    this.own = false,
    this.reimb = false,
    this.newPayee = false,
    this.merchantId,
    this.accountId,
    this.dupOf,
    this.refundOf,
    this.creditKind,
    this.sms,
    this.sugg = const [],
    this.tags = const {},
    this.splits = const [],
  });

  final int id, paise;

  // source: sms, cash or other (another account, typed in).
  final String name, vpa, acct, sender, ref, note, source;
  final DateTime when;
  final Cat? cat;
  final TxnStatus status;
  final bool inflow, own, reimb, newPayee;
  final int? merchantId, accountId, dupOf, refundOf;

  /// refund, moneyBack or income, once a credit is explained.
  final String? creditKind;

  /// The bank SMS with [brackets] round the facts read from it; null once purged.
  final String? sms;
  final List<Sugg> sugg;
  final Set<String> tags;

  /// (category, paise) shares, biggest first, when one payment covers
  /// several categories; empty otherwise. [cat] is the biggest share.
  final List<(Cat, int)> splits;

  bool get isCredit => inflow;

  /// "Groceries", or "Groceries +1" for a split payment.
  String get catLabel => cat == null ? '' : (splits.length < 2 ? cat!.full : '${cat!.short} +${splits.length - 1}');
  bool get manual => source != 'sms';
  String get refShort => ref.length > 4 ? '••${ref.substring(ref.length - 4)}' : ref;

  String metaLine({bool dated = false}) {
    final w = dated ? dowDayMon(when) : time12(when);
    if (manual) return '$w · ${source == 'cash' ? 'cash' : acct == 'Other account' ? 'other account' : acct} · added by you';
    if (own) return '$w · own account';
    if (status == TxnStatus.dup) return '$w · 2 SMS${ref.isEmpty ? '' : ', 1 UPI Ref'}';
    return acct.isEmpty ? w : '$w · $acct';
  }

  /// The bank SMS; [brackets] mark the facts the parser pulled out. Rebuilt
  /// from the facts once the raw SMS is past its 30 days.
  String get raw {
    final (r, p) = money(paise);
    return sms ??
        'Rs.[${r.replaceAll(',', '')}$p] ${inflow ? 'credited to' : 'debited from'}'
            '${acct.isEmpty ? '' : ' A/c [${acct.split(' ').last}]'} on [${smsDate(when)}]'
            '${vpa.isEmpty ? '' : ' ${inflow ? 'from' : 'to'} VPA [$vpa]'}.'
            '${ref.isEmpty ? '' : ' UPI Ref [$ref].'}';
  }
}
