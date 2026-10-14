/// Paquete de recetas para importar en bloque (archivo .json).
///
/// Formato:
/// {
///   "app": "recetas_app", "kind": "recipe_pack", "format": 1, "title": "...",
///   "foods": [ {"key": "c:x", "name": "...", "category": "...", "density": 1.0,
///               "nutrients": {"energy_kcal": 20}} ],
///   "targets": {"energy_kcal": 2000, "protein_g": 150},
///   "plan": [ {"day": 0, "slot": "desayuno", "recipe": "Nombre", "servings": 1} ],
///   "recipes": [ {"name": "...", "category": "...", "servings": 4, "prep_min": 30,
///                 "instructions": "...", "tags": "...",
///                 "ingredients": [ {"food_id": 123 | "food_key": "c:x", "food_name": "...",
///                                   "qty": 1, "unit": "taza", "grams": 120, "note": "..."} ]} ]
/// }
library;

import 'dart:convert';

import 'models.dart';
import 'text.dart';

class PackFood {
  final String key;
  final String name;
  final String category;
  final double density;
  final Map<String, double> nutrients; // código de nutriente -> por 100 g

  const PackFood({
    required this.key,
    required this.name,
    required this.category,
    required this.density,
    required this.nutrients,
  });
}

class PackIngredient {
  final int? foodId;
  final String? foodKey;
  final String foodName;
  final double qty;
  final String unit;
  final double grams;
  final String note;

  const PackIngredient({
    this.foodId,
    this.foodKey,
    required this.foodName,
    required this.qty,
    required this.unit,
    required this.grams,
    required this.note,
  });
}

class PackRecipe {
  final Recipe recipe; // sin ingredientes
  final List<PackIngredient> ingredients;
  const PackRecipe(this.recipe, this.ingredients);
}

/// Comida de un plan: [day] cuenta desde el primer día del plan (0, 1, 2...).
class PackPlanEntry {
  final int day;
  final String slot;
  final String recipe;
  final double servings;
  const PackPlanEntry(this.day, this.slot, this.recipe, this.servings);
}

class RecipePack {
  final String title;
  final List<PackFood> foods;
  final List<PackRecipe> recipes;
  final List<PackPlanEntry> plan;
  final Map<String, double> targets; // metas diarias sugeridas por el plan
  const RecipePack(this.title, this.foods, this.recipes,
      [this.plan = const [], this.targets = const {}]);

  /// Cantidad de días que abarca el plan.
  int get planDays =>
      plan.isEmpty ? 0 : plan.map((e) => e.day).reduce((a, b) => a > b ? a : b) + 1;
}

/// Ubicación (semana, día 0..6) de cada día del plan a partir de [start].
({String weekStart, int day}) planSlotDate(DateTime start, int offset) {
  final d = addDays(start, offset);
  return (weekStart: weekStartOf(d), day: d.weekday - 1);
}

double _d(Object? v, [double def = 0]) =>
    v is num ? v.toDouble() : double.tryParse('$v') ?? def;

bool isRecipePack(Map<String, dynamic> data) =>
    data['app'] == 'recetas_app' && data['kind'] == 'recipe_pack';

RecipePack parseRecipePack(String json) {
  final data = jsonDecode(json);
  if (data is! Map<String, dynamic> || !isRecipePack(data)) {
    throw const FormatException('No es un recetario de esta app');
  }
  final foods = <PackFood>[];
  for (final f in (data['foods'] as List?) ?? const []) {
    final m = f as Map<String, dynamic>;
    final nut = <String, double>{};
    ((m['nutrients'] as Map?) ?? const {}).forEach((k, v) => nut['$k'] = _d(v));
    foods.add(PackFood(
      key: m['key'] as String,
      name: (m['name'] as String).trim(),
      category: (m['category'] as String?) ?? 'Almacén',
      density: _d(m['density'], 1.0),
      nutrients: nut,
    ));
  }
  final keys = foods.map((f) => f.key).toSet();
  final recipes = <PackRecipe>[];
  for (final r in (data['recipes'] as List?) ?? const []) {
    final m = r as Map<String, dynamic>;
    final name = ((m['name'] as String?) ?? '').trim();
    if (name.isEmpty) continue;
    final cat = (m['category'] as String?) ?? defaultRecipeCategory;
    final recipe = Recipe(
      name: name,
      servings: _d(m['servings'], 1) > 0 ? _d(m['servings'], 1) : 1,
      prepMin: (m['prep_min'] as num?)?.toInt(),
      cookMin: (m['cook_min'] as num?)?.toInt(),
      instructions: (m['instructions'] as String?) ?? '',
      tags: (m['tags'] as String?) ?? '',
      category: recipeCategories.contains(cat) ? cat : defaultRecipeCategory,
    );
    final ings = <PackIngredient>[];
    for (final i in (m['ingredients'] as List?) ?? const []) {
      final x = i as Map<String, dynamic>;
      final key = x['food_key'] as String?;
      final id = (x['food_id'] as num?)?.toInt();
      if (id == null && (key == null || !keys.contains(key))) continue;
      ings.add(PackIngredient(
        foodId: id,
        foodKey: key,
        foodName: (x['food_name'] as String?) ?? '',
        qty: _d(x['qty']),
        unit: (x['unit'] as String?) ?? 'g',
        grams: _d(x['grams']),
        note: (x['note'] as String?) ?? '',
      ));
    }
    recipes.add(PackRecipe(recipe, ings));
  }
  final plan = <PackPlanEntry>[];
  for (final e in (data['plan'] as List?) ?? const []) {
    final m = e as Map<String, dynamic>;
    final day = (m['day'] as num?)?.toInt() ?? -1;
    final slot = (m['slot'] as String?) ?? '';
    final name = ((m['recipe'] as String?) ?? '').trim();
    final serv = _d(m['servings'], 1);
    if (day < 0 || day > 60 || !mealSlots.contains(slot) || name.isEmpty || serv <= 0) {
      continue;
    }
    plan.add(PackPlanEntry(day, slot, name, serv));
  }
  final targets = <String, double>{};
  ((data['targets'] as Map?) ?? const {}).forEach((k, v) {
    final x = _d(v, -1);
    if (x > 0) targets['$k'] = x;
  });
  return RecipePack(
      (data['title'] as String?) ?? 'Recetario', foods, recipes, plan, targets);
}

/// Clave para detectar recetas repetidas (sin tildes ni mayúsculas).
String recipeNameKey(String name) => normalize(name.trim());
