import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/state_views.dart';
import '../../chat/application/chat_controllers.dart';
import '../../discovery/application/discovery_controller.dart';
import '../data/safety_repository.dart';

void _afterSafetyAction(WidgetRef ref) {
  ref.read(inboxProvider.notifier).refresh();
  ref.invalidate(likesReceivedProvider);
  ref.read(discoveryControllerProvider.notifier).load(reset: true);
}

/// Confirms, then blocks. Returns true if the user was blocked.
Future<bool> confirmAndBlock(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String name,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Block $name?'),
      content: Text(
        '$name won’t be able to see your profile or message you, and you’ll be unmatched. '
        'They won’t be told that you blocked them.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await ref.read(safetyRepositoryProvider).block(userId);
    _afterSafetyAction(ref);
    if (context.mounted) showSnack(context, '$name has been blocked');
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, e);
    return false;
  }
}

/// Report flow. Returns true if a report was sent (and the user possibly blocked).
Future<bool> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String name,
  String? messageId,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReportSheet(userId: userId, name: name, messageId: messageId),
  );
  if (sent == true) _afterSafetyAction(ref);
  return sent == true;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.userId, required this.name, this.messageId});

  final String userId;
  final String name;
  final String? messageId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  ReportReason? _reason;
  bool _alsoBlock = true;
  bool _sending = false;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() => _sending = true);
    final repo = ref.read(safetyRepositoryProvider);
    try {
      await repo.report(
        widget.userId,
        reason,
        details: _details.text.trim().isEmpty ? null : _details.text.trim(),
        messageId: widget.messageId,
      );
      if (_alsoBlock) await repo.block(widget.userId);
      if (!mounted) return;
      showSnack(context, 'Thanks for letting us know. Our team will review this report.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Report ${widget.name}', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Your report is confidential. ${widget.name} won’t know who reported them.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(value: r, contentPadding: EdgeInsets.zero, title: Text(r.label)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _details,
              maxLength: 1000,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Anything else we should know? (optional)'),
            ),
            SwitchListTile(
              value: _alsoBlock,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _alsoBlock = v),
              title: Text('Also block ${widget.name}'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              onPressed: _reason == null || _sending ? null : _send,
              child: _sending
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : const Text('Send report'),
            ),
          ],
        ),
      ),
    );
  }
}
