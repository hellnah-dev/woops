import 'package:flutter/material.dart';

/// A wrap of selectable chips supporting single or multi-select.
class ChoiceChipGroup<T> extends StatelessWidget {
  const ChoiceChipGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.multiSelect = true,
    this.maxSelected,
    this.leadingOf,
  });

  final List<T> options;
  final Set<T> selected;
  final String Function(T) labelOf;
  final String? Function(T)? leadingOf;
  final ValueChanged<Set<T>> onChanged;
  final bool multiSelect;
  final int? maxSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          FilterChip(
            showCheckmark: false,
            selected: selected.contains(option),
            selectedColor: scheme.primary.withValues(alpha: 0.15),
            side: BorderSide(color: selected.contains(option) ? scheme.primary : scheme.outlineVariant),
            label: Text(
              [if (leadingOf?.call(option) != null) leadingOf!(option)!, labelOf(option)].join(' '),
            ),
            onSelected: (isSelected) {
              final next = {...selected};
              if (!multiSelect) {
                onChanged({option});
                return;
              }
              if (isSelected) {
                if (maxSelected != null && next.length >= maxSelected!) return;
                next.add(option);
              } else {
                next.remove(option);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}
