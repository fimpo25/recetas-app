import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../domain/models.dart';
import '../domain/nutrition_calc.dart';
import '../domain/targets.dart';
import '../domain/text.dart';

/// Tabla de nutrientes con % de valor diario y aviso de datos faltantes.
class NutritionTable extends StatelessWidget {
  final List<Nutrient> nutrients;
  final NutritionTotals totals;
  final Map<String, Target> targets;
  final double dvDivisor; // 1 = día; 7 = promedio semanal sobre el total

  const NutritionTable({
    super.key,
    required this.nutrients,
    required this.totals,
    required this.targets,
    this.dvDivisor = 1,
  });

  @override
  Widget build(BuildContext context) {
    final macros = nutrients.where((n) => n.kind == 'macro').toList();
    final micros = nutrients.where((n) => n.kind != 'macro').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MacroSplit(nutrients: nutrients, totals: totals),
        const SizedBox(height: 8),
        _header(context, 'Macronutrientes'),
        ...macros.map((n) => _row(context, n)),
        const SizedBox(height: 8),
        _header(context, 'Micronutrientes'),
        ...micros.map((n) => _row(context, n)),
      ],
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _row(BuildContext context, Nutrient n) {
    final value = totals.value(n.id) / dvDivisor;
    final t = targets[n.code];
    final pct = t == null ? null : percentDv(value, t.value);
    final alert = (pct != null && t != null) ? isAlert(pct, t.upper) : false;
    final missing = totals.missingShare(n.id);
    final scheme = Theme.of(context).colorScheme;
    final decimals = n.unit == 'kcal' || n.unit == 'mg' ? 0 : 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(n.nameEs)),
              Text('${fmtNum(value, decimals: decimals)} ${n.unit}'),
              SizedBox(
                width: 64,
                child: Text(
                  pct == null ? '' : '${fmtNum(pct, decimals: 0)} %',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: alert ? scheme.error : null),
                ),
              ),
            ],
          ),
          if (pct != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0).toDouble(),
                color: alert ? scheme.error : scheme.primary,
                minHeight: 4,
              ),
            ),
          if (missing > 0.001)
            Text(
              'Sin dato en ${fmtNum(missing * 100, decimals: 0)} % de los ingredientes',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
        ],
      ),
    );
  }
}

class _MacroSplit extends StatelessWidget {
  final List<Nutrient> nutrients;
  final NutritionTotals totals;
  const _MacroSplit({required this.nutrients, required this.totals});

  double _by(String code) {
    for (final n in nutrients) {
      if (n.code == code) return totals.value(n.id);
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final p = _by('protein_g') * 4;
    final c = _by('carbs_g') * 4;
    final f = _by('fat_g') * 9;
    final sum = p + c + f;
    if (sum <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    Widget seg(double v, Color color) => Expanded(
          flex: (v / sum * 1000).round().clamp(1, 1000).toInt(),
          child: Container(height: 10, color: color),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Row(children: [
            seg(p, scheme.primary),
            seg(c, scheme.tertiary),
            seg(f, scheme.secondary),
          ]),
        ),
        const SizedBox(height: 4),
        Text(
          'Energía de: proteínas ${fmtNum(p / sum * 100, decimals: 0)} % · '
          'carbohidratos ${fmtNum(c / sum * 100, decimals: 0)} % · '
          'grasas ${fmtNum(f / sum * 100, decimals: 0)} %',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
