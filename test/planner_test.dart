import 'package:flutter_test/flutter_test.dart';
import 'package:recetas_app/domain/meal_planner.dart';

void main() {
  // recetario de prueba con valores por porción realistas
  final pool = <PlanCandidate>[
    for (var i = 0; i < 12; i++)
      PlanCandidate(i, 'Desayuno $i', 'Desayuno', 250 + i * 20.0, 10 + i * 1.5),
    for (var i = 0; i < 30; i++)
      PlanCandidate(100 + i, 'Plato $i', i.isEven ? 'Principal' : 'Ensalada',
          300 + i * 15.0, 35 + i * 1.5),
    for (var i = 0; i < 12; i++)
      PlanCandidate(200 + i, 'Snack $i', 'Merienda / snack', 150 + i * 10.0, 5.0 + i),
    const PlanCandidate(999, 'Sal', 'Salsa', 5, 0),
  ];
  const cfg = PlannerConfig(
    days: [0, 1, 2, 3, 4, 5, 6],
    slots: ['desayuno', 'almuerzo', 'merienda', 'cena'],
    kcal: 2000,
    protein: 140,
    seed: 7,
  );

  test('cada día cumple kcal (±5 %) y proteína (≥95 %)', () {
    final plan = planWeek(pool, cfg);
    expect(plan.length, 28);
    for (var d = 0; d < 7; d++) {
      final (k, p) = dayTotals(plan, d);
      expect((k - 2000).abs() / 2000, lessThan(0.05), reason: 'día $d: $k kcal');
      expect(p, greaterThan(140 * 0.95), reason: 'día $d: $p g');
    }
  });

  test('cada comida usa la categoría que corresponde y porciones válidas', () {
    final plan = planWeek(pool, cfg);
    for (final m in plan) {
      expect(slotCategories[m.slot]![0], contains(m.recipe.category));
      expect(m.servings, inInclusiveRange(0.5, 2.0));
      expect((m.servings / 0.25) % 1, 0);
    }
  });

  test('no repite recetas en el día y casi no en la semana', () {
    final plan = planWeek(pool, cfg);
    for (var d = 0; d < 7; d++) {
      final ids = plan.where((m) => m.day == d).map((m) => m.recipe.id).toList();
      expect(ids.toSet().length, ids.length);
    }
    final lunchDinner = plan
        .where((m) => m.slot == 'almuerzo' || m.slot == 'cena')
        .map((m) => m.recipe.id)
        .toList();
    expect(lunchDinner.toSet().length, greaterThanOrEqualTo(12));
  });

  test('distinta semilla da otro plan; la misma, el mismo', () {
    String key(List<PlannedMeal> p) => p.map((m) => m.recipe.id).join(',');
    expect(key(planWeek(pool, cfg)), key(planWeek(pool, cfg)));
    const other = PlannerConfig(
        days: [0, 1, 2, 3, 4, 5, 6],
        slots: ['desayuno', 'almuerzo', 'merienda', 'cena'],
        kcal: 2000,
        protein: 140,
        seed: 8);
    expect(key(planWeek(pool, other)), isNot(key(planWeek(pool, cfg))));
  });

  test('cambiar una comida usa otra receta y mantiene el día en meta', () {
    final plan = planWeek(pool, cfg);
    final i = plan.indexWhere((m) => m.slot == 'cena');
    final before = plan[i].recipe.id;
    rerollMeal(plan, i, pool, cfg, 123);
    expect(plan[i].recipe.id, isNot(before));
    final (k, _) = dayTotals(plan, plan[i].day);
    expect((k - 2000).abs() / 2000, lessThan(0.06));
  });

  test('sin recetas para una comida, la saltea', () {
    final plan = planWeek(pool.where((c) => c.category != 'Desayuno').toList(),
        const PlannerConfig(days: [0], slots: ['desayuno', 'cena'], kcal: 1500, protein: 80));
    // el desayuno toma recetas de la lista secundaria (snacks)
    expect(plan.map((m) => m.slot), containsAll(['desayuno', 'cena']));
  });
}
