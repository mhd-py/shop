import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/bill_repository.dart';
import '../../data/database.dart';
import '../../data/settings_repository.dart';
import 'bill_detail_page.dart';
import 'bill_text.dart';

class BillHistoryPage extends StatefulWidget {
  const BillHistoryPage(
      {super.key, required this.bills, required this.settings});
  final BillRepository bills;
  final SettingsRepository settings;

  @override
  State<BillHistoryPage> createState() => _BillHistoryPageState();
}

class _BillHistoryPageState extends State<BillHistoryPage> {
  late final Stream<List<Bill>> _stream = widget.bills.watchBills();
  final _search = TextEditingController();
  DateTime? _day;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (d != null) setState(() => _day = d);
  }

  bool _match(Bill b) {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty &&
        !b.billNumber.toLowerCase().contains(q) &&
        !(b.customerName ?? '').toLowerCase().contains(q)) {
      return false;
    }
    final d = _day;
    if (d != null &&
        (b.createdAt.year != d.year ||
            b.createdAt.month != d.month ||
            b.createdAt.day != d.day)) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bill history')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search bill number or customer',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _day == null
                      ? ActionChip(
                          avatar: const Icon(Icons.calendar_today, size: 16),
                          label: const Text('Pick a date'),
                          onPressed: _pickDay,
                        )
                      : InputChip(
                          avatar: const Icon(Icons.calendar_today, size: 16),
                          label: Text('${_day!.day}/${_day!.month}/${_day!.year}'),
                          onPressed: _pickDay,
                          onDeleted: () => setState(() => _day = null),
                        ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Bill>>(
                  stream: _stream,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final all = snap.data!;
                    final list = all.where(_match).toList();
                    if (list.isEmpty) {
                      return Center(
                          child: Text(all.isEmpty
                              ? 'No bills yet'
                              : 'No matching bills'));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final b = list[i];
                        final cancelled = b.cancelledAt != null;
                        final status = cancelled
                            ? 'Cancelled'
                            : b.returnedPaise > 0
                                ? 'Part returned'
                                : null;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(b.billNumber),
                            subtitle: Text([
                              formatDateTime(b.createdAt),
                              '${paymentLabel(b.paymentMethod)}'
                                  '${b.customerName != null ? ' · ${b.customerName}' : ''}',
                            ].join('\n')),
                            isThreeLine: true,
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatRupees(b.totalPaise),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    decoration: cancelled
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                if (status != null)
                                  Text(status,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: cancelled
                                              ? theme.colorScheme.error
                                              : Colors.orange.shade800)),
                              ],
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BillDetailPage(
                                  billId: b.id,
                                  bills: widget.bills,
                                  settings: widget.settings,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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
