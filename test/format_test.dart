import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/format.dart';

void main() {
  test('en_IN grouping', () {
    expect(groupIN(0), '0');
    expect(groupIN(999), '999');
    expect(groupIN(1000), '1,000');
    expect(groupIN(125000), '1,25,000');
    expect(groupIN(1234567), '12,34,567');
    expect(groupIN(-14366), '-14,366');
    expect(rupees(132640), '₹1,326.40');
    expect(rupees(1436690, dec: false), '₹14,366');
  });

  test('dates', () {
    final t = DateTime(2026, 11, 8, 13, 42);
    expect(time12(t), '1:42 pm');
    expect(time12(DateTime(2026, 11, 8, 0, 5)), '12:05 am');
    expect(dowDayMon(t), 'Sun 08 Nov');
    expect(smsDate(t), '08-11-26');
  });

  test('keypad', () {
    String type(String keys) => keys.split('').fold('', keypadInput);
    expect(type('120'), '120');
    expect(type('0012'), '12');
    expect(type('.5'), '0.5');
    expect(type('12.345'), '12.34');
    expect(type('1.2.3'), '1.23');
    expect(type('12345678'), '1234567');
    expect(keypadInput('12', '⌫'), '1');
    expect(keypadInput('', '⌫'), '');
    expect(keypadInput('12.5', 'C'), '');
    expect(keypadPaise(''), 0);
    expect(keypadPaise('120'), 12000);
    expect(keypadPaise('12.5'), 1250);
    expect(keypadPaise('12.'), 1200);
  });
}
