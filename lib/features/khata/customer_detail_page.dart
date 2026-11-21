import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/customer_repository.dart';
import '../../data/database.dart';
import '../../data/ledger_repository.dart';
import '../../data/tables/ledger_entries.dart';

class _AmountResult {
  const _AmountResult(this.paise, this.note);
  final int paise;
  final String? note;
}

String _formatDate(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '${d.day}/${d.month}/${d.year}  $h:$m $ap';
}

class CustomerDetailPage extends StatefulWidget {
  const CustomerDetailPage({
    super.key,
    required this.customerId,
    required this.ledger,
  });
  final int customerId;
  final LedgerRepository ledger;

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  late final Stream<Customer?> _customer =
      widget.ledger.watchCustomer(widget.customerId);
  late final Stream<List<LedgerEntry>> _history =
      widget.ledger.watchHistory(widget.customerId);

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) _toast(done);
    } on CustomerException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<_AmountResult?> _askAmount(String title, {int? maxPaise}) =>
      showDialog<_AmountResult>(
        context: context,
        builder: (_) => _AmountDialog(title: title, maxPaise: maxPaise),
      );

  Future<void> _addCredit() async {
    final r = await _askAmount('Add credit');
    if (r == null) return;
    await _run(
      () => widget.ledger.addCredit(widget.customerId, r.paise, note: r.note),
      'Credit added',
    );
  }

  Future<void> _receivePayment(Customer c) async {
    final r = await _askAmount('Receive payment', maxPaise: c.balancePaise);
    if (r == null) return;
    await _run(
      () => widget.ledger
          .receivePayment(widget.customerId, r.paise, note: r.note),
      'Payment recorded',
    );
  }

  Future<void> _settle(Customer c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settle in full?'),
        content: Text(
            'Mark ${formatRupees(c.balancePaise)} as received from ${c.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Settle')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
        () => widget.ledger.settleFull(widget.customerId), 'Balance settled');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Customer?>(
      stream: _customer,
      builder: (context, snap) {
        final c = snap.data;
        return Scaffold(
          appBar: AppBar(title: Text(c?.name ?? 'Customer')),
          body: c == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _Header(
                      customer: c,
                      onCredit: _addCredit,
                      onPayment: () => _receivePayment(c),
                      onSettle: () => _settle(c),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('History',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<List<LedgerEntry>>(
                        stream: _history,
                        builder: (context, h) {
                          final list = h.data ?? const <LedgerEntry>[];
                          if (list.isEmpty) {
                            return const Center(
                                child: Text('No transactions yet'));
                          }
                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: list.length,
                            itemBuilder: (_, i) => _EntryTile(entry: list[i]),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.customer,
    required this.onCredit,
    required this.onPayment,
    required this.onSettle,
  });
  final Customer customer;
  final VoidCallback onCredit;
  final VoidCallback onPayment;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final owes = customer.balancePaise > 0;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('+91 ${customer.phone}'),
            const SizedBox(height: 8),
            Text(
              formatRupees(customer.balancePaise),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: owes ? Colors.red.shade700 : Colors.green.shade700,
              ),
            ),
            Text(owes ? 'Outstanding balance' : 'Settled'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onCredit,
                  icon: const Icon(Icons.add),
                  label: const Text('Add credit'),
                ),
                if (owes)
                  FilledButton.icon(
                    onPressed: onPayment,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Receive payment'),
                  ),
                if (owes)
                  FilledButton.tonalIcon(
                    onPressed: onSettle,
                    icon: const Icon(Icons.done_all),
                    label: const Text('Settle in full'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final credit = entry.type == LedgerType.credit;
    final label = switch (entry.type) {
      LedgerType.credit => 'Credit given',
      LedgerType.partialPayment => 'Partial payment',
      LedgerType.fullPayment => 'Full payment',
    };
    final color = credit ? Colors.red.shade700 : Colors.green.shade700;
    final note = entry.note;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(credit ? Icons.arrow_upward : Icons.arrow_downward,
            color: color),
        title: Text(label),
        subtitle: Text([
          _formatDate(entry.createdAt),
          ?note,
        ].join('\n')),
        isThreeLine: note != null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${credit ? '+' : '−'}${formatRupees(entry.amountPaise)}',
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
            Text('Bal ${formatRupees(entry.balanceAfterPaise)}',
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title, this.maxPaise});
  final String title;
  final int? maxPaise;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    final p = parseRupees(v ?? '');
    if (p == null || p <= 0) return 'Enter an amount above zero';
    if (widget.maxPaise != null && p > widget.maxPaise!) {
      return 'More than the ${formatRupees(widget.maxPaise!)} owed';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
        context, _AmountResult(parseRupees(_amount.text)!, _note.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
              validator: _validate,
            ),
            TextFormField(
              controller: _note,
              decoration:
                  const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}