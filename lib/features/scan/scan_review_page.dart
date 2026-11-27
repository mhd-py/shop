import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/stock_in_repository.dart';
import 'bill_parser.dart';
import 'product_matcher.dart';

String _rupees(int? paise) =>
    paise == null ? '' : (paise / 100).toStringAsFixed(2);

int? _paise(String s) {
  final v = double.tryParse(s.trim());
  return v == null ? null : (v * 100).round();
}

class _Item {
  _Item(this.line)
      : name = TextEditingController(text: line.name),
        qty = TextEditingController(text: line.qty > 0 ? '${line.qty}' : ''),
        cost = TextEditingController(
            text: line.totalPaise > 0 ? _rupees(line.unitCostPaise) : ''),
        sell = TextEditingController(
            text: _rupees((line.mrpPaise ?? 0) > 0
                ? line.mrpPaise
                : (line.totalPaise > 0 ? line.unitCostPaise : null)));
  final BillLine line;
  final TextEditingController name, qty, cost, sell;
  bool include = true;
  bool asNew = false; // for "similar" matches: owner says it is a new product
  bool updateCost = true;
  Product? picked; // chosen by the owner with "Find in my products\"

  void dispose() {
    name.dispose();
    qty.dispose();
    cost.dispose();
    sell.dispose();
  }
}

class ScanReviewPage extends StatefulWidget {
  const ScanReviewPage({
    super.key,
    required this.db,
    required this.bill,
    required this.products,
    this.readText,
  });
  final AppDatabase db;
  final ParsedBill bill;
  final List<Product> products;

  /// Raw OCR text, for checking a wrong result.
  final String? readText;

  @override
  State<ScanReviewPage> createState() => _ScanReviewPageState();
}

class _ScanReviewPageState extends State<ScanReviewPage> {
  late final ProductMatcher _matcher = ProductMatcher(widget.products);
  late final List<_Item> _items = [for (final l in widget.bill.lines) _Item(l)];
  bool _saving = false;
  final List<_Item> _trash = [];

  @override
  void dispose() {
    for (final i in [..._items, ..._trash]) {
      i.dispose();
    }
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  MatchResult _match(_Item it) => _matcher.match(it.name.text);

  /// The existing product this line will be added to, or null for a new one.
  Product? _target(_Item it) {
    if (it.picked != null) {
      return it.picked;
    }
    final m = _match(it);
    if (m.kind == MatchKind.exact) return m.product;
    if (m.kind == MatchKind.similar && !it.asNew) return m.product;
    return null;
  }

  Future<void> _save() async {
    final lines = <StockInLine>[];
    for (final it in _items) {
      if (!it.include) continue;
      final name = it.name.text.trim();
      final label = name.isEmpty ? 'a line' : '"$name"';
      final qty = int.tryParse(it.qty.text.trim());
      final cost = _paise(it.cost.text);
      if (name.isEmpty || qty == null || qty <= 0 || cost == null || cost < 0) {
        _toast('Please check the name, quantity and cost of $label');
        return;
      }
      final t = _target(it);
      if (t != null) {
        lines.add(StockInLine(
          productId: t.id,
          name: t.name,
          pieces: qty * (t.packSize > 1 ? t.packSize : 1),
          costPaise: cost,
          updateCost: it.updateCost,
        ));
      } else {
        final sell = _paise(it.sell.text);
        if (sell == null || sell <= 0) {
          _toast('Please enter a selling price for $label');
          return;
        }
        lines.add(StockInLine(
            name: name, pieces: qty, costPaise: cost, sellPiecePaise: sell));
      }
    }
    if (lines.isEmpty) {
      _toast('Nothing selected to save');
      return;
    }
    setState(() => _saving = true);
    try {
      final r = await StockInRepository(widget.db).apply(lines);
      if (mounted) Navigator.pop(context, r);
    } on StockInException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast(e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('Could not save. Nothing was changed. Please try again.');
      }
    }
  }

  void _addLine() {
    final it = _Item(BillLine(name: '', qty: 1, totalPaise: 0));
    it.cost.text = '';
    it.sell.text = '';
    setState(() => _items.add(it));
  }

