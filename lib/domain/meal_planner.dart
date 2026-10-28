/// Armado automático del plan semanal.
///
/// Elige, para cada día y comida, una receta y una cantidad de porciones de
/// modo que el día sume las kcal pedidas y llegue a la proteína pedida, con
/// variedad (no repite recetas en la semana mientras haya opciones).
library;

import 'dart:math';

/// Receta candidata con sus valores por porción.
class PlanCandidate {
  final int id;
  final String name;
  final String category;
  final double kcal;
  final double protein;
  const PlanCandidate(this.id, this.name, this.category, this.kcal, this.protein);
}

class PlannerConfig {
  final List<int> days; // 0 = lunes
  final List<String> slots; // en el orden de mealSlots
  final double kcal; // por día
  final double protein; // g por día
  final int seed;
  final double minPortion;
  final double maxPortion;
  final double step;

  const PlannerConfig({
    required this.days,
    required this.slots,
    required this.kcal,
    required this.protein,
    this.seed = 1,
    this.minPortion = 0.5,
    this.maxPortion = 2.0,
    this.step = 0.25,
  });
}

class PlannedMeal {
  final int day;
  final String slot;
  final PlanCandidate recipe;
  double servings;
  PlannedMeal(this.day, this.slot, this.recipe, this.servings);

  double get kcal => recipe.kcal * servings;
  double get protein => recipe.protein * servings;
}

/// Categorías que se usan en cada comida (la primera lista es la preferida;
/// la segunda se suma solo si hay pocas recetas).
const Map<String, List<List<String>>> slotCategories = {
  'desayuno': [
    ['Desayuno'],
    ['Merienda / snack', 'Panadería', 'Bebida'],
  ],
  'almuerzo': [
    ['Principal', 'Ensalada'],
    ['Sopa', 'Entrada'],
  ],
  'merienda': [
    ['Merienda / snack', 'Desayuno', 'Postre'],
    ['Bebida', 'Panadería'],
  ],
  'cena': [
    ['Principal', 'Ensalada'],
    ['Sopa', 'Entrada'],
  ],
  'colacion': [
    ['Merienda / snack', 'Bebida', 'Postre'],
    ['Desayuno'],
  ],
};

/// Parte de las kcal y de la proteína del día que va a cada comida.
const Map<String, double> _kcalShare = {
  'desayuno': 0.22,
  'almuerzo': 0.32,
  'merienda': 0.14,
  'cena': 0.30,
  'colacion': 0.08,
};
const Map<String, double> _protShare = {
  'desayuno': 0.20,
  'almuerzo': 0.34,
  'merienda': 0.10,
  'cena': 0.34,
  'colacion': 0.06,
};

Map<String, double> _shares(List<String> slots, Map<String, double> base) {
  final total = slots.fold<double>(0, (a, s) => a + (base[s] ?? 0.1));
  return {for (final s in slots) s: (base[s] ?? 0.1) / total};
}

/// Recetas usables en cada comida.
Map<String, List<PlanCandidate>> slotPools(
    List<PlanCandidate> all, List<String> slots) {
  final ok = all.where((c) => c.kcal >= 60 && c.kcal <= 1400).toList();
  final out = <String, List<PlanCandidate>>{};
  for (final s in slots) {
    final cats = slotCategories[s] ?? const [<String>[], <String>[]];
    final pool = ok.where((c) => cats[0].contains(c.category)).toList();
    if (pool.length < 8) {
      pool.addAll(ok.where((c) => cats[1].contains(c.category)));
    }
    out[s] = pool;
  }
  return out;
}

double _round(double v, PlannerConfig c) {
  final r = (v / c.step).round() * c.step;
  return r.clamp(c.minPortion, c.maxPortion).toDouble();
}

/// Qué tan lejos está un día de las metas (0 = perfecto).
double dayError(Iterable<PlannedMeal> meals, PlannerConfig c) {
  var k = 0.0, p = 0.0;
  for (final m in meals) {
    k += m.kcal;
    p += m.protein;
  }
  final kErr = (k - c.kcal).abs() / c.kcal;
  final pShort = c.protein > 0 ? max(0.0, c.protein - p) / c.protein : 0.0;
  final pOver = c.protein > 0 ? max(0.0, p - 1.35 * c.protein) / c.protein : 0.0;
  return kErr + 2.0 * pShort + 0.5 * pOver;
}

/// Ajusta porciones del día, de a un paso, mientras mejore el error.
void balanceDay(List<PlannedMeal> meals, PlannerConfig c) {
  for (var it = 0; it < 40; it++) {
    final base = dayError(meals, c);
    PlannedMeal? best;
    var bestDelta = 0.0, bestErr = base;
    for (final m in meals) {
      for (final d in [c.step, -c.step]) {
        final ns = m.servings + d;
        if (ns < c.minPortion - 1e-9 || ns > c.maxPortion + 1e-9) continue;
        m.servings = ns;
        final e = dayError(meals, c) + (ns - 1).abs() * 0.01;
        m.servings = ns - d;
        if (e < bestErr - 1e-6) {
          bestErr = e;
          best = m;
          bestDelta = d;
        }
      }
    }
    if (best == null) break;
    best.servings += bestDelta;
  }
}

