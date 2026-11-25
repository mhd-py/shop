import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/pin_repository.dart';

enum _Mode { enter, recover, newPin, confirmPin, showCode, erase }

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.pin, required this.onUnlocked});
  final PinRepository pin;
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  _Mode _mode = _Mode.enter;
  String? _error;
  String _firstPin = '';
  String _newCode = '';
  final _codeCtl = TextEditingController();
  final _eraseCtl = TextEditingController();

  @override
  void dispose() {
    _codeCtl.dispose();
    _eraseCtl.dispose();
    super.dispose();
  }

  void _go(_Mode m, [String? error]) => setState(() {
        _mode = m;
        _error = error;
      });

  Future<void> _onPin(String p) async {
    try {
      if (_mode == _Mode.enter) {
        await widget.pin.verifyPin(p);
        widget.onUnlocked();
      } else if (_mode == _Mode.newPin) {
        _firstPin = p;
        _go(_Mode.confirmPin);
      } else if (_mode == _Mode.confirmPin) {
        if (p != _firstPin) {
          return _go(_Mode.newPin, 'PINs did not match. Try again');
        }
        final code = await widget.pin.resetWithRecovery(_codeCtl.text, p);
        if (!mounted) return;
        _newCode = code;
        _go(_Mode.showCode);
      }
    } on PinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _checkCode() async {
    try {
      await widget.pin.checkRecovery(_codeCtl.text);
      if (mounted) _go(_Mode.newPin);
    } on PinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _erase() async {
    await widget.pin.eraseAllData();
    widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: _body(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorText() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_error ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red)),
      );

  Widget _body(BuildContext context) {
    switch (_mode) {
      case _Mode.enter:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _PinPad(
              key: ValueKey(_mode),
              title: 'Enter PIN',
              error: _error,
              onComplete: _onPin),
          TextButton(
            onPressed: () {
              _codeCtl.clear();
              _go(_Mode.recover);
            },
            child: const Text('Forgot PIN?'),
          ),
        ]);
      case _Mode.newPin:
        return _PinPad(
            key: ValueKey(_mode),
            title: 'Choose a new PIN',
            error: _error,
            onComplete: _onPin);
      case _Mode.confirmPin:
        return _PinPad(
            key: ValueKey(_mode),
            title: 'Confirm new PIN',
            error: _error,
            onComplete: _onPin);
      case _Mode.recover:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.vpn_key_outlined, size: 40),
          const SizedBox(height: 12),
          Text('Enter your recovery code',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _codeCtl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                hintText: 'XXXXX-XXXXX', border: OutlineInputBorder()),
          ),
          _errorText(),
          FilledButton(onPressed: _checkCode, child: const Text('Continue')),
          TextButton(
            onPressed: () => _go(_Mode.erase),
            child: const Text('Lost the code?'),
          ),
          TextButton(
              onPressed: () => _go(_Mode.enter),
              child: const Text('Back')),
        ]);
      case _Mode.erase:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.red),
          const SizedBox(height: 12),
          const Text(
              'This erases ALL data on this phone: bills, products, '
              'customers and Khata, and turns the PIN off. You can then '
              'restore from a backup file in Settings.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(
            controller: _eraseCtl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Type ERASE to confirm',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: _eraseCtl.text.trim() == 'ERASE' ? _erase : null,
            child: const Text('Erase everything'),
          ),
          TextButton(
              onPressed: () => _go(_Mode.recover),
              child: const Text('Back')),
        ]);
      case _Mode.showCode:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline, size: 40),
          const SizedBox(height: 12),
          Text('PIN changed',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text(
              'Your new recovery code. Write it down. It will not be '
              'shown again.',
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          SelectableText(_newCode,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2)),
          TextButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _newCode)),
            child: const Text('Copy'),
          ),
          FilledButton(
              onPressed: widget.onUnlocked,
              child: const Text('I wrote it down')),
        ]);
    }
  }
}

class _PinPad extends StatefulWidget {
  const _PinPad(
      {super.key, required this.title, required this.onComplete, this.error});
  final String title;
  final String? error;
  final Future<void> Function(String pin) onComplete;

  @override
  State<_PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<_PinPad> {
  String _digits = '';
  bool _busy = false;

  Future<void> _tap(String d) async {
    if (_busy || _digits.length >= 4) return;
    setState(() => _digits += d);
    if (_digits.length == 4) {
      _busy = true;
      await widget.onComplete(_digits);
      if (!mounted) return;
      setState(() {
        _digits = '';
        _busy = false;
      });
    }
  }

  void _back() {
    if (_busy || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Widget _key(Widget child, VoidCallback onTap) => SizedBox(
        width: 80,
        height: 64,
        child: TextButton(onPressed: onTap, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    const big = TextStyle(fontSize: 26);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.lock_outline, size: 40),
      const SizedBox(height: 12),
      Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < 4; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _digits.length ? color : null,
              border: Border.all(color: color, width: 2),
            ),
          ),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(widget.error ?? ' ',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red)),
      ),
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final d in row) _key(Text(d, style: big), () => _tap(d)),
        ]),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(width: 80, height: 64),
        _key(const Text('0', style: big), () => _tap('0')),
        _key(const Icon(Icons.backspace_outlined), _back),
      ]),
    ]);
  }
}
