/// Motor de cálculo nutricional. Trabaja en gramos y no redondea.

/// Datos de un ingrediente necesarios para el cálculo.
class IngredientData {
  final double grams;
  final double edible;
  final Map<int, double> per100g; // nutrientId -> valor por 100 g

  const IngredientData({
    required this.grams,
    this.edible = 1.0,
    required this.per100g,
  });
}

/// Totales de nutrientes con control de datos faltantes.
class NutritionTotals {
  /// nutrientId -> cantidad total
  final Map<int, double> values;

  /// nutrientId -> cantidad de ingredientes sin dato para ese nutriente
  final Map<int, int> missing;

  /// cantidad de ingredientes considerados
  final int count;

  const NutritionTotals(this.values, this.missing, this.count);

  static const empty = NutritionTotals({}, {}, 0);

  double value(int nutrientId) => values[nutrientId] ?? 0.0;

  /// Fracción (0..1) de ingredientes sin dato para el nutriente.
  double missingShare(int nutrientId) =>
      count == 0 ? 0.0 : (missing[nutrientId] ?? 0) / count;

  NutritionTotals scaled(double factor) => NutritionTotals(
        values.map((k, v) => MapEntry(k, v * factor)),
        missing,
        count,
      );

  NutritionTotals plus(NutritionTotals other) {
    final v = Map<int, double>.from(values);
    other.values.forEach((k, x) => v[k] = (v[k] ?? 0) + x);
    final m = Map<int, int>.from(missing);
    other.missing.forEach((k, x) => m[k] = (m[k] ?? 0) + x);
    return NutritionTotals(v, m, count + other.count);
  }
}

/// Suma de nutrientes de una lista de ingredientes.
///
/// N = sum(g * f * v / 100)
NutritionTotals sumIngredients(
  List<IngredientData> items,
  Iterable<int> nutrientIds,
) {
  final values = <int, double>{};
  final missing = <int, int>{};
  for (final id in nutrientIds) {
    values[id] = 0.0;
    missing[id] = 0;
  }
  for (final it in items) {
    for (final id in nutrientIds) {
      final v = it.per100g[id];
      if (v == null) {
        missing[id] = (missing[id] ?? 0) + 1;
      } else {
        values[id] = (values[id] ?? 0) + it.grams * it.edible * v / 100.0;
      }
    }
  }
  return NutritionTotals(values, missing, items.length);
}

/// Nutrientes por porción de una receta.
NutritionTotals perServing(NutritionTotals recipeTotal, double servings) {
  if (servings <= 0) {
    throw ArgumentError.value(servings, 'servings', 'debe ser mayor a cero');
  }
  return recipeTotal.scaled(1.0 / servings);
}

/// Factor de escalado de una receta.
double scaleFactor(double baseServings, double targetServings) {
  if (baseServings <= 0) {
    throw ArgumentError.value(baseServings, 'baseServings', 'debe ser mayor a cero');
  }
  return targetServings / baseServings;
}

/// Porcentaje del valor diario.
double percentDv(double value, double target) =>
    target <= 0 ? 0.0 : value / target * 100.0;
