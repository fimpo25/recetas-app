import 'package:flutter/material.dart';

import '../../common/recipe_style.dart';
import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/models.dart';
import '../../domain/nutrition_calc.dart';
import '../../domain/text.dart';
import '../recipes/recipe_detail_page.dart';

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  String _week = weekStartOf(DateTime.now());
  List<PlanEntry> _entries = [];
  List<NutritionTotals> _days = [];
  int? _energyId;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = Repo.instance;
    final entries = await repo.planEntries(_week);
    final days = await repo.weekDayTotals(_week);
    final energy = await repo.nutrientByCode('energy_kcal');
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _days = days;
      _energyId = energy?.id;
      _loaded = true;
    });
  }

  Future<void> _add(int day, String slot) async {
    final recipes = await Repo.instance.recipes();
    if (!mounted) return;
    if (recipes.isEmpty) {
      showSnack(context, 'Primero cargá recetas en la pestaña Recetas.');
      return;
    }
    final picked = await showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _RecipePickerSheet(recipes: recipes),
    );
    if (picked == null || !mounted) return;
    final servings = await askNumber(context,
        title: 'Porciones de ${picked.name}', initial: 1);
    if (servings == null || servings <= 0) return;
    await Repo.instance.addPlanEntry(PlanEntry(
      weekStart: _week,
      day: day,
      slot: slot,
      recipeId: picked.id!,
      recipeName: picked.name,
      servings: servings,
    ));
    _load();
  }

  Future<void> _entryMenu(PlanEntry e) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('Ver receta'),
              onTap: () => Navigator.pop(ctx, 'view'),
            ),
            ListTile(
              leading: const Icon(Icons.exposure),
              title: const Text('Cambiar porciones'),
              onTap: () => Navigator.pop(ctx, 'servings'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Quitar del plan'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'view':
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => RecipeDetailPage(recipeId: e.recipeId)),
        );
        break;
      case 'servings':
        final s = await askNumber(context,
            title: 'Porciones', initial: e.servings);
        if (s != null && s > 0) {
          await Repo.instance.updatePlanServings(e.id!, s);
        }
        break;
      case 'delete':
        await Repo.instance.deletePlanEntry(e.id!);
        break;
    }
    _load();
  }

  Future<void> _copyPrevious() async {
    if (_entries.isNotEmpty) {
      final ok = await confirm(context, 'Copiar semana anterior',
          'Esta semana ya tiene comidas. Se agregan las de la semana anterior a las existentes.');
      if (!ok) return;
    }
    final n = await Repo.instance.copyPreviousWeek(_week);
    if (!mounted) return;
    showSnack(context, n == 0 ? 'La semana anterior está vacía.' : 'Se copiaron $n comidas.');
    _load();
  }

  Future<void> _clear() async {
    final ok = await confirm(
        context, 'Vaciar semana', 'Se quitan todas las comidas de esta semana.');
    if (!ok) return;
    await Repo.instance.clearWeek(_week);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final start = parseIso(_week);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan semanal'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'copy') _copyPrevious();
              if (v == 'clear') _clear();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('Copiar semana anterior')),
              PopupMenuItem(value: 'clear', child: Text('Vaciar semana')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          WeekSelector(
            weekStart: _week,
            onChanged: (w) {
              _week = w;
              _load();
            },
          ),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: 7,
                    itemBuilder: (context, day) {
                      final date = addDays(start, day);
                      final kcal = (_energyId != null && day < _days.length)
                          ? _days[day].value(_energyId!)
                          : 0.0;
                      return _DayCard(
                        title: '${dayLabels[day]} ${fmtShortDate(date)}',
                        kcal: kcal,
                        entries: _entries.where((e) => e.day == day).toList(),
                        onAdd: (slot) => _add(day, slot),
                        onTapEntry: _entryMenu,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final String title;
  final double kcal;
  final List<PlanEntry> entries;
  final void Function(String slot) onAdd;
  final void Function(PlanEntry e) onTapEntry;

  const _DayCard({
    required this.title,
    required this.kcal,
    required this.entries,
    required this.onAdd,
    required this.onTapEntry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                if (kcal > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('${fmtNum(kcal, decimals: 0)} kcal'),
                  ),
              ],
            ),
            for (final slot in mealSlots)
              _slotRow(context, slot, entries.where((e) => e.slot == slot).toList()),
          ],
        ),
      ),
    );
  }

  Widget _slotRow(BuildContext context, String slot, List<PlanEntry> items) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 82,
          child: Text(mealSlotLabels[slot]!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final e in items)
                ActionChip(
                  label: Text(
                    e.servings == 1
                        ? e.recipeName
                        : '${e.recipeName} ×${fmtNum(e.servings)}',
                  ),
                  onPressed: () => onTapEntry(e),
                ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 20),
          onPressed: () => onAdd(slot),
        ),
      ],
    );
  }
}

class _RecipePickerSheet extends StatefulWidget {
  final List<Recipe> recipes;
  const _RecipePickerSheet({required this.recipes});

  @override
  State<_RecipePickerSheet> createState() => _RecipePickerSheetState();
}

class _RecipePickerSheetState extends State<_RecipePickerSheet> {
  String _q = '';
  String? _category;

  @override
  Widget build(BuildContext context) {
    final q = normalize(_q);
    final used = widget.recipes.map((r) => r.category).toSet();
    final cats = recipeCategories.where(used.contains).toList();
    final list = widget.recipes
        .where((r) => _category == null || r.category == _category)
        .where((r) =>
            q.isEmpty ||
            normalize('${r.name} ${r.tags} ${r.category}').contains(q))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Elegí una receta',
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            if (cats.length > 1)
              CategoryFilter(
                categories: cats,
                selected: _category,
                onChanged: (c) => setState(() => _category = c),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) => ListTile(
                  leading: CategoryAvatar(list[i].category, size: 38),
                  title: Text(list[i].name,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    list[i].category,
                    if (bookOf(list[i].tags) != null) bookOf(list[i].tags)!,
                  ].join(' · ')),
                  onTap: () => Navigator.pop(context, list[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
