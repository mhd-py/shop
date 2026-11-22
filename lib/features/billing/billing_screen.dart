import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/product_repository.dart';
import '../../data/tables/bill_items.dart';
import '../../data/bill_repository.dart';
import '../../data/customer_repository.dart';
import '../../data/settings_repository.dart';
import 'cart.dart';
import 'checkout_page.dart';
import 'product_picker_page.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({
    super.key,
    required this.products,
    required this.bills,
    required this.settings,
    required this.customers,
  });
  final ProductRepository products;
  final BillRepository bills;
  final SettingsRepository settings;
  final CustomerRepository customers;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _cart = CartController();

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPicker() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ProductPickerPage(repo: widget.products, cart: _cart),
        ),
      );

  Future<void> _checkout() async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutPage(
          bills: widget.bills,
          cart: _cart,
          settings: widget.settings,
          customers: widget.customers,
        ),
      ),
    );
    if (done == true) _toast('Bill saved');
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('All items will be removed from this bill.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) _cart.clear();
  }

  void _change(String? error) {
    if (error != null) _toast(error);
  }

  Widget _line(CartItem item) {
    final theme = Theme.of(context);
    final unitName = item.unit == SaleUnit.pack ? 'Pack' : 'Piece';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.product.name,
                      style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _cart.remove(item),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text('$unitName  ·  ${formatRupees(item.unitPrice)}',
                      style: theme.textTheme.bodySmall),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed:
                      item.quantity > 1 ? () => _cart.decrease(item) : null,
                ),
                SizedBox(
                  width: 28,
                  child: Text('${item.quantity}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _change(_cart.increase(item)),
                ),
                SizedBox(
                  width: 80,
                  child: Text(formatRupees(item.lineTotal),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Cart is empty', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openPicker,
            icon: const Icon(Icons.add),
            label: const Text('Add products'),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total', style: theme.textTheme.bodySmall),
                Text(formatRupees(_cart.total),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const Spacer(),
            OutlinedButton(
                onPressed: _openPicker, child: const Text('Add more')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _checkout,
              child: const Text('Checkout'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _cart,
      builder: (context, _) {
        final items = _cart.items;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Billing'),
            actions: [
              if (items.isNotEmpty)
                IconButton(
                  tooltip: 'Clear cart',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: _confirmClear,
                ),
            ],
          ),
          bottomNavigationBar: items.isEmpty ? null : _bottomBar(),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: items.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) => _line(items[index]),
                    ),
            ),
          ),
        );
      },
    );
  }
}
