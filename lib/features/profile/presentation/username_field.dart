import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/validators.dart';
import '../data/profile_repository.dart';

/// Username input with a live (debounced) availability check against the
/// server's unique index. [onChanged] reports the value and whether it's usable.
class UsernameField extends ConsumerStatefulWidget {
  const UsernameField({super.key, required this.onChanged, this.initial, this.current});

  final String? initial;

  /// The user's existing username (always "available" to them).
  final String? current;
  final void Function(String value, bool available) onChanged;

  @override
  ConsumerState<UsernameField> createState() => _UsernameFieldState();
}

class _UsernameFieldState extends ConsumerState<UsernameField> {
  late final _controller = TextEditingController(text: widget.initial);
  Timer? _debounce;
  bool? _available;
  bool _checking = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    if ((widget.initial ?? '').isNotEmpty) _check(widget.initial!);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _available = null);
    widget.onChanged(value, false);
    if (Validators.username(value) != null) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _check(value));
  }

  Future<void> _check(String value) async {
    if (value.trim().toLowerCase() == widget.current?.toLowerCase()) {
      setState(() => _available = true);
      widget.onChanged(value, true);
      return;
    }
    final id = ++_requestId;
    setState(() => _checking = true);
    try {
      final ok = await ref.read(profileRepositoryProvider).isUsernameAvailable(value);
      if (!mounted || id != _requestId) return;
      setState(() => _available = ok);
      widget.onChanged(value, ok);
    } catch (_) {
      if (mounted && id == _requestId) setState(() => _available = null);
    } finally {
      if (mounted && id == _requestId) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatError = _controller.text.isEmpty ? null : Validators.username(_controller.text);
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      key: const Key('username-field'),
      controller: _controller,
      autocorrect: false,
      maxLength: 20,
      onChanged: _onChanged,
      decoration: InputDecoration(
        prefixText: '@',
        hintText: 'username',
        errorText: formatError ?? (_available == false ? 'That username is taken' : null),
        helperText: _available == true ? 'Available' : null,
        helperStyle: TextStyle(color: scheme.primary),
        suffixIcon: _checking
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : _available == true
                ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                : null,
      ),
    );
  }
}
