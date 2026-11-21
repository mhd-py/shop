import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/customer_repository.dart';
import '../../data/database.dart';
import '../../data/ledger_repository.dart';
import 'customer_detail_page.dart';

class KhataScreen extends StatefulWidget {
  const KhataScreen({super.key, required this.repo, required this.ledger});
  final CustomerRepository repo;
  final LedgerRepository ledger;

  @override
  State<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends State<KhataScreen> {
  late final Stream<List<Customer>> _customers = widget.repo.watchAll();
  final _search = TextEditingController();

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

  Future<void> _openForm({Customer? customer}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomerDialog(
        customer: customer,
        onSave: (name, phone) async {
          try {
            if (customer == null) {
              await widget.repo.add(name, phone);
            } else {
              await widget.repo.update(customer.id, name, phone);
            }
            return null;
          } on CustomerException catch (e) {
            return e.message;
          }
        },
      ),
    );
    if (saved == true && mounted) {
      _toast(customer == null ? 'Customer added' : 'Customer updated');
    }
  }

  Future<void> _delete(Customer c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete customer?'),
        content: Text('Delete ${c.name} (${c.phone})? This cannot be undone.'),
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
    try {
      await widget.repo.delete(c.id);
      if (mounted) _toast('Customer deleted');
    } on CustomerException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add customer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search name or phone',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
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
                    child: Text(snap.data!.isEmpty
                        ? 'No customers yet'
                        : 'No matching customers'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _CustomerTile(
                    customer: list[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CustomerDetailPage(
                          customerId: list[i].id,
                          ledger: widget.ledger,
                        ),
                      ),
                    ),
                    onEdit: () => _openForm(customer: list[i]),
                    onDelete: () => _delete(list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({
    required this.customer,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });
  final Customer customer;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final owes = customer.balancePaise > 0;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Text(customer.name.trim()[0].toUpperCase()),
        ),
        title: Text(customer.name),
        subtitle: Text(customer.phone),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatRupees(customer.balancePaise),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: owes ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                ),
                Text(owes ? 'Due' : 'Settled',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog({this.customer, required this.onSave});
  final Customer? customer;

  /// Returns an error message, or null when saved.
  final Future<String?> Function(String name, String phone) onSave;

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  late final _name = TextEditingController(text: widget.customer?.name);
  late final _phone = TextEditingController(text: widget.customer?.phone);
  final _formKey = GlobalKey<FormState>();
  String? _serverError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final error = await widget.onSave(_name.text, _phone.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _serverError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'Add customer' : 'Edit customer'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => CustomerRepository.validateName(v ?? ''),
            ),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (10 digits)',
                prefixText: '+91 ',
              ),
              validator: (v) => CustomerRepository.validatePhone(v ?? ''),
            ),
            if (_serverError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_serverError!,
                    style: TextStyle(color: Colors.red.shade700)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}