import 'package:material_ui/material_ui.dart';

import '../../data/pin_repository.dart';
import 'lock_screen.dart';

/// Covers the whole app with the lock screen when a PIN is set.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.pin, required this.child});
  final PinRepository pin;
  final Widget child;

  static const grace = Duration(minutes: 1);

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _locked = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockIfPin();
  }

  @override
  void didUpdateWidget(LockGate old) {
    super.didUpdateWidget(old);
    if (old.pin != widget.pin) _lockIfPin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _lockIfPin() async {
    try {
      final has = await widget.pin.hasPin();
      if (!mounted || !has) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _locked = true);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null && DateTime.now().difference(left) >= LockGate.grace) {
        _lockIfPin();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) => LockScreen(
                    pin: widget.pin,
                    onUnlocked: () {
                      if (mounted) setState(() => _locked = false);
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
