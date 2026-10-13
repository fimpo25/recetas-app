/// Metas diarias y cálculo de requerimiento energético.

class TargetDefault {
  final double value;
  final bool upperLimit;
  const TargetDefault(this.value, {this.upperLimit = false});
}

/// Valores de referencia para una dieta de 2000 kcal. Editables en Ajustes.
const Map<String, TargetDefault> defaultTargets = {
  'energy_kcal': TargetDefault(2000),
  'protein_g': TargetDefault(75),
  'fat_g': TargetDefault(55),
  'sat_fat_g': TargetDefault(22, upperLimit: true),
  'carbs_g': TargetDefault(300),
  'fiber_g': TargetDefault(25),
  'sugars_g': TargetDefault(50, upperLimit: true),
  'sodium_mg': TargetDefault(2000, upperLimit: true),
  'potassium_mg': TargetDefault(3500),
  'calcium_mg': TargetDefault(1000),
  'iron_mg': TargetDefault(14),
  'magnesium_mg': TargetDefault(260),
  'zinc_mg': TargetDefault(7),
  'vit_a_ug': TargetDefault(600),
  'vit_c_mg': TargetDefault(45),
  'vit_d_ug': TargetDefault(15),
  'vit_b12_ug': TargetDefault(2.4),
  'folate_ug': TargetDefault(400),
};

const Map<String, double> activityFactors = {
  'Sedentario': 1.2,
  'Ligero (1-3 días/sem)': 1.375,
  'Moderado (3-5 días/sem)': 1.55,
  'Intenso (6-7 días/sem)': 1.725,
  'Muy intenso': 1.9,
};

/// Tasa metabólica basal, Mifflin-St Jeor.
double mifflinStJeor({
  required bool male,
  required double weightKg,
  required double heightCm,
  required int age,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return male ? base + 5 : base - 161;
}

/// Energía diaria objetivo.
double dailyEnergy({
  required bool male,
  required double weightKg,
  required double heightCm,
  required int age,
  required double activityFactor,
}) =>
    mifflinStJeor(male: male, weightKg: weightKg, heightCm: heightCm, age: age) *
    activityFactor;

/// Estado de un nutriente frente a su meta: 0 ok, 1 alerta.
bool isAlert(double percent, bool upperLimit) =>
    upperLimit ? percent > 100.0 : percent < 70.0;
