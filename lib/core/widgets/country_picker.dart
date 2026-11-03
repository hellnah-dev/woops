import 'package:flutter/material.dart';

import '../i18n/countries.dart';

/// Searchable country list. Returns the chosen country (single mode) or the
/// chosen set (multi mode, via [showCountryMultiPicker]).
Future<Country?> showCountryPicker(BuildContext context, {String? selected}) => showModalBottomSheet<Country>(
  // Over the whole screen, never under the glass tab bar.
  useRootNavigator: true,
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _CountrySheet(initial: {?selected}, multi: false),
);

Future<Set<String>?> showCountryMultiPicker(BuildContext context, {required Set<String> selected}) =>
    showModalBottomSheet<Set<String>>(
      // Over the whole screen, never under the glass tab bar.
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CountrySheet(initial: selected, multi: true),
    );

class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.initial, required this.multi});
  final Set<String> initial;
  final bool multi;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  late final Set<String> _selected = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? allCountries
        : allCountries.where((c) => c.name.toLowerCase().contains(q) || c.code.toLowerCase() == q).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: !widget.multi,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search countries'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: results.length,
              itemBuilder: (context, i) {
                final c = results[i];
                final isSelected = _selected.contains(c.code);
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 26)),
                  title: Text(c.name),
                  trailing: isSelected ? Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary) : null,
                  onTap: () {
                    if (!widget.multi) {
                      Navigator.pop(context, c);
                      return;
                    }
                    setState(() => isSelected ? _selected.remove(c.code) : _selected.add(c.code));
                  },
                );
              },
            ),
          ),
          if (widget.multi)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, <String>{}),
                        child: const Text('Any country'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, _selected),
                        child: Text(_selected.isEmpty ? 'Done' : 'Done (${_selected.length})'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
