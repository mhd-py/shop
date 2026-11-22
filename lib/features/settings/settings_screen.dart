import 'package:material_ui/material_ui.dart';

import '../../core/upi.dart';
import '../../data/settings_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});
  final SettingsRepository settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Stream<String> _shop = widget.settings.watchShopName();
  late final Stream<String> _upi = widget.settings.watchUpiId();

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
            ],
          ),
        ),
      ),
    );
  }
}