  void _remove(_Item it) {
    final index = _items.indexOf(it);
    if (index < 0) return;
    setState(() {
      _items.removeAt(index);
      _trash.add(it);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Line removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => setState(() {
            _trash.remove(it);
            _items.insert(index.clamp(0, _items.length).toInt(), it);
          }),
        ),
      ));
  }

  Future<void> _pick(_Item it) async {
    final words = it.name.text.trim().split(RegExp(r'\s+'));
    final chosen = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPicker(
        products: widget.products,
        start: words.take(2).join(' '),
        canClear: it.picked != null,
      ),
    );
    if (!mounted) {
      return;
    }
    if (chosen is Product) {
      setState(() => it.picked = chosen);
    } else if (chosen == false) {
      setState(() => it.picked = null);
    }
  }

  Widget _banner() {
    final scheme = Theme.of(context).colorScheme;
    final b = widget.bill;
    final String text;
    final Color bg;
    final Color fg;
    if (b.totalsChecked && b.totalsMatch) {
      text = 'Line totals match the bill total.';
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else if (b.totalsChecked) {
      text = 'Line totals do not match the bill total. Check every line.';
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    } else {
      text = 'Bill total not found. Check every line carefully.';
      bg = scheme.tertiaryContainer;
      fg = scheme.onTertiaryContainer;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: fg)),
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool number = false, double? width}) {
    final f = TextField(
      controller: c,
      onChanged: (_) => setState(() {}),
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
    return width == null ? f : SizedBox(width: width, child: f);
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 12, color: fg)),
      );

  Widget _card(_Item it) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = _match(it);
    final t = _target(it);
    final qty = int.tryParse(it.qty.text.trim()) ?? 0;
    final cost = _paise(it.cost.text);
    final isPack = t != null && t.packSize > 1;
    final pieces = t == null ? qty : qty * (isPack ? t.packSize : 1);

    final tag = t == null
        ? _tag('New product', scheme.secondaryContainer,
            scheme.onSecondaryContainer)
        : it.picked != null
            ? _tag('Chosen by you', scheme.primaryContainer,
                scheme.onPrimaryContainer)
        : m.kind == MatchKind.exact
            ? _tag('Matched', scheme.primaryContainer,
                scheme.onPrimaryContainer)
            : _tag('Similar', scheme.tertiaryContainer,
                scheme.onTertiaryContainer);

    return Opacity(
      opacity: it.include ? 1 : 0.5,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  tag,
                  const Spacer(),
                  const Text('Include'),
                  Switch(
                    value: it.include,
                    onChanged: (v) => setState(() => it.include = v),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove line',
                    onPressed: () => _remove(it),
                  ),
                ],
              ),
              _field(it.name, 'Product name'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _pick(it),
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(it.picked == null
                      ? 'Find in my products'
                      : 'Linked to ${it.picked!.name} (change)'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _field(it.qty, isPack ? 'Packs' : 'Qty',
                      number: true, width: 90),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _field(
                          it.cost, isPack ? 'Cost per pack (₹)' : 'Cost each (₹)',
                          number: true)),
                  if (t == null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                        child:
                            _field(it.sell, 'Selling price (₹)', number: true)),
                  ],
                ],
              ),
              if (m.kind == MatchKind.similar && it.picked == null) ...[
                const SizedBox(height: 8),
                Text('Is this "${m.product!.name}"?',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text('Yes, add to ${m.product!.name}'),
                      selected: !it.asNew,
                      onSelected: (_) => setState(() => it.asNew = false),
                    ),
                    ChoiceChip(
                      label: const Text('No, new product'),
                      selected: it.asNew,
                      onSelected: (_) => setState(() => it.asNew = true),
                    ),
                  ],
                ),
              ],
              if (t != null) ...[
                const SizedBox(height: 8),
                Text(
                  'In stock ${t.stock} + $pieces = ${t.stock + pieces} pcs',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (cost != null && cost != t.costPaise)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: it.updateCost,
                    onChanged: (v) => setState(() => it.updateCost = v),
                    title: Text(
                        'Use new cost ${formatRupees(cost)} '
                        '(was ${formatRupees(t.costPaise)})'),
                  ),
              ],
              for (final w in it.line.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 18, color: scheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(w,
                              style: TextStyle(color: scheme.error))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _items.where((i) => i.include).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check bill items'),
        actions: [
          if (widget.readText != null)
            IconButton(
              icon: const Icon(Icons.text_snippet_outlined),
              tooltip: 'What was read',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('What was read'),
                  content: SingleChildScrollView(
                    child: SelectableText(widget.readText!,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11)),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: widget.readText!));
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Copy'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _saving || count == 0 ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Save stock ($count items)'),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _items.length + 2,
            separatorBuilder: (context, i) => const SizedBox(height: 8),
            itemBuilder: (context, i) => i == 0
                ? _banner()
                : i == _items.length + 1
                    ? OutlinedButton.icon(
                        onPressed: _addLine,
                        icon: const Icon(Icons.add),
                        label: const Text('Add item'),
                      )
                    : _card(_items[i - 1]),
          ),
        ),
      ),
    );
  }
}

/// Search box over the shop's own products.
class _ProductPicker extends StatefulWidget {
  const _ProductPicker({
    required this.products,
    required this.start,
    required this.canClear,
  });
  final List<Product> products;
  final String start;
  final bool canClear;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  late final TextEditingController _q =
      TextEditingController(text: widget.start);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = _q.text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final shown = widget.products.where((p) {
      final n = p.name.toLowerCase();
      return words.every((w) => n.contains(w));
    }).take(50).toList();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search your products',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.canClear)
                    ListTile(
                      leading: const Icon(Icons.link_off),
                      title: const Text('Remove link (automatic match)'),
                      onTap: () => Navigator.pop(context, false),
                    ),
                  for (final p in shown)
                    ListTile(
                      title: Text(p.name),
                      subtitle: Text('In stock ${p.stock}'),
                      onTap: () => Navigator.pop(context, p),
                    ),
                  if (shown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No product found. Try fewer letters.'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
