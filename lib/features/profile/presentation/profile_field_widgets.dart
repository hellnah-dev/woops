import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/state_views.dart';
import '../application/profile_providers.dart';
import '../domain/profile_enums.dart';
import '../domain/profile_models.dart';

/// Interest chips loaded from the server catalogue.
class InterestPicker extends ConsumerWidget {
  const InterestPicker({super.key, required this.selected, required this.onChanged, this.max = 10});

  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final int max;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interests = ref.watch(interestsProvider);
    return interests.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(interestsProvider)),
      data: (all) {
        final byId = {for (final i in all) i.id: i};
        return ChoiceChipGroup<Interest>(
          options: all,
          selected: selected.map((id) => byId[id]).whereType<Interest>().toSet(),
          labelOf: (i) => i.name,
          leadingOf: (i) => i.emoji,
          maxSelected: max,
          onChanged: (set) => onChanged(set.map((i) => i.id).toSet()),
        );
      },
    );
  }
}

/// Edit up to three prompt answers.
class PromptsEditor extends StatelessWidget {
  const PromptsEditor({super.key, required this.prompts, required this.onChanged, this.max = 3});

  final List<ProfilePrompt> prompts;
  final ValueChanged<List<ProfilePrompt>> onChanged;
  final int max;

  Future<void> _edit(BuildContext context, {int? index}) async {
    final used = prompts.map((p) => p.prompt).toSet();
    final result = await showModalBottomSheet<ProfilePrompt>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PromptSheet(
        initial: index == null ? null : prompts[index],
        available: profilePromptQuestions
            .where((q) => !used.contains(q) || (index != null && prompts[index].prompt == q))
            .toList(),
      ),
    );
    if (result == null) return;
    final next = [...prompts];
    if (index == null) {
      next.add(result);
    } else {
      next[index] = result;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < prompts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                title: Text(prompts[i].prompt, style: theme.textTheme.labelLarge),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(prompts[i].answer, style: theme.textTheme.bodyLarge),
                ),
                onTap: () => _edit(context, index: i),
                trailing: IconButton(
                  tooltip: 'Remove prompt',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => onChanged([...prompts]..removeAt(i)),
                ),
              ),
            ),
          ),
        if (prompts.length < max)
          OutlinedButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a prompt'),
          ),
      ],
    );
  }
}

class _PromptSheet extends StatefulWidget {
  const _PromptSheet({required this.available, this.initial});
  final List<String> available;
  final ProfilePrompt? initial;

  @override
  State<_PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<_PromptSheet> {
  late String _prompt = widget.initial?.prompt ?? widget.available.first;
  late final _answer = TextEditingController(text: widget.initial?.answer);

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pick a prompt', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _prompt,
            isExpanded: true,
            items: [for (final q in widget.available) DropdownMenuItem(value: q, child: Text(q))],
            onChanged: (v) => setState(() => _prompt = v ?? _prompt),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _answer,
            autofocus: true,
            maxLength: 250,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Your answer'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _answer.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, ProfilePrompt(prompt: _prompt, answer: _answer.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Section header used in forms.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm + 2),
      child: Row(
        children: [
          Expanded(child: Text(text, style: theme.textTheme.titleMedium)),
          if (trailing != null)
            Text(trailing!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
