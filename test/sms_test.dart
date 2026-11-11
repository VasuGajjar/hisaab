import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/sms.dart';

void main() {
  test('bank from the sender ID, else the text', () {
    expect(bankOf('VM-HDFCBK', '')?.name, 'HDFC');
    expect(bankOf('JD-AXISBK-S', '')?.name, 'Axis');
    expect(bankOf('ax-amzpay', '…from HDFC Bank XX1111')?.name, 'Amazon Pay'); // sender ID wins
    expect(bankOf('+919800000001', 'Rs.450 debited from your Axis Bank a/c')?.name, 'Axis');
    expect(bankOf('', 'credited to your Central Bank of India a/c')?.name, 'Central Bank'); // earliest match
    expect(bankOf('VM-SWIGGY', 'Rs.450 paid to swiggy@icici'), isNull); // a UPI ID names the payee's bank
    // A phone number as a sender: its digits, however the carrier writes them.
    const mine = [Bank('Test', ['9000011111'], [])];
    expect(bankOf('+91 90000-11111', '', mine)?.name, 'Test');
    expect(bankOf('+919000022222', '', mine), isNull);
  });

  test('HDFC UPI debit', () {
    final p = parseSms('Rs.450.00 debited from A/c XX1111 on 08-11-26 to VPA swiggy@icici. UPI Ref 631200000008.')!;
    expect((p.paise, p.inflow, p.last4, p.vpa, p.ref, p.complete), (45000, false, '1111', 'swiggy@icici', '631200000008', true));
    expect(p.marked, 'Rs.[450.00] debited from A/c XX[1111] on [08-11-26] to VPA [swiggy@icici]. UPI Ref [631200000008].');
  });

  test('HDFC credit, VPA ends in a bracket', () {
    final p = parseSms('Rs.1200.00 credited to A/c XX1111 on 08-11-26 from VPA asha.k@okhdfcbank (UPI Ref 631200000007).')!;
    expect((p.paise, p.inflow, p.vpa, p.ref, p.name), (120000, true, 'asha.k@okhdfcbank', '631200000007', ''));
  });

  test('HDFC multi-line "Sent"', () {
    final p = parseSms('Sent Rs.212.00\nFrom HDFC Bank A/C *1111\nTo UBER INDIA\nOn 08/11/26\nRef 631200000006\nNot You?\n'
        'Call 18002586161/SMS BLOCK UPI to 7308080808')!;
    expect((p.paise, p.inflow, p.last4, p.name, p.ref), (21200, false, '1111', 'Uber India', '631200000006'));
  });

  test('ICICI debit: payee before "credited", 3-digit account', () {
    final p = parseSms('ICICI Bank Acct XX222 debited for Rs 1,326.40 on 07-Nov-26; BIGBASKET credited. UPI:631200000021. '
        'Call 18002662 for dispute.')!;
    expect((p.paise, p.inflow, p.last4, p.name, p.ref), (132640, false, '222', 'BigBasket', '631200000021'));
  });

  test('ICICI credit', () {
    final p = parseSms('Dear Customer, Acct XX222 is credited with Rs 1200.00 on 08-Nov-26 from ASHA K. UPI:631200000007-ICICI Bank.')!;
    expect((p.inflow, p.name, p.ref), (true, 'Asha K', '631200000007'));
  });

  test('SBI, amount without Rs', () {
    final p = parseSms('Dear UPI user A/C X1234 debited by 450.0 on date 08Nov26 trf to SWIGGY Refno 631200000008. '
        'If not u? call 1800111109. -SBI')!;
    expect((p.paise, p.inflow, p.last4, p.name, p.ref), (45000, false, '1234', 'Swiggy', '631200000008'));
  });

  test('SBI NACH: "has a debit by", no payee', () {
    final p = parseSms('Dear Customer, Your A/C XXXXX654321 has a debit by NACH of Rs 2,500.00 on 11/11/26. '
        'Avl Bal Rs 50,123.45. Download YONO - SBI')!;
    expect((p.paise, p.inflow, p.last4, p.complete), (250000, false, '4321', false));
    expect(bankOf('JX-CBSSBI-S', p.body)?.name, 'SBI');
    expect(parseSms('Your A/C XXXXX654321 has a credit by NEFT of Rs 10,000.00 on 11/11/26.')!.inflow, true);
  });

  test('Axis', () {
    final p = parseSms('INR 450.00 debited\nA/c no. XX1234\n08-11-26, 13:42:10\nUPI/P2M/631200000008/SWIGGY\n'
        'Not you? SMS BLOCKUPI Cust ID to 919900000023\nAxis Bank')!;
    expect((p.paise, p.inflow, p.name, p.ref), (45000, false, 'Swiggy', '631200000008'));
  });

  test('Amazon Pay echo', () {
    final p = parseSms('Paid Rs.299.00 to Zomato using Amazon Pay UPI from HDFC Bank XX1111. Ref 631200000020.')!;
    expect((p.paise, p.inflow, p.last4, p.name, p.ref), (29900, false, '1111', 'Zomato', '631200000020'));
  });

  test('IMPS: amount but no payee, mobile number is not an account', () {
    final p = parseSms('Your a/c no. XXXXXXXX1111 is debited for Rs.2150.00 on 06-11-26 and a/c linked to mobile '
        '9XXXXXX000 credited (IMPS Ref no 631000000004).')!;
    expect((p.paise, p.accts.join(), p.complete), (215000, '1111', false));
  });

  test('own transfer lists both accounts', () {
    expect(parseSms('Rs.5000.00 debited from A/c XX1111 on 07-11-26 to A/c XX2222. IMPS Ref 631200000017.')!.accts,
        ['1111', '2222']);
  });

  test('not payments', () {
    expect(parseSms('123456 is your OTP for txn of Rs.2,500.00 at AMAZON on HDFC Bank card XX1111.'), isNull);
    expect(parseSms('Asha has requested Rs.500 from you on UPI. Pay via any app.'), isNull);
    expect(parseSms('Get a personal loan up to Rs 5,00,000 at 10.5%. Apply now!'), isNull);
    expect(parseSms('Reached home. Call you at 8?'), isNull);
  });

  test('payee names from VPAs', () {
    expect(payeeFromVpa('asha.k@okhdfcbank'), 'Asha K');
    expect(payeeFromVpa('chaipoint@axisbank'), 'Chai Point');
    expect(payeeFromVpa('uberindia@ybl'), 'Uber');
    expect(payeeFromVpa('q000000113@ybl'), 'PhonePe merchant ••0113');
    expect(payeeFromVpa('9876543210@okaxis'), 'Google Pay payee ••3210');
    expect(guessCat('swiggy@icici'), 'food');
    expect(guessCat('jiomart@hdfcbank'), 'groc');
    expect(guessCat('asha.k@okhdfcbank'), isNull);
  });

  test('inbox scan groups by bank, wallets last', () {
    final at = DateTime(2026, 11, 8);
    final found = scanInbox([
      (sender: 'AX-AMZPAY', body: 'Paid Rs.299.00 to Zomato using Amazon Pay UPI from HDFC Bank XX1111. Ref 631200000020.', at: at),
      (sender: 'VM-HDFCBK', body: 'Rs.450.00 debited from A/c XX1111 on 08-11-26 to VPA swiggy@icici. UPI Ref 631200000008.', at: at),
      (sender: 'AD-HDFCBK', body: 'Rs.180.00 debited from A/c XX1111 on 08-11-26 to VPA a@ybl. UPI Ref 631200000009.', at: at),
      (sender: 'VK-ICICIB', body: 'ICICI Bank Acct XX2222 debited for Rs 10.00 on 07-Nov-26; X credited. UPI:631200000021.', at: at),
      (sender: 'BX-PROMOS', body: 'Rs.100 debited to VPA a@ybl UPI Ref 631200000022', at: at),
    ]);
    // Wallets add no accounts: the account in an Amazon Pay SMS is the bank's.
    expect([for (final f in found) (f.bank.name, f.count, f.accounts.join(','))],
        [('HDFC', 2, '1111'), ('ICICI', 1, '2222'), ('Amazon Pay', 1, '')]);
  });
}
