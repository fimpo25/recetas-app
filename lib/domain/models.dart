/// Modelos de datos de la app. Sin dependencias de Flutter.

class Nutrient {
  final int id;
  final String code;
  final String nameEs;
  final String unit;
  final String kind; // macro | micro
  final int order;

  const Nutrient({
    required this.id,
    required this.code,
    required this.nameEs,
    required this.unit,
    required this.kind,
    required this.order,
  });
}

class Food {
  final int id;
  final String name;
  final String? nameEn;
  final String category;
  final double density; // g/ml
  final double edible; // fraccion comestible 0..1
  final bool custom;

  const Food({
    required this.id,
    required this.name,
    this.nameEn,
    required this.category,
    this.density = 1.0,
    this.edible = 1.0,
    this.custom = false,
  });
}

class Portion {
  final String label;
  final double grams;
  const Portion(this.label, this.grams);
}

class RecipeIngredient {
  int? id;
  int foodId;
  String foodName;
  double qty;
  String unit;
  double grams;
  String note;

  RecipeIngredient({
    this.id,
    required this.foodId,
    required this.foodName,
    required this.qty,
    required this.unit,
    required this.grams,
    this.note = '',
  });

  Map<String, Object?> toJson() => {
        'food_id': foodId,
        'food_name': foodName,
        'qty': qty,
        'unit': unit,
        'grams': grams,
        'note': note,
      };

  static RecipeIngredient fromJson(Map<String, dynamic> j) => RecipeIngredient(
        foodId: (j['food_id'] as num).toInt(),
        foodName: j['food_name'] as String,
        qty: (j['qty'] as num).toDouble(),
        unit: j['unit'] as String,
        grams: (j['grams'] as num).toDouble(),
        note: (j['note'] as String?) ?? '',
      );
}

class Recipe {
  int? id;
  String name;
  double servings;
  int? prepMin;
  int? cookMin;
  String instructions;
  String tags;
  String category;
  List<RecipeIngredient> ingredients;

  Recipe({
    this.id,
    required this.name,
    required this.servings,
    this.prepMin,
    this.cookMin,
    this.instructions = '',
    this.tags = '',
    this.category = defaultRecipeCategory,
    List<RecipeIngredient>? ingredients,
  }) : ingredients = ingredients ?? [];

  Map<String, Object?> toJson() => {
        'name': name,
        'servings': servings,
        'prep_min': prepMin,
        'cook_min': cookMin,
        'instructions': instructions,
        'tags': tags,
        'category': category,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
      };

  static Recipe fromJson(Map<String, dynamic> j) => Recipe(
        name: j['name'] as String,
        servings: (j['servings'] as num).toDouble(),
        prepMin: (j['prep_min'] as num?)?.toInt(),
        cookMin: (j['cook_min'] as num?)?.toInt(),
        instructions: (j['instructions'] as String?) ?? '',
        tags: (j['tags'] as String?) ?? '',
        category: (j['category'] as String?) ?? defaultRecipeCategory,
        ingredients: ((j['ingredients'] as List?) ?? [])
            .map((e) => RecipeIngredient.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PlanEntry {
  int? id;
  String weekStart; // ISO yyyy-mm-dd, lunes
  int day; // 0 = lunes
  String slot;
  int recipeId;
  String recipeName;
  double servings;

  PlanEntry({
    this.id,
    required this.weekStart,
    required this.day,
    required this.slot,
    required this.recipeId,
    required this.recipeName,
    required this.servings,
  });
}

/// Categorías de receta, en el orden en que se muestran.
const List<String> recipeCategories = [
  'Desayuno',
  'Entrada',
  'Ensalada',
  'Sopa',
  'Principal',
  'Guarnición',
  'Postre',
  'Merienda / snack',
  'Panadería',
  'Salsa',
  'Bebida',
  'Otra',
];

const String defaultRecipeCategory = 'Otra';

const List<String> mealSlots = [
  'desayuno',
  'almuerzo',
  'merienda',
  'cena',
  'colacion',
];

const Map<String, String> mealSlotLabels = {
  'desayuno': 'Desayuno',
  'almuerzo': 'Almuerzo',
  'merienda': 'Merienda',
  'cena': 'Cena',
  'colacion': 'Colación',
};

const List<String> dayLabels = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
