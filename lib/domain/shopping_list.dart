/// Consolidación de la lista de compras.

class NeedLine {
  final int foodId;
  final String name;
  final String category;
  final double grams;
  const NeedLine(this.foodId, this.name, this.category, this.grams);
}

class ShoppingItem {
  final int foodId;
  final String name;
  final String category;
  final double grams;
  const ShoppingItem(this.foodId, this.name, this.category, this.grams);
}

/// Agrupa por alimento, suma gramos y descuenta despensa (mínimo cero).
List<ShoppingItem> buildShoppingList(
  List<NeedLine> lines, {
  Map<int, double> pantry = const {},
}) {
  final grams = <int, double>{};
  final names = <int, String>{};
  final cats = <int, String>{};
  for (final l in lines) {
    grams[l.foodId] = (grams[l.foodId] ?? 0) + l.grams;
    names[l.foodId] = l.name;
    cats[l.foodId] = l.category;
  }
  final out = <ShoppingItem>[];
  grams.forEach((id, g) {
    final need = g - (pantry[id] ?? 0);
    if (need > 0.0001) {
      out.add(ShoppingItem(id, names[id]!, cats[id]!, need));
    }
  });
  out.sort((a, b) {
    final c = a.category.compareTo(b.category);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return out;
}

/// Redondea hacia arriba a una cantidad de compra razonable.
double roundUpPurchase(double grams) {
  if (grams <= 0) return 0;
  if (grams < 100) return (grams / 10).ceil() * 10.0;
  if (grams < 1000) return (grams / 50).ceil() * 50.0;
  return (grams / 100).ceil() * 100.0;
}
