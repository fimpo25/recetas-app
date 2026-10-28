import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/nutrition_calc.dart';
import '../domain/recipe_pack.dart';
import '../domain/shopping_list.dart';
import '../domain/targets.dart';
import '../domain/text.dart';
import 'db.dart';
import 'photo_store.dart';

/// Los alimentos propios usan IDs desde este valor para no chocar con la base.
const int customFoodBaseId = 1000000;

int _i(Object? v) => (v as num).toInt();
int? _iN(Object? v) => (v as num?)?.toInt();
double _d(Object? v) => (v as num).toDouble();
double? _dN(Object? v) => (v as num?)?.toDouble();
String _s(Object? v) => (v as String?) ?? '';

/// Valores por porción para mostrar en la lista de recetas.
class RecipeSummary {
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  const RecipeSummary(this.kcal, this.protein, this.carbs, this.fat);
}

class Target {
  final double value;
  final bool upper;
  const Target(this.value, this.upper);
}

/// Acceso a datos y cálculos que combinan las dos bases.
class Repo {
  Repo._();
  static final Repo instance = Repo._();

  Database get _nut => AppDb.instance.nut;
  Database get _user => AppDb.instance.user;

  List<Nutrient>? _nutrients;
  Map<int, RecipeSummary>? _summaries;

  /// Invalida los datos resumidos de las recetas (después de cambios).
  void _dirty() => _summaries = null;

  // ---------------------------------------------------------------- nutrientes

  Future<List<Nutrient>> nutrients() async {
    if (_nutrients != null) return _nutrients!;
    final rows = await _nut.query('nutrient', orderBy: 'display_order');
    _nutrients = rows
        .map((r) => Nutrient(
              id: _i(r['id']),
              code: _s(r['code']),
              nameEs: _s(r['name_es']),
              unit: _s(r['unit']),
              kind: _s(r['kind']),
              order: _i(r['display_order']),
            ))
        .toList();
    return _nutrients!;
  }

  Future<Nutrient?> nutrientByCode(String code) async {
    for (final n in await nutrients()) {
      if (n.code == code) return n;
    }
    return null;
  }

  // ---------------------------------------------------------------- alimentos

  Food _nutFood(Map<String, Object?> r) => Food(
        id: _i(r['id']),
        name: (r['name_es'] as String?) ?? _s(r['name_en']),
        nameEn: r['name_en'] as String?,
        category: _s(r['category']),
        density: _dN(r['density_g_ml']) ?? 1.0,
        edible: _dN(r['edible_fraction']) ?? 1.0,
      );

  Food _customFood(Map<String, Object?> r) => Food(
        id: _i(r['id']),
        name: _s(r['name']),
        category: _s(r['category']),
        density: _d(r['density']),
        edible: _d(r['edible']),
        custom: true,
      );

  Future<List<Food>> searchFoods(String query, {int limit = 60}) async {
    final terms = normalize(query)
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return recentFoods();
    final where = terms.map((_) => 'search_text LIKE ?').join(' AND ');
    final args = terms.map((t) => '%$t%').toList();

    final custom = await _user.query('custom_food',
        where: where, whereArgs: args, orderBy: 'name', limit: 20);
    final base = await _nut.rawQuery(
      'SELECT * FROM food WHERE $where '
      'ORDER BY CASE WHEN name_es IS NULL THEN 1 ELSE 0 END, '
      'length(COALESCE(name_es, name_en)) LIMIT ?',
      [...args, limit],
    );
    return [
      ...custom.map(_customFood),
      ...base.map(_nutFood),
    ];
  }

  Future<List<Food>> recentFoods({int limit = 25}) async {
    final rows = await _user.rawQuery(
      'SELECT food_id, MAX(id) AS last FROM recipe_ingredient '
      'GROUP BY food_id ORDER BY last DESC LIMIT ?',
      [limit],
    );
    final ids = rows.map((r) => _i(r['food_id'])).toList();
    final foods = await foodsByIds(ids.toSet());
    return ids.where(foods.containsKey).map((id) => foods[id]!).toList();
  }