PlannedMeal? _pickMeal({
  required int day,
  required String slot,
  required List<PlanCandidate> pool,
  required double kcalTarget,
  required double protTarget,
  required PlannerConfig cfg,
  required Map<int, int> lastUsed, // receta -> último día usada
  required Set<int> usedToday,
  required Set<int> exclude,
  required Random rnd,
}) {
  final scored = <(double, PlanCandidate, double)>[];
  for (final c in pool) {
    if (usedToday.contains(c.id) || exclude.contains(c.id)) continue;
    final m = _round(kcalTarget / c.kcal, cfg);
    final k = c.kcal * m, p = c.protein * m;
    var cost = (k - kcalTarget).abs() / kcalTarget;
    if (protTarget > 0) {
      cost += 1.5 * max(0.0, protTarget - p) / protTarget;
      cost += 0.3 * max(0.0, p - 1.8 * protTarget) / protTarget;
    }
    cost += (m - 1).abs() * 0.12; // preferir porciones enteras
    final last = lastUsed[c.id];
    if (last != null) cost += (day - last).abs() <= 2 ? 3.0 : 1.0;
    scored.add((cost, c, m));
  }
  if (scored.isEmpty) return null;
  scored.sort((a, b) => a.$1.compareTo(b.$1));
  // variedad: elegir al azar entre las mejores, con más peso a las primeras
  final top = scored.take(6).toList();
  final weights = [for (var i = 0; i < top.length; i++) 1.0 / (i + 1)];
  var r = rnd.nextDouble() * weights.reduce((a, b) => a + b);
  var idx = 0;
  while (idx < top.length - 1 && r > weights[idx]) {
    r -= weights[idx];
    idx++;
  }
  final pick = top[idx];
  return PlannedMeal(day, slot, pick.$2, pick.$3);
}

/// Arma el plan de los días pedidos.
List<PlannedMeal> planWeek(List<PlanCandidate> all, PlannerConfig cfg) {
  final rnd = Random(cfg.seed);
  final pools = slotPools(all, cfg.slots);
  final ks = _shares(cfg.slots, _kcalShare);
  final ps = _shares(cfg.slots, _protShare);
  final lastUsed = <int, int>{};
  final out = <PlannedMeal>[];
  for (final day in cfg.days) {
    final today = <PlannedMeal>[];
    final usedToday = <int>{};
    for (final slot in cfg.slots) {
      final m = _pickMeal(
        day: day,
        slot: slot,
        pool: pools[slot] ?? const [],
        kcalTarget: cfg.kcal * ks[slot]!,
        protTarget: cfg.protein * ps[slot]!,
        cfg: cfg,
        lastUsed: lastUsed,
        usedToday: usedToday,
        exclude: const {},
        rnd: rnd,
      );
      if (m == null) continue;
      today.add(m);
      usedToday.add(m.recipe.id);
      lastUsed[m.recipe.id] = day;
    }
    balanceDay(today, cfg);
    out.addAll(today);
  }
  return out;
}

/// Cambia una comida del plan por otra receta y reequilibra ese día.
void rerollMeal(List<PlannedMeal> plan, int index, List<PlanCandidate> all,
    PlannerConfig cfg, int seed) {
  final old = plan[index];
  final pools = slotPools(all, cfg.slots);
  final ks = _shares(cfg.slots, _kcalShare);
  final ps = _shares(cfg.slots, _protShare);
  final lastUsed = <int, int>{};
  for (final m in plan) {
    if (!identical(m, old)) lastUsed[m.recipe.id] = m.day;
  }
  final today = plan.where((m) => m.day == old.day && !identical(m, old));
  final m = _pickMeal(
    day: old.day,
    slot: old.slot,
    pool: pools[old.slot] ?? const [],
    kcalTarget: cfg.kcal * (ks[old.slot] ?? 0.25),
    protTarget: cfg.protein * (ps[old.slot] ?? 0.25),
    cfg: cfg,
    lastUsed: lastUsed,
    usedToday: today.map((e) => e.recipe.id).toSet(),
    exclude: {old.recipe.id},
    rnd: Random(seed),
  );
  if (m == null) return;
  plan[index] = m;
  balanceDay(plan.where((e) => e.day == old.day).toList(), cfg);
}

/// Totales (kcal, proteína) de un día del plan.
(double, double) dayTotals(Iterable<PlannedMeal> plan, int day) {
  var k = 0.0, p = 0.0;
  for (final m in plan.where((m) => m.day == day)) {
    k += m.kcal;
    p += m.protein;
  }
  return (k, p);
}
