import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/money.dart';
import '../../core/upi.dart';
import '../../data/bill_repository.dart';
import '../../data/customer_repository.dart';
import '../../data/database.dart';
import '../../data/settings_repository.dart';
import '../../data/tables/bill_items.dart';
import '../../data/tables/bills.dart';
import 'cart.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({
    super.key,
    required this.bills,
    required this.cart,
    required this.settings,
    required this.customers,
  });
  final BillRepository bills;
  final CartController cart;
  final SettingsRepository settings;
  final CustomerRepository customers;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  static const _quick = [5000, 10000, 20000, 50000];

  final _received = TextEditingController();
  final _search = TextEditingController();
  late final int _subtotal = widget.cart.total;
  final _discountCtl = TextEditingController();
  int get _discountPaise => _method == PaymentMethod.cash
      ? (parseRupees(_discountCtl.text) ?? 0)
      : 0;
  bool get _discountOk => _discountPaise >= 0 && _discountPaise < _subtotal;
  int get _total => _discountOk ? _subtotal - _discountPaise : _subtotal;
  late final List<CartLine> _lines = widget.cart.toLines();
  late final Stream<String> _upiId = widget.settings.watchUpiId();
  late final Stream<String> _shopName = widget.settings.watchShopName();
  late final Stream<List<Customer>> _customers = widget.customers.watchAll();
  PaymentMethod _method = PaymentMethod.cash;
  int? _customerId;
  bool _busy = false;
  String? _error;
  Bill? _saved;
  Stream<List<BillItem>>? _items;

  @override
  void dispose() {
    _received.dispose();
    _discountCtl.dispose();
    _search.dispose();
    super.dispose();
  }

  int get _receivedPaise => parseRupees(_received.text) ?? 0;

  bool get _canConfirm {
    if (_busy || !_discountOk) return false;
    switch (_method) {
      case PaymentMethod.cash:
        return _receivedPaise >= _total;
      case PaymentMethod.upi:
        return true;
      case PaymentMethod.khata:
        return _customerId != null;
    }
  }

  String get _confirmLabel {
    if (_busy) return 'Saving...';
    switch (_method) {
      case PaymentMethod.cash:
        return 'Confirm payment';
      case PaymentMethod.upi:
        return 'Payment received';
      case PaymentMethod.khata:
        return 'Add to Khata';
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bill = await widget.bills.checkout(
        method: _method,
        lines: _lines,
        discountPaise: _discountOk ? _discountPaise : 0,
        receivedPaise: _method == PaymentMethod.cash ? _receivedPaise : null,
        customerId: _method == PaymentMethod.khata ? _customerId : null,
      );
      widget.cart.clear();
      if (mounted) {
        setState(() {
          _saved = bill;
          _items = widget.bills.watchItems(bill.id);
        });
      }
    } on BillException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on CustomerException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String label, String value, {bool big = false}) {
    final style = big
        ? Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.titleMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }

  // ---------- saved ----------

  Widget _itemsCard() {
    final theme = Theme.of(context);
    return StreamBuilder<List<BillItem>>(
      stream: _items,
      builder: (context, snap) {
        final items = snap.data ?? const <BillItem>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(i.productName,
                                  style: theme.textTheme.titleMedium),
                              Text(
                                '${i.quantity} ${i.unit == SaleUnit.pack ? 'pack' : 'pc'}'
                                ' × ${formatRupees(i.unitPricePaise)}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(formatRupees(i.lineTotalPaise),
                            style: theme.textTheme.titleMedium),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _savedView() {
    final theme = Theme.of(context);
    final b = _saved!;
    final rows = <Widget>[
      if (b.discountPaise > 0) ...[
        _row('Subtotal', formatRupees(b.totalPaise + b.discountPaise)),
        _row('Discount', '- ${formatRupees(b.discountPaise)}'),
      ],
      _row('Total', formatRupees(b.totalPaise)),
    ];
    switch (b.paymentMethod) {
      case PaymentMethod.cash:
        rows
          ..add(_row('Paid by', 'Cash'))
          ..add(_row('Received', formatRupees(b.receivedPaise ?? 0)))
          ..add(_row('Change to return', formatRupees(b.changePaise ?? 0),
              big: true));
      case PaymentMethod.upi:
        rows.add(_row('Paid by', 'UPI', big: true));
      case PaymentMethod.khata:
        rows
          ..add(_row('Customer', b.customerName ?? ''))
          ..add(_row('Added to Khata', formatRupees(b.totalPaise), big: true));
    }
    return ListView(
      children: [
        Center(
          child: Icon(Icons.check_circle,
              size: 72, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 12),
        Center(child: Text('Bill saved', style: theme.textTheme.headlineSmall)),
        Center(
            child: Text('Bill ${b.billNumber}',
                style: theme.textTheme.bodyMedium)),
        const SizedBox(height: 24),
        _itemsCard(),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: rows),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  // ---------- method sections ----------

  Widget _cashSection() {
    final change = _receivedPaise - _total;
    final quick = _quick.where((q) => q >= _total).toList();
    final empty = _received.text.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _received,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Cash received',
            prefixText: '₹ ',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: const Text('Exact'),
              onPressed: () => setState(
                  () => _received.text = (_total / 100).toStringAsFixed(2)),
            ),
            for (final q in quick)
              ActionChip(
                label: Text('₹${q ~/ 100}'),
                onPressed: () =>
                    setState(() => _received.text = '${q ~/ 100}'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _receivedPaise < _total
                ? _row(empty ? 'Change' : 'Still needed',
                    empty ? '—' : formatRupees(_total - _receivedPaise),
                    big: true)
                : _row('Change to return', formatRupees(change), big: true),
          ),
        ),
      ],
    );
  }

  Widget _upiSection() {
    final theme = Theme.of(context);
    return StreamBuilder<String>(
      stream: _upiId,
      initialData: '',
      builder: (context, upiSnap) {
        final upi = upiSnap.data ?? '';
        if (validateUpiId(upi) != null) {
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No UPI ID is set. Open the Settings tab, add your UPI ID, '
                'then come back to show the QR code.\n\n'
                'If the customer has already paid some other way, you can '
                'still tap "Payment received".',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          );
        }
        return StreamBuilder<String>(
          stream: _shopName,
          initialData: '',
          builder: (context, nameSnap) {
            final uri = buildUpiUri(
                upiId: upi, name: nameSnap.data ?? '', amountPaise: _total);
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Ask the customer to scan and pay',
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    QrImageView(
                      data: uri,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Text(formatRupees(_total),
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(upi, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _khataSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search customer by name or phone',
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: StreamBuilder<List<Customer>>(
            stream: _customers,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final q = _search.text.trim().toLowerCase();
              final list = snap.data!
                  .where((c) =>
                      q.isEmpty ||
                      c.name.toLowerCase().contains(q) ||
                      c.phone.contains(q))
                  .toList();
              if (list.isEmpty) {
                return Center(
                  child: Text(
                    snap.data!.isEmpty
                        ? 'No customers yet. Add one in the Khata tab.'
                        : 'No matching customers.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final c = list[i];
                  final selected = c.id == _customerId;
                  return Card(
                    margin: EdgeInsets.zero,
                    color: selected ? theme.colorScheme.primaryContainer : null,
                    child: ListTile(
                      title: Text(c.name),
                      subtitle: Text(c.balancePaise > 0
                          ? '${c.phone}  ·  Owes ${formatRupees(c.balancePaise)}'
                          : c.phone),
                      trailing: selected
                          ? Icon(Icons.check_circle,
                              color: theme.colorScheme.primary)
                          : null,
                      onTap: () => setState(() => _customerId = c.id),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _payView() {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              if (_discountOk && _discountPaise > 0) ...[
                _row('Subtotal', formatRupees(_subtotal)),
                _row('Discount', '- ${formatRupees(_discountPaise)}'),
              ],
              _row('Total payable', formatRupees(_total), big: true),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<PaymentMethod>(
          segments: const [
            ButtonSegment(
                value: PaymentMethod.cash,
                icon: Icon(Icons.payments_outlined),
                label: Text('Cash')),
            ButtonSegment(
                value: PaymentMethod.upi,
                icon: Icon(Icons.qr_code_2),
                label: Text('UPI')),
            ButtonSegment(
                value: PaymentMethod.khata,
                icon: Icon(Icons.menu_book_outlined),
                label: Text('Khata')),
          ],
          selected: {_method},
          onSelectionChanged: (s) => setState(() {
            _method = s.first;
            _error = null;
          }),
        ),
        if (_method == PaymentMethod.cash) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _discountCtl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Discount (optional)',
              prefixText: '₹ ',
              border: const OutlineInputBorder(),
              errorText: _discountOk
                  ? null
                  : 'Must be less than ${formatRupees(_subtotal)}',
            ),
          ),
        ],
        const SizedBox(height: 16),
        switch (_method) {
          PaymentMethod.cash => _cashSection(),
          PaymentMethod.upi => _upiSection(),
          PaymentMethod.khata => _khataSection(),
        },
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!,
                style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _canConfirm ? _confirm : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_confirmLabel),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _saved == null,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_saved == null ? 'Payment' : 'Done'),
          automaticallyImplyLeading: _saved == null,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _saved == null ? _payView() : _savedView(),
            ),
          ),
        ),
      ),
    );
  }
}