  Future<Map<int, Food>> foodsByIds(Set<int> ids) async {
    final out = <int, Food>{};
    final custom = ids.where((i) => i >= customFoodBaseId).toList();
    final base = ids.where((i) => i < customFoodBaseId).toList();
    for (final chunk in _chunks(base)) {
      final rows = await _nut.query('food',
          where: 'id IN (${_marks(chunk.length)})', whereArgs: chunk);
      for (final r in rows) {
        final f = _nutFood(r);
        out[f.id] = f;
      }
    }
    for (final chunk in _chunks(custom)) {
      final rows = await _user.query('custom_food',
          where: 'id IN (${_marks(chunk.length)})', whereArgs: chunk);
      for (final r in rows) {
        final f = _customFood(r);
        out[f.id] = f;
      }
    }
    return out;
  }

  Future<List<Portion>> portions(int foodId) async {
    final List<Map<String, Object?>> rows;
    if (foodId >= customFoodBaseId) {
      rows = await _user.query('custom_portion',
          where: 'food_id = ?', whereArgs: [foodId], orderBy: 'id');
    } else {
      rows = await _nut.query('food_portion',
          where: 'food_id = ?', whereArgs: [foodId], orderBy: 'id');
    }
    return rows.map((r) => Portion(_s(r['label']), _d(r['grams']))).toList();
  }

  Future<Map<int, Map<int, double>>> per100(Set<int> foodIds) async {
    final out = <int, Map<int, double>>{for (final id in foodIds) id: {}};
    final custom = foodIds.where((i) => i >= customFoodBaseId).toList();
    final base = foodIds.where((i) => i < customFoodBaseId).toList();
    for (final chunk in _chunks(base)) {
      final rows = await _nut.query('food_nutrient',
          where: 'food_id IN (${_marks(chunk.length)})', whereArgs: chunk);
      for (final r in rows) {
        out[_i(r['food_id'])]![_i(r['nutrient_id'])] = _d(r['per_100g']);
      }
    }
    for (final chunk in _chunks(custom)) {
      final rows = await _user.query('custom_food_nutrient',
          where: 'food_id IN (${_marks(chunk.length)})', whereArgs: chunk);
      for (final r in rows) {
        out[_i(r['food_id'])]![_i(r['nutrient_id'])] = _d(r['per_100g']);
      }
    }
    return out;
  }

  Future<List<Food>> customFoods() async {
    final rows = await _user.query('custom_food', orderBy: 'name');
    return rows.map(_customFood).toList();
  }

