import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/branding.dart';

/// Held by any screen that's actually playing video. While at least one hold
/// is active, two things are true:
///   * the in-app idle screensaver below never fades in, and
///   * the device is asked to keep the screen on, so Fire TV / Android TV's
///     own ambient mode and display sleep stay out of the way too.
///
/// Both are released as soon as the last player screen closes, so the normal
/// idle behaviour (and burn-in protection) comes back when you stop watching.
/// Call [acquire] in a player's initState and [release] in its dispose.
class KeepAwake {
  static final ValueNotifier<int> holds = ValueNotifier<int>(0);

  static void acquire() {
    holds.value++;
    if (holds.value == 1) _setWakelock(true);
  }

  static void release() {
    if (holds.value == 0) return;
    holds.value--;
    if (holds.value == 0) _setWakelock(false);
  }

  // Best-effort: a device or plugin version that can't do this shouldn't take
  // playback down with it.
  static Future<void> _setWakelock(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {/* ignore */}
  }
}

/// Wraps the whole app (see `builder:` in main.dart). After [idleAfter] with
/// no remote-control input at all, fades in a low-brightness screensaver
/// (logo + clock) instead of leaving a static frame on screen — useful for
/// whenever HyDr02 itself is left open and idle (paused on browse/guide),
/// since an app can't opt into or drive Android TV's own system-level
/// ambient mode. Any D-pad press, touch, or click dismisses it immediately.
///
/// v1 shows the app logo + a clock. A real photo slideshow (like Fire TV's
/// built-in ambient mode) is a natural next step once there's a photo
/// source to point it at (a folder on the device, Google Photos, etc.) —
/// swap `_Screensaver`'s body for a `PageView`/`AnimatedSwitcher` over that
/// source's image list when that's ready.
class IdleWatcher extends StatefulWidget {
  final Widget child;
  final Duration idleAfter;
  const IdleWatcher({
    super.key,
    required this.child,
    this.idleAfter = const Duration(minutes: 5),
  });

  @override
  State<IdleWatcher> createState() => _IdleWatcherState();
}

class _IdleWatcherState extends State<IdleWatcher> {
  Timer? _timer;
  bool _idle = false;
  final _focusNode = FocusNode(debugLabel: 'IdleWatcher');

  @override
  void initState() {
    super.initState();
    KeepAwake.holds.addListener(_onHoldsChanged);
    _resetTimer();
  }

  @override
  void dispose() {
    KeepAwake.holds.removeListener(_onHoldsChanged);
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  /// Playback started or stopped: drop the screensaver and stop counting
  /// while something is playing, resume counting once it ends.
  void _onHoldsChanged() => _resetTimer();

  void _resetTimer([dynamic _]) {
    _timer?.cancel();
    if (_idle) setState(() => _idle = false);
    // Don't count down at all while video is playing — sitting still through
    // a two-hour movie is not "idle".
    if (KeepAwake.holds.value > 0) return;
    _timer = Timer(widget.idleAfter, () {
      if (mounted) setState(() => _idle = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _resetTimer,
      onPointerMove: _resetTimer,
      behavior: HitTestBehavior.translucent,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          _resetTimer();
          return KeyEventResult.ignored; // let the key still reach the real UI/nav
        },
        child: Stack(
          children: [
            widget.child,
            if (_idle) _Screensaver(onDismiss: _resetTimer),
          ],
        ),
      ),
    );
  }
}

class _Screensaver extends StatelessWidget {
  final VoidCallback onDismiss;
  const _Screensaver({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final b = Branding.I;
    return GestureDetector(
      onTap: onDismiss,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        builder: (context, opacity, _) => Opacity(
          opacity: opacity,
          child: Container(
            color: Colors.black,
            width: double.infinity,
            height: double.infinity,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/logo.png',
                    width: 96,
                    height: 96,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.live_tv, size: 96, color: b.primaryColor),
                  ),
                  const SizedBox(height: 24),
                  _Clock(color: b.primaryColor),
                  const SizedBox(height: 8),
                  Text(
                    b.appName,
                    style: const TextStyle(color: Colors.white38, fontSize: 14, letterSpacing: 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  final Color color;
  const _Clock({required this.color});

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$h:$m',
      style: TextStyle(color: widget.color, fontSize: 56, fontWeight: FontWeight.w300),
    );
  }
}
