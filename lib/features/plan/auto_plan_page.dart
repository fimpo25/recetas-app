import 'package:flutter/material.dart';

import '../../common/recipe_style.dart';
import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/meal_planner.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';
import '../recipes/recipe_detail_page.dart';

/// Arma el plan de la semana según metas de kcal y proteína.
/// Devuelve true (con Navigator.pop) si se guardó.
class AutoPlanPage extends StatefulWidget {
  final String weekStart;
  const AutoPlanPage({super.key, required this.weekStart});

  @override
  State<AutoPlanPage> createState() => _AutoPlanPageState();
}

class _AutoPlanPageState extends State<AutoPlanPage> {
  final _kcal = TextEditingController();
  final _prot = TextEditingController();
  final Set<String> _slots = {'desayuno', 'almuerzo', 'merienda', 'cena'};
  final Set<int> _days = {0, 1, 2, 3, 4, 5, 6};
  Set<String>? _books; // null = todos
  bool _replace = true;
  int _seed = DateTime.now().millisecondsSinceEpoch % 100000;

  List<Recipe> _recipes = [];
  Map<int, RecipeSummary> _sum = {};
  List<PlannedMeal>? _plan;
  PlannerConfig? _cfg;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = Repo.instance;
    final recipes = await repo.recipes();
    final sum = await repo.recipeSummaries();
    final t = await repo.targets();
    if (!mounted) return;
    setState(() {
      _recipes = recipes;
      _sum = sum;
      _kcal.text = fmtNum(t['energy_kcal']?.value ?? 2000, decimals: 0).replaceAll('.', '');
      _prot.text = fmtNum(t['protein_g']?.value ?? 75, decimals: 0).replaceAll('.', '');
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _kcal.dispose();
    _prot.dispose();
    super.dispose();
  }

  List<String> get _bookNames {
    final s = _recipes.map((r) => bookOf(r.tags) ?? 'Mis recetas').toSet().toList()
      ..sort();
    return s;
  }

  List<PlanCandidate> get _candidates => [
        for (final r in _recipes)
          if (_books == null || _books!.contains(bookOf(r.tags) ?? 'Mis recetas'))
            if (_sum[r.id] != null)
              PlanCandidate(r.id!, r.name, r.category, _sum[r.id]!.kcal,
                  _sum[r.id]!.protein),
      ];

  void _generate({bool newSeed = false}) {
    final kcal = parseNum(_kcal.text) ?? 0;
    final prot = parseNum(_prot.text) ?? 0;
    if (kcal < 800 || kcal > 6000) {
      showSnack(context, 'Poné una meta de calorías entre 800 y 6000 kcal.');
      return;
    }
    if (_slots.isEmpty || _days.isEmpty) {
      showSnack(context, 'Elegí al menos una comida y un día.');
      return;
    }
    if (newSeed) _seed++;
    final cfg = PlannerConfig(
      days: _days.toList()..sort(),
      slots: mealSlots.where(_slots.contains).toList(),
      kcal: kcal,
      protein: prot,
      seed: _seed,
    );
    final plan = planWeek(_candidates, cfg);
    setState(() {
      _cfg = cfg;
      _plan = plan;
    });
    if (plan.isEmpty) {
      showSnack(context, 'No hay recetas suficientes con esos filtros.');
    }
  }

  Future<void> _pickBooks() async {
    final all = _bookNames;
    final sel = Set<String>.from(_books ?? all);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 16),
                    const Expanded(
                        child: Text('Recetarios a usar',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600))),
                    TextButton(
                        onPressed: () => setS(() => sel
                          ..clear()
                          ..addAll(all)),
                        child: const Text('Todos')),
                    TextButton(
                        onPressed: () => setS(sel.clear),
                        child: const Text('Ninguno')),
                  ],
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final b in all)
                        CheckboxListTile(
                          value: sel.contains(b),
                          title: Text(b),
                          onChanged: (v) => setS(
                              () => v == true ? sel.add(b) : sel.remove(b)),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Listo'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true) {
      setState(() => _books = sel.length == all.length ? null : sel);
    }
  }

  Future<void> _mealMenu(int index) async {
    final m = _plan![index];
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shuffle),
              title: const Text('Cambiar por otra receta'),
              onTap: () => Navigator.pop(ctx, 'swap'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('Ver receta'),
              onTap: () => Navigator.pop(ctx, 'view'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'swap') {
      _seed++;
      setState(() => rerollMeal(_plan!, index, _candidates, _cfg!, _seed));
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RecipeDetailPage(recipeId: m.recipe.id)),
      );
    }
  }

  Future<void> _save() async {
    final plan = _plan!;
    await Repo.instance.saveAutoPlan(
      widget.weekStart,
      _cfg!.days,
      [
        for (final m in plan)
          (day: m.day, slot: m.slot, recipeId: m.recipe.id, servings: m.servings)
      ],
      replace: _replace,
    );
    if (!mounted) return;
    showSnack(context, 'Plan guardado: ${plan.length} comidas.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final start = parseIso(widget.weekStart);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Armar plan automático')),
      bottomNavigationBar: _plan == null || _plan!.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _generate(newSeed: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Otra opción'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Guardar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Text(
                    'Semana del ${fmtShortDate(start)} al ${fmtShortDate(addDays(start, 6))}',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _kcal,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Calorías por día',
                            suffixText: 'kcal',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _prot,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Proteína por día',
                            suffixText: 'g',
                            border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Comidas', style: TextStyle(fontWeight: FontWeight.w600)),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final s in mealSlots)
                      FilterChip(
                        label: Text(mealSlotLabels[s]!),
                        selected: _slots.contains(s),
                        onSelected: (v) => setState(
                            () => v ? _slots.add(s) : _slots.remove(s)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Días', style: TextStyle(fontWeight: FontWeight.w600)),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var d = 0; d < 7; d++)
                      FilterChip(
                        label: Text(dayLabels[d].substring(0, 3)),
                        selected: _days.contains(d),
                        onSelected: (v) => setState(
                            () => v ? _days.add(d) : _days.remove(d)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Recetarios'),
                  subtitle: Text(_books == null
                      ? 'Todos'
                      : _books!.isEmpty
                          ? 'Ninguno'
                          : _books!.join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickBooks,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reemplazar lo planificado esos días'),
                  value: _replace,
                  onChanged: (v) => setState(() => _replace = v),
                ),
                const SizedBox(height: 4),
                FilledButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(_plan == null ? 'Armar plan' : 'Volver a armar'),
                ),
                if (_plan != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Tocá una comida para cambiarla. Las porciones se ajustan para llegar a la meta de cada día.',
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                  for (final d in _cfg!.days) _dayCard(d, start),
                ],
              ],
            ),
    );
  }

  Widget _dayCard(int day, DateTime start) {
    final plan = _plan!;
    final cfg = _cfg!;
    final (k, p) = dayTotals(plan, day);
    final kOk = (k - cfg.kcal).abs() <= cfg.kcal * 0.05;
    final pOk = cfg.protein <= 0 || p >= cfg.protein * 0.95;
    const good = Color(0xFF81C784);
    const warn = Color(0xFFFFB74D);
    final recipesById = {for (final r in _recipes) r.id: r};
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      '${dayLabels[day]} ${fmtShortDate(addDays(start, day))}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                InfoPill(Icons.local_fire_department,
                    '${fmtNum(k, decimals: 0)} kcal',
                    color: kOk ? good : warn),
                const SizedBox(width: 10),
                InfoPill(Icons.fitness_center, '${fmtNum(p, decimals: 0)} g',
                    color: pOk ? good : warn),
              ],
            ),
            for (var i = 0; i < plan.length; i++)
              if (plan[i].day == day)
                InkWell(
                  onTap: () => _mealMenu(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        RecipeThumb(
                            category: plan[i].recipe.category,
                            photo: recipesById[plan[i].recipe.id]?.photo,
                            size: 46),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(mealSlotLabels[plan[i].slot]!,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: categoryStyle(plan[i].recipe.category)
                                          .color)),
                              Text(plan[i].recipe.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              Text(
                                '${fmtNum(plan[i].servings, decimals: 2)} porc. · '
                                '${fmtNum(plan[i].kcal, decimals: 0)} kcal · '
                                '${fmtNum(plan[i].protein, decimals: 0)} g prot',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.more_vert, size: 18),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
