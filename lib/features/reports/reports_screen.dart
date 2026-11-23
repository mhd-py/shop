import 'package:material_ui/material_ui.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/product_extensions.dart';
import '../../data/report_repository.dart';
import '../../data/settings_repository.dart';

enum _Period { today, yesterday, week, month, custom }

class _Data {
  _Data(this.summary, this.khata, this.byQty, this.byProfit, this.low,
      this.threshold, this.stockValue, this.daily);
  final SalesSummary summary;
  final KhataSummary khata;
  final List<TopItem> byQty;
  final List<TopItem> byProfit;
  final List<Product> low;
  final int threshold;
  final int stockValue;
  final List<DailySales> daily;
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.reports,
    required this.settings,
    this.refresh,
  });
  final ReportRepository reports;
  final SettingsRepository settings;

  /// Reload whenever this changes (the tab was opened).
  final Listenable? refresh;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Period _period = _Period.today;
  DateRange? _custom;
  late Future<_Data> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    widget.refresh?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  DateRange _range() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.today:
        return DateRange.today(now);
      case _Period.yesterday:
        return DateRange.yesterday(now);
      case _Period.week:
        return DateRange.last7Days(now);
      case _Period.month:
        return DateRange.thisMonth(now);
      case _Period.custom:
        return _custom ?? DateRange.today(now);
    }
  }

  Future<_Data> _load() async {
    final r = _range();
    final rep = widget.reports;
    final threshold = await widget.settings.watchLowStockThreshold().first;
    return _Data(
      await rep.summary(r),
      await rep.khata(r),
      await rep.topByQuantity(r),
      await rep.topByProfit(r),
      await rep.lowStock(threshold),
      threshold,
      await rep.stockValueAtCost(),
      await rep.dailySales(r),
    );
  }

  Future<void> _pick(_Period p) async {
    if (p == _Period.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: now,
        initialDateRange: _custom == null
            ? null
            : DateTimeRange(
                start: _custom!.start,
                end: _custom!.end.subtract(const Duration(days: 1))),
      );
      if (picked == null) return;
      _custom = DateRange.days(picked.start, picked.end);
    }
    setState(() {
      _period = p;
      _future = _load();
    });
  }

  static const _labels = {
    _Period.today: 'Today',
    _Period.yesterday: 'Yesterday',
    _Period.week: '7 days',
    _Period.month: 'This month',
    _Period.custom: 'Custom',
  };

  String _d(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _rangeText() {
    final r = _range();
    final last = r.end.subtract(const Duration(days: 1));
    final a = _d(r.start);
    final b = _d(last);
    return a == b ? a : '$a  to  $b';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text('Reports',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              Text(_rangeText(),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final p in _Period.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(_labels[p]!),
                    selected: _period == p,
                    onSelected: (_) => _pick(p),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<_Data>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(child: Text('Could not load reports'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return RefreshIndicator(
                onRefresh: () async {
                  _reload();
                  await _future;
                },
                child: _body(context, snap.data!),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, _Data d) {
    final s = d.summary;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          children: [
            Expanded(child: _stat(context, 'Total sales', formatRupees(s.totalPaise))),
            const SizedBox(width: 8),
            Expanded(child: _stat(context, 'Bills', '${s.billCount}')),
            const SizedBox(width: 8),
            Expanded(child: _stat(context, 'Average', formatRupees(s.averagePaise))),
          ],
        ),
        _section(context, 'Payment split', [
          _row('Cash', formatRupees(s.cashPaise)),
          _row('UPI', formatRupees(s.upiPaise)),
          _row('Khata (credit given)', formatRupees(s.khataPaise)),
        ]),
        _section(context, 'Profit', [
          _row('Profit',
              s.profitPaise == null ? 'Not available' : formatRupees(s.profitPaise!),
              bold: true),
          if (s.billsWithoutCost > 0)
            _note(context,
                'Profit not available for ${s.billsWithoutCost} older bill${s.billsWithoutCost == 1 ? '' : 's'}.'),
        ]),
        _section(context, 'Khata', [
          _row('Total outstanding', formatRupees(d.khata.outstandingPaise), bold: true),
          _row('Collected in period', formatRupees(d.khata.collectedPaise)),
          if (d.khata.topDebtors.isNotEmpty) ...[
            const Divider(height: 20),
            for (final c in d.khata.topDebtors)
              _row(c.name, formatRupees(c.balancePaise)),
          ],
        ]),
        _section(context, 'Daily sales', [_chart(context, d.daily)]),
        _section(context, 'Top items by quantity', [
          if (d.byQty.isEmpty) _note(context, 'No sales in this period.'),
          for (final i in d.byQty) _row(i.name, _qty(i)),
        ]),
        _section(context, 'Top items by profit', [
          if (d.byProfit.isEmpty) _note(context, 'No profit data in this period.'),
          for (final i in d.byProfit) _row(i.name, formatRupees(i.profitPaise!)),
        ]),
        _section(context, 'Low stock (${d.threshold} or fewer)', [
          if (d.low.isEmpty) _note(context, 'All items are well stocked.'),
          for (final p in d.low) _row(p.name, p.stockText),
        ]),
        _section(context, 'Stock', [
          _row('Stock value at cost', formatRupees(d.stockValue), bold: true),
        ]),
      ],
    );
  }

  String _qty(TopItem i) {
    final parts = <String>[];
    if (i.pieces > 0) parts.add('${i.pieces} pcs');
    if (i.packs > 0) parts.add('${i.packs} pack${i.packs == 1 ? '' : 's'}');
    return parts.join(' + ');
  }

  Widget _stat(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            FittedBox(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _chart(BuildContext context, List<DailySales> days) {
    if (days.length > 31) {
      return _note(context, 'Chart shows up to 31 days. Pick a shorter period.');
    }
    final cs = Theme.of(context).colorScheme;
    final max = days.fold<int>(0, (m, e) => e.totalPaise > m ? e.totalPaise : m);
    if (max == 0) return _note(context, 'No sales in this period.');
    const barArea = 110.0;
    final step = days.length > 10 ? 5 : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Highest day: ${formatRupees(max)}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        SizedBox(
          height: barArea + 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: days[i].totalPaise == 0
                            ? 2
                            : barArea * days[i].totalPaise / max,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: days[i].totalPaise == 0
                              ? cs.outlineVariant
                              : cs.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 16,
                        child: Text(i % step == 0 ? '${days[i].day.day}' : '',
                            style: const TextStyle(fontSize: 10)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
