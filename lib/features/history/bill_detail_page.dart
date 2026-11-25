import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../core/share_text.dart';
import '../../data/bill_repository.dart';
import '../../data/database.dart';
import '../../data/settings_repository.dart';
import '../../data/tables/bill_items.dart';
import 'bill_text.dart';

class BillDetailPage extends StatefulWidget {
  const BillDetailPage({
    super.key,
    required this.billId,
    required this.bills,
    required this.settings,
  });
  final int billId;
  final BillRepository bills;
  final SettingsRepository settings;

  @override
  State<BillDetailPage> createState() => _BillDetailPageState();
}

class _BillDetailPageState extends State<BillDetailPage> {
  late final Stream<Bill?> _bill = widget.bills.watchBill(widget.billId);
  late final Stream<List<BillItem>> _items =
      widget.bills.watchItems(widget.billId);

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _share(Bill b, List<BillItem> items) async {
    final shop = await widget.settings.watchShopName().first;
    final ok = await shareText(billText(b, items, shopName: shop),
        subject: 'Bill ${b.billNumber}');
    if (!ok) _snack('Sharing is not available here. Try on the phone.');
  }

  Future<void> _showRefund(RefundResult r) {
    final lines = <String>['Refund: ${formatRupees(r.refundPaise)}'];
    if (r.toKhataPaise > 0) {
      lines.add('${formatRupees(r.toKhataPaise)} taken off the Khata balance.');
    }
    if (r.handBackPaise > 0) {
      lines.add('Give ${formatRupees(r.handBackPaise)} back to the customer.');
    }
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle),
        title: const Text('Done'),
        content: Text(lines.join('\n\n')),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _cancel(Bill b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
        title: Text('Cancel bill ${b.billNumber}?'),
        content: const Text('Stock is put back and the bill is marked '
            'cancelled. For a Khata bill the customer balance is reduced. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep bill')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel bill'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _showRefund(await widget.bills.cancelBill(b.id));
    } on BillException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _return(Bill b, List<BillItem> items) async {
    final picked = await showDialog<Map<int, int>>(
      context: context,
      builder: (_) => _ReturnDialog(items: items),
    );
    if (picked == null) return;
    try {
      await _showRefund(await widget.bills.returnItems(b.id, picked));
    } on BillException catch (e) {
      _snack(e.message);
    }
  }

  Widget _row(String l, String v, {bool bold = false, Color? color}) {
    final s = TextStyle(
        fontWeight: bold ? FontWeight.w700 : null,
        fontSize: bold ? 18 : null,
        color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(l, style: s)),
        Text(v, style: s),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<Bill?>(
      stream: _bill,
      builder: (context, bs) {
        final b = bs.data;
        return StreamBuilder<List<BillItem>>(
          stream: _items,
          builder: (context, is_) {
            final items = is_.data ?? const <BillItem>[];
            if (b == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Bill')),
                body: const Center(child: CircularProgressIndicator()),
              );
            }
            final cancelled = b.cancelledAt != null;
            final canReturn =
                !cancelled && items.any((i) => i.returnedQty < i.quantity);
            return Scaffold(
              appBar: AppBar(
                title: Text('Bill ${b.billNumber}'),
                actions: [
                  IconButton(
                    tooltip: 'Share',
                    icon: const Icon(Icons.share),
                    onPressed: () => _share(b, items),
                  ),
                ],
              ),
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (cancelled)
                        Card(
                          color: theme.colorScheme.errorContainer,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                                'Cancelled on ${formatDateTime(b.cancelledAt!)}',
                                style: TextStyle(
                                    color: theme.colorScheme.onErrorContainer,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      Text(formatDateTime(b.createdAt)),
                      Text(
                          'Paid by ${paymentLabel(b.paymentMethod)}'
                          '${b.customerName != null ? ' · ${b.customerName}' : ''}',
                          style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 12),
                      for (final i in items)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(i.productName),
                            subtitle: Text(
                                '${i.quantity} ${i.unit == SaleUnit.pack ? 'pack' : 'pc'}'
                                ' × ${formatRupees(i.unitPricePaise)}'
                                '${i.returnedQty > 0 ? '\nReturned: ${i.returnedQty}' : ''}'),
                            isThreeLine: i.returnedQty > 0,
                            trailing: Text(formatRupees(i.lineTotalPaise),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            if (b.discountPaise > 0) ...[
                              _row('Subtotal',
                                  formatRupees(b.totalPaise + b.discountPaise)),
                              _row('Discount',
                                  '- ${formatRupees(b.discountPaise)}'),
                            ],
                            _row('Total', formatRupees(b.totalPaise),
                                bold: true),
                            if (b.returnedPaise > 0) ...[
                              _row('Returned',
                                  '- ${formatRupees(b.returnedPaise)}',
                                  color: theme.colorScheme.error),
                              _row('Net',
                                  formatRupees(b.totalPaise - b.returnedPaise),
                                  bold: true),
                            ],
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!cancelled) ...[
                        FilledButton.tonalIcon(
                          onPressed: canReturn ? () => _return(b, items) : null,
                          icon: const Icon(Icons.assignment_return_outlined),
                          label: const Text('Return items'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red),
                          onPressed: () => _cancel(b),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel whole bill'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ReturnDialog extends StatefulWidget {
  const _ReturnDialog({required this.items});
  final List<BillItem> items;

  @override
  State<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<_ReturnDialog> {
  final Map<int, int> _qty = {};

  @override
  Widget build(BuildContext context) {
    final rows = widget.items.where((i) => i.returnedQty < i.quantity);
    final any = _qty.values.any((q) => q > 0);
    return AlertDialog(
      title: const Text('Return items'),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final i in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(i.productName),
                subtitle: Text(
                    'Can return ${i.quantity - i.returnedQty} '
                    '${i.unit == SaleUnit.pack ? 'pack' : 'pc'}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: (_qty[i.id] ?? 0) > 0
                          ? () => setState(() => _qty[i.id] = _qty[i.id]! - 1)
                          : null,
                    ),
                    Text('${_qty[i.id] ?? 0}'),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: (_qty[i.id] ?? 0) < i.quantity - i.returnedQty
                          ? () => setState(
                              () => _qty[i.id] = (_qty[i.id] ?? 0) + 1)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: any ? () => Navigator.pop(context, _qty) : null,
          child: const Text('Return'),
        ),
      ],
    );
  }
}
