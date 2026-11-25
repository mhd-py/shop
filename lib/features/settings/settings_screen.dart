import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart' show ShareResultStatus;

import 'package:file_picker/file_picker.dart';

import '../../core/upi.dart';
import '../../core/share_csv.dart';
import '../../core/share_file.dart';
import '../../data/backup_service.dart';
import '../../data/pin_repository.dart';
import '../lock/pin_dialogs.dart';
import '../../data/database.dart';
import '../../data/bill_repository.dart';
import '../history/bill_history_page.dart';
import '../../data/settings_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.bills,
    this.onDatabaseReplaced,
  });
  final SettingsRepository settings;
  final BillRepository bills;

  /// Called after a restore, with the freshly opened database.
  final void Function(AppDatabase db)? onDatabaseReplaced;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Stream<String> _shop = widget.settings.watchShopName();
  late final Stream<String> _upi = widget.settings.watchUpiId();
  late final Stream<int> _low = widget.settings.watchLowStockThreshold();
  late final Stream<DateTime?> _lastBackup = widget.settings.watchLastBackup();
  late final PinRepository _pin = PinRepository(widget.settings.database);
  late final Stream<bool> _hasPin = _pin.watchHasPin();

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

  Future<void> _pinTap(bool on) async {
    if (!on) return _setPin();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('App PIN'),
        children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'change'),
              child: const Text('Change PIN')),
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text('Remove PIN')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'change') await _changePin();
    if (choice == 'remove') await _removePin();
  }

  Future<void> _setPin() async {
    final v = await askPinFields(context,
        title: 'Set a 4-digit PIN',
        labels: const ['New PIN', 'Confirm PIN'],
        confirmNew: true);
    if (v == null || !mounted) return;
    try {
      final code = await _pin.setPin(v[0]);
      if (!mounted) return;
      await showRecoveryCode(context, code);
      _snack('PIN is on');
    } on PinException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _changePin() async {
    final v = await askPinFields(context,
        title: 'Change PIN',
        labels: const ['Current PIN', 'New PIN', 'Confirm new PIN'],
        confirmNew: true);
    if (v == null) return;
    try {
      await _pin.changePin(v[0], v[1]);
      _snack('PIN changed');
    } on PinException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _removePin() async {
    final v = await askPinFields(context,
        title: 'Remove PIN', labels: const ['Current PIN']);
    if (v == null) return;
    try {
      await _pin.removePin(v[0]);
      _snack('PIN removed');
    } on PinException catch (e) {
      _snack(e.message);
    }
  }

  String _ago(DateTime? t) {
    if (t == null) return 'Never backed up';
    final days = DateTime.now().difference(t).inDays;
    if (days == 0) return 'Last backup: today';
    if (days == 1) return 'Last backup: yesterday';
    return 'Last backup: $days days ago';
  }

  Future<void> _backup({bool confirm = true}) async {
    if (!BackupService.supported) {
      return _snack('Backup works on the phone app only');
    }
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Back up all data?'),
          content: const Text('The backup file contains all your data, '
              'including customer names and phone numbers. It is not '
              'encrypted. Save it somewhere safe and private.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continue')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final path = await BackupService(widget.settings.database).createBackup();
      final status = await shareBackupFile(path);
      if (status == ShareResultStatus.unavailable) {
        return _snack('Sharing is not available here');
      }
      if (status == ShareResultStatus.dismissed) {
        return _snack('Backup was not saved');
      }
      await widget.settings.markBackupNow();
      _snack('Backup shared');
    } catch (e) {
      _snack('Backup failed: $e');
    }
  }

  Future<void> _restore() async {
    if (!BackupService.supported) {
      return _snack('Restore works on the phone app only');
    }
    final done = widget.onDatabaseReplaced;
    if (done == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFile();
      if (picked == null) return;
      final path = picked.path;
      if (path == null) return _snack('Could not read the chosen file');
      final svc = BackupService(widget.settings.database);
      await svc.validate(path);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
          title: const Text('Restore this backup?'),
          content: Text('File: ${picked.name}\n\n'
              'All current data (bills, products, customers, Khata) will be '
              'replaced by the data in this backup. A safety copy of the '
              'current data is kept on this phone first.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      final r = await svc.restore(path);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(r.restored ? 'Backup restored' : r.error!)));
      done(r.db);
    } on BackupException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Restore failed: $e');
    }
  }

  Future<void> _clear() async {
    final count = await widget.bills.billCount();
    if (count == 0) return _snack('There are no bills to clear');
    if (!mounted) return;
    if (BackupService.supported) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Back up first?'),
          content: const Text(
              'Clearing bills cannot be undone. A backup lets you restore '
              'them later.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'skip'),
                child: const Text('Skip')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'backup'),
                child: const Text('Back up now')),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'backup') {
        await _backup();
        if (!mounted) return;
      }
    }
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
                  leading: const Icon(Icons.history),
                  title: const Text('Bill history'),
                  subtitle: const Text('Search, share, return or cancel bills'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BillHistoryPage(
                          bills: widget.bills, settings: widget.settings),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Backup',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              StreamBuilder<DateTime?>(
                stream: _lastBackup,
                builder: (context, s) => Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('Back up data'),
                    subtitle: Text(_ago(s.data)),
                    onTap: _backup,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Restore from backup'),
                  subtitle: const Text('Replace current data with a backup file'),
                  onTap: _restore,
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Security',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              StreamBuilder<bool>(
                stream: _hasPin,
                initialData: false,
                builder: (context, s) => Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('App PIN'),
                    subtitle: Text(s.data == true
                        ? 'On. Asked when the app opens'
                        : 'Off'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pinTap(s.data == true),
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
