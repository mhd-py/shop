import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/tables/bill_items.dart';
import '../../data/tables/bills.dart';

String formatDateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '${d.day}/${d.month}/${d.year}  $h:$m $ap';
}

String paymentLabel(PaymentMethod m) => switch (m) {
      PaymentMethod.cash => 'Cash',
      PaymentMethod.upi => 'UPI',
      PaymentMethod.khata => 'Khata',
    };

/// Plain-text receipt for sharing.
String billText(Bill b, List<BillItem> items, {String shopName = ''}) {
  final o = StringBuffer();
  if (shopName.trim().isNotEmpty) o.writeln(shopName.trim());
  o.writeln('Bill ${b.billNumber}');
  o.writeln(formatDateTime(b.createdAt));
  if (b.cancelledAt != null) o.writeln('*** CANCELLED ***');
  o.writeln('------------------------');
  for (final i in items) {
    final unit = i.unit == SaleUnit.pack ? 'pack' : 'pc';
    o.writeln(i.productName);
    o.writeln('  ${i.quantity} $unit x ${formatRupees(i.unitPricePaise)}'
        '  =  ${formatRupees(i.lineTotalPaise)}');
    if (i.returnedQty > 0) o.writeln('  (returned ${i.returnedQty})');
  }
  o.writeln('------------------------');
  if (b.discountPaise > 0) {
    o.writeln('Subtotal: ${formatRupees(b.totalPaise + b.discountPaise)}');
    o.writeln('Discount: -${formatRupees(b.discountPaise)}');
  }
  o.writeln('Total: ${formatRupees(b.totalPaise)}');
  if (b.returnedPaise > 0) {
    o.writeln('Returned: -${formatRupees(b.returnedPaise)}');
    o.writeln('Net: ${formatRupees(b.totalPaise - b.returnedPaise)}');
  }
  o.write('Paid by: ${paymentLabel(b.paymentMethod)}');
  if (b.paymentMethod == PaymentMethod.khata && b.customerName != null) {
    o.write(' (${b.customerName})');
  }
  o.writeln();
  return o.toString();
}
