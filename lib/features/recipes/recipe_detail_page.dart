import 'package:flutter/material.dart';

import '../../common/nutrition_table.dart';
import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/models.dart';
import '../../domain/nutrition_calc.dart';
import '../../domain/text.dart';
import '../../domain/units.dart';
import 'recipe_edit_page.dart';

class RecipeDetailPage extends StatefulWidget {
  final int recipeId;
  const RecipeDetailPage({super.key, required this.recipeId});

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  Recipe? _recipe;
  NutritionTotals _perServing = NutritionTotals.empty;
  List<double> _kcal = [];
  List<Nutrient> _nutrients = [];
  Map<String, Target> _targets = {};
  double _servings = 1;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = Repo.instance;
    final r = await repo.recipe(widget.recipeId);
    if (r == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final totals = await repo.recipeTotals(r);
    final kcal = await repo.ingredientKcal(r);
    final ns = await repo.nutrients();
    final ts = await repo.targets();
    if (!mounted) return;
    setState(() {
      _recipe = r;
      _perServing = r.servings > 0 ? perServing(totals, r.servings) : totals;
      _kcal = kcal;
      _nutrients = ns;
      _targets = ts;
      _servings = r.servings;
      _loaded = true;
    });
  }

  Future<void> _edit() async {
    await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => RecipeEditPage(recipe: _recipe)),
    );
    _load();
  }

  Future<void> _delete() async {
    final ok = await confirm(context, 'Borrar receta',
        'Se borra "${_recipe!.name}" y sus apariciones en el plan semanal.');
    if (!ok) return;
    await Repo.instance.deleteRecipe(_recipe!.id!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _duplicate() async {
    final id = await Repo.instance.duplicateRecipe(_recipe!.id!);
    if (!mounted) return;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => RecipeDetailPage(recipeId: id)),
    );
  }

  Future<void> _addToPlan() async {
    final r = _recipe!;
    var day = DateTime.now().weekday - 1;
    var slot = 'almuerzo';
    var servings = 1.0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Agregar al plan de esta semana'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: day,
                decoration: const InputDecoration(labelText: 'Día'),
                items: [
                  for (var i = 0; i < 7; i++)
                    DropdownMenuItem(value: i, child: Text(dayLabels[i])),
                ],
                onChanged: (v) => setD(() => day = v ?? day),
              ),
              DropdownButtonFormField<String>(
                initialValue: slot,
                decoration: const InputDecoration(labelText: 'Comida'),
                items: [
                  for (final s in mealSlots)
                    DropdownMenuItem(value: s, child: Text(mealSlotLabels[s]!)),
                ],
                onChanged: (v) => setD(() => slot = v ?? slot),
              ),
              TextFormField(
                initialValue: '1',
                decoration: const InputDecoration(labelText: 'Porciones'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => servings = parseNum(v) ?? servings,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Agregar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await Repo.instance.addPlanEntry(PlanEntry(
      weekStart: weekStartOf(DateTime.now()),
      day: day,
      slot: slot,
      recipeId: r.id!,
      recipeName: r.name,
      servings: servings,
    ));
    if (mounted) {
      showSnack(context,
          'Agregada al ${dayLabels[day].toLowerCase()}, ${mealSlotLabels[slot]!.toLowerCase()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final r = _recipe!;
    final factor = r.servings > 0 ? _servings / r.servings : 1.0;
    final theme = Theme.of(context);
    final time = <String>[
      if (r.prepMin != null) 'Preparación ${r.prepMin} min',
      if (r.cookMin != null) 'Cocción ${r.cookMin} min',
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(r.name),
        actions: [
          IconButton(
              tooltip: 'Agregar al plan',
              icon: const Icon(Icons.event_available),
              onPressed: _addToPlan),
          IconButton(
              tooltip: 'Editar', icon: const Icon(Icons.edit), onPressed: _edit),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'dup') _duplicate();
              if (v == 'del') _delete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dup', child: Text('Duplicar')),
              PopupMenuItem(value: 'del', child: Text('Borrar')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text([r.category, ...time, if (r.tags.isNotEmpty) r.tags].join(' · '),
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Porciones', style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _servings > 1
                    ? () => setState(() => _servings -= 1)
                    : null,
              ),
              Text(fmtNum(_servings), style: theme.textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _servings += 1),
              ),
            ],
          ),
          const Divider(),
          Text('Ingredientes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (r.ingredients.isEmpty) const Text('Sin ingredientes cargados.'),
          for (var i = 0; i < r.ingredients.length; i++)
            _ingredientRow(r.ingredients[i], factor,
                i < _kcal.length ? _kcal[i] * factor : 0.0),
          const Divider(),
          Text('Nutrición por porción', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          NutritionTable(
            nutrients: _nutrients,
            totals: _perServing,
            targets: _targets,
          ),
          if (r.instructions.trim().isNotEmpty) ...[
            const Divider(),
            Text('Preparación', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(r.instructions),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _ingredientRow(RecipeIngredient ing, double factor, double kcal) {
    final qty = ing.qty * factor;
    final grams = ing.grams * factor;
    final showGrams = ing.unit != 'g' && ing.grams > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(qtyLabel(qty, ing.unit)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ing.foodName),
                if (ing.note.isNotEmpty || showGrams)
                  Text(
                    [
                      if (showGrams) fmtGrams(grams),
                      if (ing.note.isNotEmpty) ing.note,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
          Text('${fmtNum(kcal, decimals: 0)} kcal',
              style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
