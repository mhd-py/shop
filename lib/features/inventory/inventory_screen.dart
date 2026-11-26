import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/product_extensions.dart';
import '../../data/product_repository.dart';
import '../../data/settings_repository.dart';
import '../scan/scan_bill_page.dart';
import 'product_form_page.dart';

enum _Filter { all, low, out }

enum _MergeChoice { keepOld, useNew }

String _priceSummary(int packSize, int cost, int sellPiece, int? sellPack) {
  if (packSize <= 1) {
    return 'Cost ${formatRupees(cost)}  ·  Sell ${formatRupees(sellPiece)}';
  }
  return 'Cost ${formatRupees(cost)}/pack  ·  '
      'Sell ${formatRupees(sellPack ?? 0)}/pack, ${formatRupees(sellPiece)}/pc';
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.repo,
    required this.settings,
  });
  final ProductRepository repo;
  final SettingsRepository settings;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late final Stream<List<Product>> _products = widget.repo.watchAll();
  late final Stream<int> _limit = widget.settings.watchLowStockThreshold();
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- actions ----------

  Future<void> _add() async {
    final input = await Navigator.push<ProductInput>(
      context,
      MaterialPageRoute(builder: (_) => const ProductFormPage()),
    );
    if (input == null || !mounted) return;
    final existing = await widget.repo.findByName(input.name);
    if (!mounted) return;
    if (existing == null) {
      await widget.repo.add(input);
      if (mounted) _toast('Product added');
    } else {
      await _handleDuplicate(existing, input);
    }
  }

  Future<void> _handleDuplicate(Product existing, ProductInput input) async {
    if (existing.packSize != input.packSize) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Looks like a different product'),
          content: Text(
              '"${existing.name}" already exists with pack size ${existing.packSize}, '
              'but you entered pack size ${input.packSize}. To avoid mixing '
              'different products, change the name (for example add the pack '
              'size) and try again.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    final samePrices = existing.costPaise == input.costPaise &&
        existing.sellPiecePaise == input.sellPiecePaise &&
        existing.sellPackPaise == input.sellPackPaise;

    final choice = await showDialog<_MergeChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Product already exists'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing.name, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('In stock: ${existing.stockText}'),
              Text('Adding: ${formatStock(input.stockPieces, input.packSize)}'),
              if (!samePrices) ...[
                const SizedBox(height: 12),
                const Text('The prices are different:'),
                Text(
                    'Old: ${_priceSummary(existing.packSize, existing.costPaise, existing.sellPiecePaise, existing.sellPackPaise)}'),
                Text(
                    'New: ${_priceSummary(input.packSize, input.costPaise, input.sellPiecePaise, input.sellPackPaise)}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          if (samePrices)
            FilledButton(
                onPressed: () => Navigator.pop(ctx, _MergeChoice.keepOld),
                child: const Text('Merge stock'))
          else ...[
            OutlinedButton(
                onPressed: () => Navigator.pop(ctx, _MergeChoice.keepOld),
                child: const Text('Merge, keep old prices')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, _MergeChoice.useNew),
                child: const Text('Merge, use new prices')),
          ],
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await widget.repo
        .merge(existing, input, useNewPrices: choice == _MergeChoice.useNew);
    if (mounted) _toast('Merged into existing product');
  }

  Future<void> _edit(Product p) async {
    final input = await Navigator.push<ProductInput>(
      context,
      MaterialPageRoute(builder: (_) => ProductFormPage(existing: p)),
    );
    if (input == null || !mounted) return;
    final clash = await widget.repo.findByName(input.name);
    if (!mounted) return;
    if (clash != null && clash.id != p.id) {
      _toast('Another product already uses this name');
      return;
    }
    await widget.repo.update(p.id, input);
    if (mounted) _toast('Product updated');
  }

  Future<void> _confirmDelete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('"${p.name}" will be removed from inventory.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repo.delete(p.id);
    if (mounted) _toast('Product deleted');
  }

  Future<void> _editLimit(int current) async {
    final c = TextEditingController(text: '$current');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Low stock limit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Show a low-stock alert when stock is at or below this '
                'number. For pack products it counts packs; for other '
                'products it counts pieces.'),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())),
              child: const Text('Save')),
        ],
      ),
    );
    if (value == null || value < 0) return;
    await widget.settings.setLowStockThreshold(value);
    if (mounted) _toast('Low stock limit set to $value');
  }

  // ---------- list helpers ----------

  List<Product> _apply(List<Product> all, int limit) {
    final q = ProductRepository.keyOf(_search.text);
    return all.where((p) {
      if (q.isNotEmpty && !p.nameKey.contains(q)) return false;
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.low:
          return p.isLow(limit);
        case _Filter.out:
          return p.isOut;
      }
    }).toList();
  }

  String _emptyText(bool noProducts) {
    if (noProducts) return 'No products yet. Tap "Add product".';
    switch (_filter) {
      case _Filter.low:
        return 'No low-stock items.';
      case _Filter.out:
        return 'No items are out of stock.';
      case _Filter.all:
        return 'No matching products.';
    }
  }

  Widget _chips(List<Product> all, int limit) {
    final low = all.where((p) => p.isLow(limit)).length;
    final out = all.where((p) => p.isOut).length;
    Widget chip(String label, _Filter f) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _filter == f,
            onSelected: (_) => setState(() => _filter = f),
          ),
        );
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip('All (${all.length})', _Filter.all),
          chip('Low stock ($low)', _Filter.low),
          chip('Out of stock ($out)', _Filter.out),
        ],
      ),
    );
  }

  Widget _tile(Product p, int limit) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final out = p.isOut;
    final low = p.isLow(limit);
    final badgeBg = out
        ? scheme.errorContainer
        : (low ? scheme.tertiaryContainer : null);
    final badgeFg = out ? scheme.onErrorContainer : scheme.onTertiaryContainer;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(p),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      _priceSummary(p.packSize, p.costPaise, p.sellPiecePaise,
                          p.sellPackPaise),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(p.stockText,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (badgeBg != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(out ? 'Out of stock' : 'Low stock',
                          style: TextStyle(fontSize: 11, color: badgeFg)),
                    ),
                ],
              ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? _edit(p) : _confirmDelete(p),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _limit,
      initialData: SettingsRepository.defaultLowStock,
      builder: (context, limitSnap) {
        final limit = limitSnap.data ?? SettingsRepository.defaultLowStock;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Inventory'),
            actions: [
              IconButton(
                tooltip: 'Scan bill',
                icon: const Icon(Icons.document_scanner_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ScanBillPage(db: widget.repo.database)),
                ),
              ),
              IconButton(
                tooltip: 'Low stock limit',
                icon: const Icon(Icons.notifications_active_outlined),
                onPressed: () => _editLimit(limit),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Add product'),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: StreamBuilder<List<Product>>(
                stream: _products,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snap.data!;
                  final shown = _apply(all, limit);
                  return Column(
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
                      _chips(all, limit),
                      const SizedBox(height: 8),
                      Expanded(
                        child: shown.isEmpty
                            ? Center(child: Text(_emptyText(all.isEmpty)))
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 96),
                                itemCount: shown.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) =>
                                    _tile(shown[index], limit),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
