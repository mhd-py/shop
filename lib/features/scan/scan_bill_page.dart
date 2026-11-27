import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../data/product_repository.dart';
import '../../data/stock_in_repository.dart';
import 'bill_parser.dart';
import 'row_builder.dart';
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
  String? _dump;

  static const _tips = [
    'Keep the paper flat and well lit.',
    'Hold the phone straight above the bill.',
    'Include the whole item table in the photo.',
    'Avoid shadows and glare; flatten folds with your hand.',
    'Rotate the photo so the text reads left to right.',
  ];

  Future<void> _scan() async {
    if (kIsWeb) {
      setState(() => _message = 'Bill scanning works on the phone only.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _dump = null;
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
      _dump = _makeDump(result);
      final bill = _bestParse(result);
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
              db: widget.db,
              bill: bill,
              products: products,
              readText: _dump),
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

  /// Plain-text copy of everything ML Kit read, with box positions.
  static String _makeDump(RecognizedText result) {
    final lines = <TextLine>[
      for (final b in result.blocks) ...b.lines,
    ]..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final out = StringBuffer(
        'BLOCKS ${result.blocks.length}  LINES ${lines.length}\n'
        'format: top bottom | left right | text\n');
    for (final l in lines) {
      final r = l.boundingBox;
      out.writeln('${r.top.round()} ${r.bottom.round()} | '
          '${r.left.round()} ${r.right.round()} | ${l.text}');
    }
    return out.toString();
  }

  /// Rows built from single words, so merged columns are split apart.
  /// A row's height is compared with the average of the row so far, which
  /// copes better with slightly tilted photos.
  static List<List<OcrCell>> _toRowsByWord(RecognizedText result) {
    final words = <TextElement>[
      for (final b in result.blocks)
        for (final l in b.lines) ...l.elements,
    ]..sort((a, b) =>
        a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
    final groups = <List<TextElement>>[];
    for (final w in words) {
      if (groups.isNotEmpty) {
        final last = groups.last;
        var cy = 0.0;
        var h = 0.0;
        for (final x in last) {
          cy += x.boundingBox.center.dy;
          h += x.boundingBox.height;
        }
        cy /= last.length;
        h /= last.length;
        if ((w.boundingBox.center.dy - cy).abs() < h * 0.6) {
          last.add(w);
          continue;
        }
      }
      groups.add([w]);
    }
    return [
      for (final g in groups)
        [
          for (final w in (g
            ..sort(
                (a, b) => a.boundingBox.left.compareTo(b.boundingBox.left))))
            OcrCell(w.text, w.boundingBox.left, w.boundingBox.right),
        ],
    ];
  }

  /// Tries three ways of building rows and keeps the most trustworthy result.
  static ParsedBill _bestParse(RecognizedText result) {
    final attempts = [
      _toRowsDeskewed(result),
      _toRowsByWord(result),
      _toRows(result),
    ];
    var best = BillParser().parse(attempts.first);
    var bestScore = _score(best);
    for (final rows in attempts.skip(1)) {
      final b = BillParser().parse(rows);
      final s = _score(b);
      if (s > bestScore) {
        best = b;
        bestScore = s;
      }
    }
    return best;
  }

  static int _score(ParsedBill b) {
    if (b.problem != null || b.lines.isEmpty) {
      return 0;
    }
    if (b.lines.every((l) => l.totalPaise == 0)) {
      return 1; // names only
    }
    if (!b.totalsChecked) {
      return 3;
    }
    return b.totalsMatch ? 4 : 2;
  }

  /// Rows built from words after straightening a tilted photo.
  static List<List<OcrCell>> _toRowsDeskewed(RecognizedText result) {
    final slopes = <double>[];
    final words = <RawWord>[];
    for (final b in result.blocks) {
      for (final l in b.lines) {
        final p = l.cornerPoints;
        if (p.length >= 2) {
          final dx = (p[1].x - p[0].x).toDouble();
          final dy = (p[1].y - p[0].y).toDouble();
          if (dx > 80) {
            slopes.add(dy / dx);
          }
        }
        for (final w in l.elements) {
          final r = w.boundingBox;
          words.add(RawWord(w.text, r.left, r.right, r.top, r.bottom));
        }
      }
    }
    return buildRows(words, slope: medianSlope(slopes));
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
                      if (_dump != null) ...[
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => _DumpPage(text: _dump!)),
                          ),
                          icon: const Icon(Icons.text_snippet_outlined),
                          label: const Text('Show what was read'),
                        ),
                        const SizedBox(height: 8),
                      ],
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

/// Shows the raw OCR output so it can be copied and shared.
class _DumpPage extends StatelessWidget {
  const _DumpPage({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('What was read'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')));
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ),
    );
  }
}
