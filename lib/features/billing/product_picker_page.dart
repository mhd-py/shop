import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/product_extensions.dart';
import '../../data/product_repository.dart';
import '../../data/tables/bill_items.dart';
import 'cart.dart';

class ProductPickerPage extends StatefulWidget {
  const ProductPickerPage({super.key, required this.repo, required this.cart});
  final ProductRepository repo;
  final CartController cart;

  @override
  State<ProductPickerPage> createState() => _ProductPickerPageState();
}

class _ProductPickerPageState extends State<ProductPickerPage> {
  late final Stream<List<Product>> _products = widget.repo.watchAll();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _add(Product p, SaleUnit unit) {
    final error = widget.cart.add(p, unit);
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Widget _tile(Product p) {
    final theme = Theme.of(context);
    final inCart = widget.cart.piecesInCart(p.id);
    final price = CartController.canSellPack(p)
        ? 'Piece ${formatRupees(p.sellPiecePaise)}  ·  Pack ${formatRupees(p.sellPackPaise!)}'
        : formatRupees(p.sellPiecePaise);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(p.name, style: theme.textTheme.titleMedium)),
                Text(p.isOut ? 'Out of stock' : p.stockText,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: p.isOut ? theme.colorScheme.error : null)),
              ],
            ),
            const SizedBox(height: 2),
            Text(price, style: theme.textTheme.bodySmall),
            if (inCart > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('In cart: ${formatStock(inCart, p.packSize)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: p.isOut ? null : () => _add(p, SaleUnit.piece),
                  child: const Text('+ Piece'),
                ),
                if (CartController.canSellPack(p))
                  FilledButton.tonal(
                    onPressed: p.isOut ? null : () => _add(p, SaleUnit.pack),
                    child: const Text('+ Pack'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add products'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search products',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                          ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Product>>(
                  stream: _products,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Error: ${snap.error}'));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final q = ProductRepository.keyOf(_search.text);
                    final shown = snap.data!
                        .where((p) => q.isEmpty || p.nameKey.contains(q))
                        .toList();
                    if (shown.isEmpty) {
                      return const Center(child: Text('No matching products.'));
                    }
                    return ListenableBuilder(
                      listenable: widget.cart,
                      builder: (context, _) => ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: shown.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) => _tile(shown[index]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
