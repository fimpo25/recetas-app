import 'package:flutter/material.dart';

import '../../common/nutrition_table.dart';
import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/models.dart';
import '../../domain/nutrition_calc.dart';
import '../../domain/text.dart';

/// Resumen nutricional del plan: por día o promedio semanal.
class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage> {
  String _week = weekStartOf(DateTime.now());
  int _view = DateTime.now().weekday - 1; // 0..6 día, 7 = promedio semana
  List<NutritionTotals> _days = [];
  List<Nutrient> _nutrients = [];
  Map<String, Target> _targets = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = Repo.instance;
    final days = await repo.weekDayTotals(_week);
    final ns = await repo.nutrients();
    final ts = await repo.targets();
    if (!mounted) return;
    setState(() {
      _days = days;
      _nutrients = ns;
      _targets = ts;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    NutritionTotals totals = NutritionTotals.empty;
    double divisor = 1;
    if (_loaded) {
      if (_view == 7) {
        for (final d in _days) {
          totals = totals.plus(d);
        }
        final planned = _days.where((d) => d.count > 0).length;
        divisor = planned == 0 ? 1 : planned.toDouble();
      } else if (_view < _days.length) {
        totals = _days[_view];
      }
    }
    final start = parseIso(_week);
    return Scaffold(
      appBar: AppBar(title: const Text('Nutrición')),
      body: Column(
        children: [
          WeekSelector(
            weekStart: _week,
            onChanged: (w) {
              _week = w;
              _load();
            },
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                          '${dayLabels[i].substring(0, 3)} ${addDays(start, i).day}'),
                      selected: _view == i,
                      onSelected: (_) => setState(() => _view = i),
                    ),
                  ),
                ChoiceChip(
                  label: const Text('Promedio semana'),
                  selected: _view == 7,
                  onSelected: (_) => setState(() => _view = 7),
                ),
              ],
            ),
          ),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : totals.count == 0
                    ? const EmptyState(
                        icon: Icons.insights_outlined,
                        text: 'No hay comidas planificadas para este período.',
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_view == 7)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                  'Promedio diario sobre ${fmtNum(divisor, decimals: 0)} días con comidas planificadas.'),
                            ),
                          NutritionTable(
                            nutrients: _nutrients,
                            totals: totals,
                            targets: _targets,
                            dvDivisor: divisor,
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
