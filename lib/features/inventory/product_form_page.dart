import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/product_repository.dart';

/// Add / edit form. Pops a [ProductInput] when saved.
class ProductFormPage extends StatefulWidget {
  const ProductFormPage({super.key, this.existing});
  final Product? existing;

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _packSize = TextEditingController(text: '10');
  final _cost = TextEditingController();
  final _sellPiece = TextEditingController();
  final _sellPack = TextEditingController();
  final _stockPieces = TextEditingController(text: '0');
  final _stockPacks = TextEditingController(text: '0');
  final _stockLoose = TextEditingController(text: '0');
  bool _sellsInPacks = false;

  String _rupees(int paise) => (paise / 100).toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p == null) return;
    _name.text = p.name;
    _sellsInPacks = p.packSize > 1;
    _packSize.text = p.packSize.toString();
    _cost.text = _rupees(p.costPaise);
    _sellPiece.text = _rupees(p.sellPiecePaise);
    _sellPack.text = p.sellPackPaise == null ? '' : _rupees(p.sellPackPaise!);
    _stockPieces.text = p.stock.toString();
    _stockPacks.text = (p.stock ~/ p.packSize).toString();
    _stockLoose.text = (p.stock % p.packSize).toString();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _packSize, _cost, _sellPiece, _sellPack,
      _stockPieces, _stockPacks, _stockLoose,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _money(TextEditingController c, String label,
      {bool allowZero = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          prefixText: '₹ ',
          border: const OutlineInputBorder(),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) {
          final p = parseRupees(v ?? '');
          if (p == null) return 'Enter a valid amount';
          if (!allowZero && p == 0) return 'Must be more than 0';
          return null;
        },
      ),
    );
  }

  Widget _whole(TextEditingController c, String label, {int min = 0}) {
    return TextFormField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      validator: (v) {
        final n = int.tryParse((v ?? '').trim());
        return (n == null || n < min) ? 'Enter $min or more' : null;
      },
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final packs = _sellsInPacks;
    final size = packs ? int.parse(_packSize.text.trim()) : 1;
    final stock = packs
        ? int.parse(_stockPacks.text.trim()) * size +
            int.parse(_stockLoose.text.trim())
        : int.parse(_stockPieces.text.trim());
    Navigator.pop(
      context,
      ProductInput(
        name: _name.text.trim(),
        packSize: size,
        costPaise: parseRupees(_cost.text)!,
        sellPiecePaise: parseRupees(_sellPiece.text)!,
        sellPackPaise: packs ? parseRupees(_sellPack.text) : null,
        stockPieces: stock,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit product' : 'Add product')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Product name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Enter a name';
                    if (t.length > 100) return 'Name is too long';
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sold in packs and pieces'),
                  subtitle: const Text('For example cigarettes'),
                  value: _sellsInPacks,
                  onChanged: (v) => setState(() => _sellsInPacks = v),
                ),
                if (_sellsInPacks) ...[
                  _whole(_packSize, 'Pieces in one pack', min: 2),
                  const SizedBox(height: 12),
                ],
                _money(
                    _cost,
                    _sellsInPacks
                        ? 'Cost price per pack'
                        : 'Cost price (what you pay)',
                    allowZero: true),
                if (_sellsInPacks) _money(_sellPack, 'Selling price per pack'),
                _money(_sellPiece,
                    _sellsInPacks ? 'Selling price per piece' : 'Selling price'),
                const SizedBox(height: 4),
                if (_sellsInPacks)
                  Row(
                    children: [
                      Expanded(child: _whole(_stockPacks, 'Stock: packs')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _whole(_stockLoose, 'Stock: loose pieces')),
                    ],
                  )
                else
                  _whole(_stockPieces, 'Stock quantity'),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _save, child: const Text('Save')),
        ),
      ),
    );
  }
}
