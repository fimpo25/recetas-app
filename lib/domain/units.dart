/// Conversión de cantidades a gramos.
///
/// Unidades fijas: g, kg, ml, l, cdita (5 ml), cda (15 ml), taza (250 ml).
/// Porciones caseras del alimento: 'p:<etiqueta>|<gramos>'.

const Map<String, double> massUnits = {'g': 1, 'kg': 1000};
const Map<String, double> volumeUnitsMl = {
  'ml': 1,
  'l': 1000,
  'cdita': 5,
  'cda': 15,
  'taza': 250,
};

const List<String> fixedUnits = ['g', 'kg', 'ml', 'l', 'cdita', 'cda', 'taza'];

String portionUnit(String label, double grams) => 'p:$label|$grams';

bool isPortionUnit(String unit) => unit.startsWith('p:');

/// Etiqueta legible de una unidad.
String unitLabel(String unit) {
  if (isPortionUnit(unit)) {
    final body = unit.substring(2);
    final bar = body.lastIndexOf('|');
    return bar < 0 ? body : body.substring(0, bar);
  }
  return unit;
}

double? portionGrams(String unit) {
  if (!isPortionUnit(unit)) return null;
  final bar = unit.lastIndexOf('|');
  if (bar < 0) return null;
  return double.tryParse(unit.substring(bar + 1));
}

/// Devuelve los gramos o null si la unidad no se puede convertir.
double? toGrams({
  required double qty,
  required String unit,
  double density = 1.0,
}) {
  if (qty < 0) return null;
  final mass = massUnits[unit];
  if (mass != null) return qty * mass;
  final vol = volumeUnitsMl[unit];
  if (vol != null) {
    final d = density > 0 ? density : 1.0;
    return qty * vol * d;
  }
  final pg = portionGrams(unit);
  if (pg != null) return qty * pg;
  return null;
}
