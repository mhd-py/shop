import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:material_ui/material_ui.dart';

/// Temporary page: proves how well OCR reads real bills.
class OcrTestPage extends StatefulWidget {
  const OcrTestPage({super.key});

  @override
  State<OcrTestPage> createState() => _OcrTestPageState();
}

class _OcrTestPageState extends State<OcrTestPage> {
  bool _busy = false;
  String? _error;
  List<String> _rows = [];
  List<String> _raw = [];

  Future<void> _pick() async {
    if (kIsWeb) {
      setState(() => _error = 'OCR works on the phone only.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final dynamic picked = await FilePicker.pickFile();
      final String? path = picked == null
          ? null
          : (picked.path ?? picked.files.first.path) as String?;
      if (path == null) {
        setState(() => _busy = false);
        return;
      }
      final result =
          await recognizer.processImage(InputImage.fromFilePath(path));
      final lines = <TextLine>[
        for (final b in result.blocks) ...b.lines,
      ]..sort((a, b) =>
          a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));

      // Group lines that sit on the same visual row.
      final groups = <List<TextLine>>[];
      for (final l in lines) {
        if (groups.isNotEmpty) {
          final last = groups.last.first;
          final dy =
              (l.boundingBox.center.dy - last.boundingBox.center.dy).abs();
          if (dy < last.boundingBox.height * 0.6) {
            groups.last.add(l);
            continue;
          }
        }
        groups.add([l]);
      }
      final rows = [
        for (final g in groups)
          (g..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left)))
              .map((l) => l.text)
              .join('  |  '),
      ];
      setState(() {
        _rows = rows;
        _raw = [for (final l in lines) l.text];
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _busy = false;
      });
    } finally {
      await recognizer.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bill reading test'),
          bottom: const TabBar(
              tabs: [Tab(text: 'Rows'), Tab(text: 'Raw lines')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.image_outlined),
          label: const Text('Pick bill photo'),
        ),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [_list(_rows), _list(_raw)]),
      ),
    );
  }

  Widget _list(List<String> items) {
    if (items.isEmpty) {
      return const Center(child: Text('Pick a bill photo to begin.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: items.length,
      separatorBuilder: (context, i) => const Divider(height: 12),
      itemBuilder: (context, i) => SelectableText(items[i]),
    );
  }
}
