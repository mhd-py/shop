import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../data/product_repository.dart';
import '../../data/stock_in_repository.dart';
import 'bill_parser.dart';
import 'scan_review_page.dart';

/// Pick a bill photo, read it, then hand over to the review screen.
class ScanBillPage extends StatefulWidget {
  const ScanBillPage({super.key, required this.db});
  final AppDatabase db;

  @override
  State<ScanBillPage> createState() => _ScanBillPageState();
}

class _ScanBillPageState extends State<ScanBillPage> {
  bool _busy = false;
  String? _message;

  static const _tips = [
    'Keep the paper flat and well lit.',
    'Hold the phone straight above the bill.',
    'Include the whole item table in the photo.',
  ];

  Future<void> _scan() async {
    if (kIsWeb) {
      setState(() => _message = 'Bill scanning works on the phone only.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final dynamic picked = await FilePicker.pickFile();
      final String? path = picked == null
          ? null
          : (picked.path ?? picked.files.first.path) as String?;
      if (path == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final result =
          await recognizer.processImage(InputImage.fromFilePath(path));
      final bill = BillParser().parse(_toRows(result));
      final products = await ProductRepository(widget.db).watchAll().first;
      if (!mounted) return;
      setState(() => _busy = false);
      if (bill.problem != null) {
        setState(() => _message = bill.problem);
        return;
      }
      final saved = await Navigator.push<StockInResult>(
        context,
        MaterialPageRoute(
          builder: (_) => ScanReviewPage(
              db: widget.db, bill: bill, products: products),
        ),
      );
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Stock updated: ${saved.updated} existing, ${saved.added} new')));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Could not read this photo. Try again with a clearer '
              'photo, or use Add product.';
        });
      }
    } finally {
      await recognizer.close();
    }
  }

  /// Groups recognised lines into table rows, top to bottom.
  static List<List<OcrCell>> _toRows(RecognizedText result) {
    final lines = <TextLine>[
      for (final b in result.blocks) ...b.lines,
    ]..sort((a, b) =>
        a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
    final groups = <List<TextLine>>[];
    for (final l in lines) {
      if (groups.isNotEmpty) {
        final first = groups.last.first;
        final dy = (l.boundingBox.center.dy - first.boundingBox.center.dy).abs();
        if (dy < first.boundingBox.height * 0.6) {
          groups.last.add(l);
          continue;
        }
      }
      groups.add([l]);
    }
    return [
      for (final g in groups)
        [
          for (final l in (g
            ..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left))))
            OcrCell(l.text, l.boundingBox.left, l.boundingBox.right),
        ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan bill')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _busy
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Reading the bill...'),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.document_scanner_outlined,
                          size: 64, color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      Text('Add stock from a supplier bill',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 12),
                      for (final t in _tips)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('•  $t',
                              style: theme.textTheme.bodyMedium),
                        ),
                      const SizedBox(height: 16),
                      if (_message != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(_message!,
                              style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer)),
                        ),
                      FilledButton.icon(
                        onPressed: _scan,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Choose bill photo'),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'You can check and change every line before anything is saved.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
