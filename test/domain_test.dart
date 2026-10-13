import 'package:flutter_test/flutter_test.dart';
import 'package:recetas_app/data/updater.dart';
import 'package:recetas_app/domain/nutrition_calc.dart';
import 'package:recetas_app/domain/shopping_list.dart';
import 'package:recetas_app/domain/targets.dart';
import 'package:recetas_app/domain/text.dart';
import 'package:recetas_app/domain/units.dart';

void main() {
  group('Conversión a gramos', () {
    test('1 taza de leche (densidad 1,03) = 257,5 g', () {
      expect(toGrams(qty: 1, unit: 'taza', density: 1.03), closeTo(257.5, 1e-9));
    });
    test('2 huevos de 50 g = 100 g', () {
      expect(toGrams(qty: 2, unit: portionUnit('1 huevo', 50)), 100);
    });
    test('kg, cda y unidad desconocida', () {
      expect(toGrams(qty: 1.5, unit: 'kg'), 1500);
      expect(toGrams(qty: 2, unit: 'cda'), 30);
      expect(toGrams(qty: 1, unit: 'xyz'), isNull);
    });
    test('etiqueta de porción', () {
      expect(unitLabel(portionUnit('1 diente', 5)), '1 diente');
      expect(unitLabel('g'), 'g');
    });
  });

  group('Nutrición', () {
    const protein = 1;
    const iron = 2;
    test('100 g con 10 g de proteína / 100 g = 10 g; 4 porciones = 2,5 g', () {
      final t = sumIngredients(
        [const IngredientData(grams: 100, per100g: {protein: 10})],
        [protein],
      );
      expect(t.value(protein), closeTo(10, 1e-9));
      expect(perServing(t, 4).value(protein), closeTo(2.5, 1e-9));
    });
    test('fracción comestible', () {
      final t = sumIngredients(
        [const IngredientData(grams: 200, edible: 0.5, per100g: {protein: 10})],
        [protein],
      );
      expect(t.value(protein), closeTo(10, 1e-9));
    });
    test('dato faltante no cuenta como cero silencioso', () {
      final t = sumIngredients(
        [
          const IngredientData(grams: 100, per100g: {protein: 10, iron: 1}),
          const IngredientData(grams: 100, per100g: {protein: 5}),
        ],
        [protein, iron],
      );
      expect(t.missingShare(iron), 0.5);
      expect(t.missingShare(protein), 0);
    });
    test('escalado 4 → 6 porciones = 1,5', () {
      expect(scaleFactor(4, 6), 1.5);
    });
    test('porciones cero rechazado', () {
      expect(() => perServing(NutritionTotals.empty, 0), throwsArgumentError);
      expect(() => scaleFactor(0, 2), throwsArgumentError);
    });
    test('% VD', () {
      expect(percentDv(50, 200), 25);
      expect(isAlert(120, true), isTrue);
      expect(isAlert(50, false), isTrue);
      expect(isAlert(90, false), isFalse);
    });
  });

  group('Lista de compras', () {
    test('suma por alimento y descuenta despensa', () {
      final list = buildShoppingList(
        const [
          NeedLine(7, 'Cebolla', 'Verdulería', 200),
          NeedLine(7, 'Cebolla', 'Verdulería', 300),
          NeedLine(9, 'Arroz', 'Almacén', 100),
        ],
        pantry: {7: 100, 9: 500},
      );
      expect(list.length, 1);
      expect(list.first.name, 'Cebolla');
      expect(list.first.grams, closeTo(400, 1e-9));
    });
    test('redondeo de compra', () {
      expect(roundUpPurchase(43), 50);
      expect(roundUpPurchase(420), 450);
      expect(roundUpPurchase(1230), 1300);
    });
  });

  group('Energía', () {
    test('Mifflin-St Jeor', () {
      expect(mifflinStJeor(male: true, weightKg: 80, heightCm: 180, age: 40),
          closeTo(1730, 1e-9));
      expect(mifflinStJeor(male: false, weightKg: 60, heightCm: 165, age: 30),
          closeTo(1320.25, 1e-9));
    });
  });

  group('Texto', () {
    test('normalizar y formatear', () {
      expect(normalize('Ñandú Árbol'), 'nandu arbol');
      expect(fmtNum(1234.5), '1.234,5');
      expect(fmtNum(2.0), '2');
      expect(parseNum('1,5'), 1.5);
      expect(fmtGrams(1250), '1,25 kg');
    });
    test('semanas', () {
      expect(weekStartOf(DateTime(2026, 10, 15)), '2026-10-12');
      expect(shiftWeek('2026-10-12', 1), '2026-10-19');
      expect(shiftWeek('2026-12-28', 1), '2027-01-04');
    });
  });

  group('Actualizaciones', () {
    test('número de compilación desde el tag', () {
      expect(buildFromTag('v0.1.12'), 12);
      expect(buildFromTag('v0.1.3'), 3);
      expect(buildFromTag('basura'), 0);
    });
    test('novedades = primer párrafo del release', () {
      expect(notesFromBody('Categorías de receta\n\nCompilado desde abc.'),
          'Categorías de receta');
      expect(notesFromBody('Compilado desde abc.\n\n- algo'), '');
    });
  });
}