  /// Crea o actualiza un alimento propio. [values] = nutrientId -> por 100 g.
  Future<int> saveCustomFood({
    int? id,
    required String name,
    required String category,
    double density = 1.0,
    required Map<int, double> values,
    List<Portion> portions = const [],
  }) async {
    _dirty();
    return _user.transaction((txn) async {
      var foodId = id;
      if (foodId == null) {
        final r = await txn.rawQuery('SELECT MAX(id) AS m FROM custom_food');
        final max = _iN(r.first['m']) ?? (customFoodBaseId - 1);
        foodId = max < customFoodBaseId ? customFoodBaseId : max + 1;
      }
      await txn.insert(
        'custom_food',
        {
          'id': foodId,
          'name': name,
          'category': category,
          'density': density,
          'edible': 1.0,
          'search_text': normalize(name),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('custom_food_nutrient',
          where: 'food_id = ?', whereArgs: [foodId]);
      for (final e in values.entries) {
        await txn.insert('custom_food_nutrient',
            {'food_id': foodId, 'nutrient_id': e.key, 'per_100g': e.value});
      }
      await txn.delete('custom_portion', where: 'food_id = ?', whereArgs: [foodId]);
      for (final p in portions) {
        await txn.insert('custom_portion',
            {'food_id': foodId, 'label': p.label, 'grams': p.grams});
      }
      return foodId;
    });
  }

  Future<void> deleteCustomFood(int id) async {
    await _user.delete('custom_food', where: 'id = ?', whereArgs: [id]);
  }

  /// Agrega una porción casera a un alimento propio (las de la base son fijas).
  Future<void> addCustomPortion(int foodId, Portion p) async {
    await _user.insert('custom_portion',
        {'food_id': foodId, 'label': p.label, 'grams': p.grams});
  }

  // ---------------------------------------------------------------- recetas

  static String _category(Object? v) {
    final c = (v as String?) ?? '';
    return recipeCategories.contains(c) ? c : defaultRecipeCategory;
  }

  /// Recetas filtradas por texto (nombre, etiquetas, categoría) y categoría.
  Future<List<Recipe>> recipes({String query = '', String? category}) async {
    final rows = await _user.query('recipe', orderBy: 'name COLLATE NOCASE');
    final q = normalize(query.trim());
    final list = rows
        .map((r) => Recipe(
              id: _i(r['id']),
              name: _s(r['name']),
              servings: _d(r['servings']),
              prepMin: _iN(r['prep_min']),
              cookMin: _iN(r['cook_min']),
              instructions: _s(r['instructions']),
              tags: _s(r['tags']),
              category: _category(r['category']),
              photo: r['photo'] as String?,
            ))
        .toList();
    return list
        .where((r) => category == null || r.category == category)
        .where((r) =>
            q.isEmpty ||
            normalize('${r.name} ${r.tags} ${r.category}').contains(q))
        .toList();
  }

  Future<Recipe?> recipe(int id) async {
    final rows = await _user.query('recipe', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final ing = await _user.query('recipe_ingredient',
        where: 'recipe_id = ?', whereArgs: [id], orderBy: 'sort_order, id');
    return Recipe(
      id: id,
      name: _s(r['name']),
      servings: _d(r['servings']),
      prepMin: _iN(r['prep_min']),
      cookMin: _iN(r['cook_min']),
      instructions: _s(r['instructions']),
      tags: _s(r['tags']),
      category: _category(r['category']),
      photo: r['photo'] as String?,
      ingredients: ing
          .map((x) => RecipeIngredient(
                id: _i(x['id']),
                foodId: _i(x['food_id']),
                foodName: _s(x['food_name']),
                qty: _d(x['qty']),
                unit: _s(x['unit']),
                grams: _d(x['grams']),
                note: _s(x['note']),
              ))
          .toList(),
    );
  }

  Future<int> saveRecipe(Recipe r) async {
    _dirty();
    final now = DateTime.now().millisecondsSinceEpoch;
    return _user.transaction((txn) async {
      final values = <String, Object?>{
        'name': r.name,
        'servings': r.servings,
        'prep_min': r.prepMin,
        'cook_min': r.cookMin,
        'instructions': r.instructions,
        'tags': r.tags,
        'category': r.category,
        'updated_at': now,
      };
      int id;
      if (r.id == null) {
        values['created_at'] = now;
        id = await txn.insert('recipe', values);
      } else {
        id = r.id!;
        await txn.update('recipe', values, where: 'id = ?', whereArgs: [id]);
        await txn.delete('recipe_ingredient',
            where: 'recipe_id = ?', whereArgs: [id]);
      }
      var order = 0;
      for (final ing in r.ingredients) {
        await txn.insert('recipe_ingredient', {
          'recipe_id': id,
          'food_id': ing.foodId,
          'food_name': ing.foodName,
          'qty': ing.qty,
          'unit': ing.unit,
          'grams': ing.grams,
          'note': ing.note,
          'sort_order': order++,
        });
      }
      return id;
    });
  }

  Future<void> deleteRecipe(int id) async {
    _dirty();
    final rows = await _user.query('recipe',
        columns: ['photo'], where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) await PhotoStore.delete(rows.first['photo'] as String?);
    await _user.delete('recipe', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> duplicateRecipe(int id) async {
    final r = await recipe(id);
    if (r == null) throw StateError('Receta inexistente');
    r.id = null;
    r.name = '${r.name} (copia)';
    for (final i in r.ingredients) {
      i.id = null;
    }
    final photo = r.photo;
    final newId = await saveRecipe(r);
    if (photo != null) {
      final bytes = await PhotoStore.read(photo);
      if (bytes != null) await setRecipePhoto(newId, bytes);
    }
    return newId;
  }

  /// Guarda la foto de una receta (reemplaza la anterior). [bytes] null = quitar.
  Future<String?> setRecipePhoto(int recipeId, List<int>? bytes) async {
    final rows = await _user.query('recipe',
        columns: ['photo'], where: 'id = ?', whereArgs: [recipeId]);
    if (rows.isEmpty) return null;
    final old = rows.first['photo'] as String?;
    final name = bytes == null ? null : await PhotoStore.save(recipeId, bytes);
    await _user.update('recipe', {'photo': name},
        where: 'id = ?', whereArgs: [recipeId]);
    if (old != null && old != name) await PhotoStore.delete(old);
    return name;
  }

  // ---------------------------------------------------------------- nutrición

  /// Totales de la receta completa (no por porción).
  Future<NutritionTotals> recipeTotals(Recipe r) async {
    final ns = await nutrients();
    final ids = r.ingredients.map((e) => e.foodId).toSet();
    final values = await per100(ids);
    final foods = await foodsByIds(ids);
    final items = r.ingredients
        .map((e) => IngredientData(
              grams: e.grams,
              edible: foods[e.foodId]?.edible ?? 1.0,
              per100g: values[e.foodId] ?? const {},
            ))
        .toList();
    return sumIngredients(items, ns.map((n) => n.id));
  }

  /// kcal, proteínas, carbohidratos y grasas por porción de todas las
  /// recetas, calculado en bloque para la lista (se guarda en memoria).
  Future<Map<int, RecipeSummary>> recipeSummaries() async {
    if (_summaries != null) return _summaries!;
    final codes = <String, int>{};
    for (final n in await nutrients()) {
      codes[n.code] = n.id;
    }
    final kcalId = codes['energy_kcal'];
    final protId = codes['protein_g'];
    final carbId = codes['carbs_g'];
    final fatId = codes['fat_g'];
    final recipes = await _user.query('recipe', columns: ['id', 'servings']);
    final rows = await _user.query('recipe_ingredient',
        columns: ['recipe_id', 'food_id', 'grams']);
    final ids = rows.map((r) => _i(r['food_id'])).toSet();
    final values = await per100(ids);
    final foods = await foodsByIds(ids);
    final acc = <int, List<double>>{};
    for (final r in rows) {
      final fid = _i(r['food_id']);
      final v = values[fid];
      if (v == null) continue;
      final g = _d(r['grams']) * (foods[fid]?.edible ?? 1.0) / 100.0;
      final a = acc.putIfAbsent(_i(r['recipe_id']), () => [0, 0, 0, 0]);
      a[0] += g * (v[kcalId] ?? 0);
      a[1] += g * (v[protId] ?? 0);
      a[2] += g * (v[carbId] ?? 0);
      a[3] += g * (v[fatId] ?? 0);
    }
    final out = <int, RecipeSummary>{};
    for (final r in recipes) {
      final id = _i(r['id']);
      final serv = _d(r['servings']);
      final a = acc[id] ?? [0, 0, 0, 0];
      final k = serv > 0 ? serv : 1.0;
      out[id] = RecipeSummary(a[0] / k, a[1] / k, a[2] / k, a[3] / k);
    }
    return _summaries = out;
  }

  /// kcal aportadas por cada ingrediente de la receta completa.
  Future<List<double>> ingredientKcal(Recipe r) async {
    final energy = await nutrientByCode('energy_kcal');
    if (energy == null) return r.ingredients.map((_) => 0.0).toList();
    final ids = r.ingredients.map((e) => e.foodId).toSet();
    final values = await per100(ids);
    final foods = await foodsByIds(ids);
    return r.ingredients.map((e) {
      final v = values[e.foodId]?[energy.id] ?? 0.0;
      return e.grams * (foods[e.foodId]?.edible ?? 1.0) * v / 100.0;
    }).toList();
  }

  /// Totales por día (7 elementos, lunes a domingo) de una semana del plan.
  Future<List<NutritionTotals>> weekDayTotals(String weekStart) async {
    final entries = await planEntries(weekStart);
    final cache = <int, NutritionTotals>{};
    final days = List<NutritionTotals>.filled(7, NutritionTotals.empty);
    for (final e in entries) {
      var perServ = cache[e.recipeId];
      if (perServ == null) {
        final r = await recipe(e.recipeId);
        if (r == null || r.servings <= 0) continue;
        perServ = perServing(await recipeTotals(r), r.servings);
        cache[e.recipeId] = perServ;
      }
      days[e.day] = days[e.day].plus(perServ.scaled(e.servings));
    }
    return days;
  }

  // ---------------------------------------------------------------- plan

  Future<List<PlanEntry>> planEntries(String weekStart) async {
    final rows = await _user.rawQuery(
      'SELECT p.*, r.name AS recipe_name FROM plan_entry p '
      'JOIN recipe r ON r.id = p.recipe_id WHERE p.week_start = ? '
      'ORDER BY p.day, p.id',
      [weekStart],
    );
    return rows
        .map((r) => PlanEntry(
              id: _i(r['id']),
              weekStart: _s(r['week_start']),
              day: _i(r['day']),
              slot: _s(r['slot']),
              recipeId: _i(r['recipe_id']),
              recipeName: _s(r['recipe_name']),
              servings: _d(r['servings']),
            ))
        .toList();
  }

  Future<void> addPlanEntry(PlanEntry e) async {
    await _user.insert('plan_entry', {
      'week_start': e.weekStart,
      'day': e.day,
      'slot': e.slot,
      'recipe_id': e.recipeId,
      'servings': e.servings,
    });
  }

  Future<void> updatePlanServings(int id, double servings) async {
    await _user.update('plan_entry', {'servings': servings},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePlanEntry(int id) async {
    await _user.delete('plan_entry', where: 'id = ?', whereArgs: [id]);
  }

  /// Copia la semana anterior en esta. Devuelve cuántas entradas copió.
  Future<int> copyPreviousWeek(String weekStart) async {
    final prev = shiftWeek(weekStart, -1);
    final entries = await planEntries(prev);
    await _user.transaction((txn) async {
      for (final e in entries) {
        await txn.insert('plan_entry', {
          'week_start': weekStart,
          'day': e.day,
          'slot': e.slot,
          'recipe_id': e.recipeId,
          'servings': e.servings,
        });
      }
    });
    return entries.length;
  }

  /// Guarda un plan armado automáticamente. Con [replace] primero vacía
  /// esos días.
  Future<void> saveAutoPlan(String weekStart, List<int> days,
      List<({int day, String slot, int recipeId, double servings})> meals,
      {bool replace = true}) async {
    await _user.transaction((txn) async {
      if (replace) {
        for (final d in days) {
          await txn.delete('plan_entry',
              where: 'week_start = ? AND day = ?', whereArgs: [weekStart, d]);
        }
      }
      for (final m in meals) {
        await txn.insert('plan_entry', {
          'week_start': weekStart,
          'day': m.day,
          'slot': m.slot,
          'recipe_id': m.recipeId,
          'servings': m.servings,
        });
      }
    });
  }

  Future<void> clearWeek(String weekStart) async {
    await _user.delete('plan_entry',
        where: 'week_start = ?', whereArgs: [weekStart]);
  }

  // ---------------------------------------------------------------- compras

  Future<List<ShoppingItem>> shoppingList(String weekStart) async {
    final entries = await planEntries(weekStart);
    final recipesById = <int, Recipe>{};
    final lines = <NeedLine>[];
    final allIds = <int>{};
    for (final e in entries) {
      final r = recipesById[e.recipeId] ?? await recipe(e.recipeId);
      if (r == null || r.servings <= 0) continue;
      recipesById[e.recipeId] = r;
      allIds.addAll(r.ingredients.map((i) => i.foodId));
    }
    final foods = await foodsByIds(allIds);
    for (final e in entries) {
      final r = recipesById[e.recipeId];
      if (r == null) continue;
      final factor = e.servings / r.servings;
      for (final i in r.ingredients) {
        lines.add(NeedLine(
          i.foodId,
          i.foodName,
          foods[i.foodId]?.category ?? 'Almacén',
          i.grams * factor,
        ));
      }
    }
    return buildShoppingList(lines, pantry: await pantryMap());
  }

  Future<Map<int, double>> pantryMap() async {
    final rows = await _user.query('pantry_item');
    return {for (final r in rows) _i(r['food_id']): _d(r['grams'])};
  }

  Future<List<ShoppingItem>> pantryItems() async {
    final rows = await _user.query('pantry_item', orderBy: 'category, food_name');
    return rows
        .map((r) => ShoppingItem(_i(r['food_id']), _s(r['food_name']),
            _s(r['category']), _d(r['grams'])))
        .toList();
  }

  Future<void> setPantry(Food f, double grams) async {
    if (grams <= 0) {
      await _user.delete('pantry_item', where: 'food_id = ?', whereArgs: [f.id]);
      return;
    }
    await _user.insert(
      'pantry_item',
      {'food_id': f.id, 'food_name': f.name, 'category': f.category, 'grams': grams},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removePantry(int foodId) async {
    await _user.delete('pantry_item', where: 'food_id = ?', whereArgs: [foodId]);
  }

  // ---------------------------------------------------------------- metas

  Future<Map<String, Target>> targets() async {
    final out = <String, Target>{
      for (final e in defaultTargets.entries)
        e.key: Target(e.value.value, e.value.upperLimit),
    };
    final rows = await _user.query('nutrient_target');
    for (final r in rows) {
      out[_s(r['code'])] = Target(_d(r['daily_target']), _i(r['is_upper']) == 1);
    }
    return out;
  }

  Future<void> setTarget(String code, double value, bool upper) async {
    await _user.insert(
      'nutrient_target',
      {'code': code, 'daily_target': value, 'is_upper': upper ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> resetTargets() async {
    await _user.delete('nutrient_target');
  }

  // ---------------------------------------------------------------- ajustes

  Future<String?> setting(String key) async {
    final rows =
        await _user.query('setting', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : _s(rows.first['value']);
  }

  Future<void> setSetting(String key, String value) async {
    await _user.insert('setting', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------- backup

  static const _backupTables = [
    'custom_food',
    'custom_food_nutrient',
    'custom_portion',
    'recipe',
    'recipe_ingredient',
    'plan_entry',
    'nutrient_target',
    'pantry_item',
    'setting',
  ];

  Future<String> exportJson() async {
    final data = <String, Object?>{
      'app': 'recetas_app',
      'format': 1,
      'exported_at': DateTime.now().toIso8601String(),
    };
    for (final t in _backupTables) {
      data[t] = await _user.query(t);
    }
    return jsonEncode(data);
  }

  /// Reemplaza todos los datos del usuario por los del respaldo.
  Future<void> importJson(String json) async {
    _dirty();
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (data['app'] != 'recetas_app') {
      throw const FormatException('No es un respaldo de esta app');
    }
    await _user.transaction((txn) async {
      for (final t in _backupTables.reversed) {
        await txn.delete(t);
      }
      for (final t in _backupTables) {
        final rows = (data[t] as List?) ?? const [];
        for (final r in rows) {
          await txn.insert(t, Map<String, Object?>.from(r as Map));
        }
      }
    });
  }

  /// Agrega las recetas de un recetario (.json). No borra nada: las recetas
  /// cuyo nombre ya existe se saltean y los alimentos propios se reutilizan
  /// por nombre. Las fotos del recetario se guardan en las recetas nuevas y
  /// también en las existentes que todavía no tengan foto.
  /// Devuelve (agregadas, salteadas, fotos guardadas).
  Future<(int, int, int)> importRecipePack(String json) async {
    _dirty();
    final pack = parseRecipePack(json);
    final codeToId = {for (final n in await nutrients()) n.code: n.id};
    var added = 0;
    var skipped = 0;
    var photos = 0;
    await _user.transaction((txn) async {
      // alimentos propios del paquete
      final keyToId = <String, int>{};
      final existing = await txn.query('custom_food', columns: ['id', 'name']);
      final byName = {
        for (final r in existing) recipeNameKey(_s(r['name'])): _i(r['id'])
      };
      final maxRow = await txn.rawQuery('SELECT MAX(id) AS m FROM custom_food');
      var next = (_iN(maxRow.first['m']) ?? (customFoodBaseId - 1)) + 1;
      if (next < customFoodBaseId) next = customFoodBaseId;
      for (final f in pack.foods) {
        final found = byName[recipeNameKey(f.name)];
        if (found != null) {
          keyToId[f.key] = found;
          continue;
        }
        final id = next++;
        await txn.insert('custom_food', {
          'id': id,
          'name': f.name,
          'category': f.category,
          'density': f.density > 0 ? f.density : 1.0,
          'edible': 1.0,
          'search_text': normalize(f.name),
        });
        for (final e in f.nutrients.entries) {
          final nid = codeToId[e.key];
          if (nid == null) continue;
          await txn.insert('custom_food_nutrient',
              {'food_id': id, 'nutrient_id': nid, 'per_100g': e.value});
        }
        keyToId[f.key] = id;
        byName[recipeNameKey(f.name)] = id;
      }
      // recetas
      final existingRecipes =
          await txn.query('recipe', columns: ['id', 'name', 'photo']);
      final names = existingRecipes.map((r) => recipeNameKey(_s(r['name']))).toSet();
      final withoutPhoto = {
        for (final r in existingRecipes)
          if (r['photo'] == null) recipeNameKey(_s(r['name'])): _i(r['id'])
      };
      Future<void> attach(int rid, String b64) async {
        try {
          final name = await PhotoStore.save(rid, base64Decode(b64));
          await txn.update('recipe', {'photo': name},
              where: 'id = ?', whereArgs: [rid]);
          photos++;
        } catch (_) {
          // una foto dañada no frena la importación
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      for (final pr in pack.recipes) {
        final r = pr.recipe;
        final key = recipeNameKey(r.name);
        if (!names.add(key)) {
          skipped++;
          final rid = withoutPhoto.remove(key);
          if (rid != null && pr.image != null) await attach(rid, pr.image!);
          continue;
        }
        final rid = await txn.insert('recipe', {
          'name': r.name,
          'servings': r.servings,
          'prep_min': r.prepMin,
          'cook_min': r.cookMin,
          'instructions': r.instructions,
          'tags': r.tags,
          'category': r.category,
          'created_at': now,
          'updated_at': now,
        });
        var order = 0;
        for (final i in pr.ingredients) {
          final fid = i.foodId ?? keyToId[i.foodKey];
          if (fid == null) continue;
          await txn.insert('recipe_ingredient', {
            'recipe_id': rid,
            'food_id': fid,
            'food_name': i.foodName,
            'qty': i.qty,
            'unit': i.unit,
            'grams': i.grams,
            'note': i.note,
            'sort_order': order++,
          });
        }
        if (pr.image != null) await attach(rid, pr.image!);
        added++;
      }
    });
    return (added, skipped, photos);
  }

  /// Carga el plan de un recetario desde el día [start]. Si [replace] es
  /// true, antes borra lo que haya en esos días. Devuelve (cargadas, faltantes):
  /// las faltantes son comidas cuya receta no existe en la app.
  Future<(int, int)> importPackPlan(RecipePack pack, DateTime start,
      {bool replace = true}) async {
    final ids = <String, int>{};
    for (final r in await _user.query('recipe', columns: ['id', 'name'])) {
      ids.putIfAbsent(recipeNameKey(_s(r['name'])), () => _i(r['id']));
    }
    var added = 0;
    var missing = 0;
    await _user.transaction((txn) async {
      if (replace) {
        for (var d = 0; d < pack.planDays; d++) {
          final at = planSlotDate(start, d);
          await txn.delete('plan_entry',
              where: 'week_start = ? AND day = ?',
              whereArgs: [at.weekStart, at.day]);
        }
      }
      for (final e in pack.plan) {
        final id = ids[recipeNameKey(e.recipe)];
        if (id == null) {
          missing++;
          continue;
        }
        final at = planSlotDate(start, e.day);
        await txn.insert('plan_entry', {
          'week_start': at.weekStart,
          'day': at.day,
          'slot': e.slot,
          'recipe_id': id,
          'servings': e.servings,
        });
        added++;
      }
    });
    return (added, missing);
  }

  // ---------------------------------------------------------------- helpers

  static String _marks(int n) => List.filled(n, '?').join(',');

  static Iterable<List<int>> _chunks(List<int> ids, [int size = 500]) sync* {
    for (var i = 0; i < ids.length; i += size) {
      yield ids.sublist(i, i + size > ids.length ? ids.length : i + size);
    }
  }
}
