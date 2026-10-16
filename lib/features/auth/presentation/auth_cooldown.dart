import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Friendly handling of Supabase Auth rate limits ("too many attempts").
///
/// Supabase limits sign-ins/sign-ups per IP address (default 30 per 5 minutes)
/// and auth emails (with the built-in email service, 2 per hour). When a limit
/// is hit we show a countdown instead of letting people retry into more errors.
/// The wait survives an app restart.
class AuthCooldown {
  AuthCooldown._();

  static bool isRateLimited(Object e) {
    if (e is AuthException) {
      final m = e.message.toLowerCase();
      return e.statusCode == '429' || m.contains('rate limit') || m.contains('too many');
    }
    return false;
  }

  /// Emails (confirmation, reset link) unlock after an hour; sign-ins after 5 minutes.
  static Duration waitFor(Object e) => e is AuthException && e.message.toLowerCase().contains('email')
      ? const Duration(hours: 1)
      : const Duration(minutes: 5);

  static String _key(String action) => 'auth_cooldown_$action';

  static Future<void> start(String action, Duration wait) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key(action), DateTime.now().add(wait).millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<DateTime?> until(String action) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_key(action));
      if (ms == null) return null;
      final t = DateTime.fromMillisecondsSinceEpoch(ms);
      return t.isAfter(DateTime.now()) ? t : null;
    } catch (_) {
      return null;
    }
  }
}

/// Rebuilds every second while a cooldown runs. [builder] gets the time left
/// (null when the action is allowed).
class CooldownBuilder extends StatefulWidget {
  const CooldownBuilder({super.key, required this.action, required this.builder});
  final String action;
  final Widget Function(BuildContext context, Duration? remaining) builder;

  @override
  State<CooldownBuilder> createState() => CooldownBuilderState();
}

class CooldownBuilderState extends State<CooldownBuilder> {
  DateTime? _until;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Call after [AuthCooldown.start] to show the countdown right away.
  Future<void> reload() async {
    final until = await AuthCooldown.until(widget.action);
    if (!mounted) return;
    setState(() => _until = until);
    _timer?.cancel();
    if (until != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (!DateTime.now().isBefore(_until!)) {
          _timer?.cancel();
          setState(() => _until = null);
        } else {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _until?.difference(DateTime.now());
    return widget.builder(context, left == null || left.isNegative ? null : left);
  }
}

String formatWait(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m >= 60 ? '${d.inHours} h ${m % 60} min' : '$m:${s.toString().padLeft(2, '0')}';
}

/// Explains the wait under a disabled button.
class CooldownNotice extends StatelessWidget {
  const CooldownNotice({super.key, required this.remaining, required this.what});
  final Duration remaining;
  final String what;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Too many attempts for now, to keep accounts safe. You can $what again in ${formatWait(remaining)}.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
