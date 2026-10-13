import 'package:flutter/material.dart';

import '../domain/text.dart';

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirm(BuildContext context, String title, String body) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aceptar')),
      ],
    ),
  );
  return r ?? false;
}

Future<double?> askNumber(
  BuildContext context, {
  required String title,
  double? initial,
  String? suffix,
}) async {
  final ctrl = TextEditingController(
      text: initial == null ? '' : fmtNum(initial, decimals: 2));
  final r = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(suffixText: suffix),
        onSubmitted: (v) => Navigator.pop(ctx, parseNum(v)),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, parseNum(ctrl.text)),
            child: const Text('Aceptar')),
      ],
    ),
  );
  return r;
}

/// Barra para moverse entre semanas (lunes a domingo).
class WeekSelector extends StatelessWidget {
  final String weekStart;
  final ValueChanged<String> onChanged;

  const WeekSelector({super.key, required this.weekStart, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final start = parseIso(weekStart);
    final end = addDays(start, 6);
    final isCurrent = weekStart == weekStartOf(DateTime.now());
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(shiftWeek(weekStart, -1)),
        ),
        Expanded(
          child: TextButton(
            onPressed: () => onChanged(weekStartOf(DateTime.now())),
            child: Text(
              'Semana ${fmtShortDate(start)} – ${fmtShortDate(end)}${isCurrent ? ' (actual)' : ''}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onChanged(shiftWeek(weekStart, 1)),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
