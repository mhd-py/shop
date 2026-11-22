import 'package:material_ui/material_ui.dart';

import '../../core/upi.dart';
import '../../core/share_csv.dart';
import '../../data/bill_repository.dart';
import '../../data/settings_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(
      {super.key, required this.settings, required this.bills});
  final SettingsRepository settings;
  final BillRepository bills;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Stream<String> _shop = widget.settings.watchShopName();
  late final Stream<String> _upi = widget.settings.watchUpiId();
  late final Stream<int> _low = widget.settings.watchLowStockThreshold();

  Future<void> _edit({
    required String title,
    required String current,
    required String hint,
    required String? Function(String) validate,
    required Future<void> Function(String) save,
  }) async {
    final c = TextEditingController(text: current);
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(
              hintText: hint,
              errorText: error,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final e = validate(c.text);
                if (e != null) {
                  setLocal(() => error = e);
                } else {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await save(c.text);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Saved')));
      }
    }
    c.dispose();
  }

  Widget _tile(IconData icon, String label, String value, String empty,
      VoidCallback onTap) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value.isEmpty ? empty : value),
        trailing: const Icon(Icons.edit_outlined),
        onTap: onTap,
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _export() async {
    try {
      final csv = await widget.bills.buildCsv();
      if (csv == null) return _snack('There are no bills to export');
      final d = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final name = 'bills_${d.year}${two(d.month)}${two(d.day)}.csv';
      final ok = await shareCsv(name, csv);
      if (!ok) _snack('Sharing is not available here. Try on the phone.');
    } catch (e) {
      _snack('Export failed: $e');
    }
  }

  Future<void> _clear() async {
    final count = await widget.bills.billCount();
    if (count == 0) return _snack('There are no bills to clear');
    if (!mounted) return;
    final c = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
          title: Text('Clear $count bills?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This permanently deletes all bills and cannot be '
                  'undone. Export the CSV first if you need a record.\n\n'
                  'Products, customers and Khata balances and history are '
                  'kept.'),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                autofocus: true,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: c.text.trim() == 'DELETE'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Clear bills'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    if (go != true) return;
    try {
      final n = await widget.bills.clearAll();
      _snack('$n bills cleared');
    } catch (e) {
      _snack('Could not clear bills: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StreamBuilder<String>(
                stream: _shop,
                initialData: '',
                builder: (context, s) => _tile(
                  Icons.storefront_outlined,
                  'Shop name',
                  s.data ?? '',
                  'Not set',
                  () => _edit(
                    title: 'Shop name',
                    current: s.data ?? '',
                    hint: 'e.g. Sree Stores',
                    validate: (v) => v.trim().length > 60
                        ? 'Use 60 characters or fewer'
                        : null,
                    save: widget.settings.setShopName,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<String>(
                stream: _upi,
                initialData: '',
                builder: (context, s) => _tile(
                  Icons.qr_code_2,
                  'UPI ID',
                  s.data ?? '',
                  'Not set. Needed for the UPI QR code',
                  () => _edit(
                    title: 'UPI ID',
                    current: s.data ?? '',
                    hint: 'e.g. shop@upi',
                    validate: validateUpiId,
                    save: widget.settings.setUpiId,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<int>(
                stream: _low,
                initialData: SettingsRepository.defaultLowStock,
                builder: (context, s) => _tile(
                  Icons.notifications_active_outlined,
                  'Low-stock limit',
                  '${s.data ?? SettingsRepository.defaultLowStock}',
                  'Not set',
                  () => _edit(
                    title: 'Low-stock limit',
                    current: '${s.data ?? SettingsRepository.defaultLowStock}',
                    hint: 'e.g. 5',
                    validate: (v) {
                      final n = int.tryParse(v.trim());
                      if (n == null || n < 1 || n > 9999) {
                        return 'Enter a number from 1 to 9999';
                      }
                      return null;
                    },
                    save: (v) =>
                        widget.settings.setLowStockThreshold(int.parse(v.trim())),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Billing data',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Export bills (CSV)'),
                  subtitle: const Text('Share or save all bills as a file'),
                  onTap: _export,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Clear bills'),
                  subtitle: const Text(
                      'Frees storage. Customers, products and Khata are kept'),
                  onTap: _clear,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
