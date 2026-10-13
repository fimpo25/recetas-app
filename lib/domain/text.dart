/// Utilidades de texto y formato (es_AR).

const Map<String, String> _accents = {
  'á': 'a',
  'é': 'e',
  'í': 'i',
  'ó': 'o',
  'ú': 'u',
  'ü': 'u',
  'ñ': 'n',
  'à': 'a',
  'è': 'e',
  'ì': 'i',
  'ò': 'o',
  'ù': 'u',
};

/// Minúsculas y sin acentos, para buscar.
String normalize(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

/// Número con coma decimal y separador de miles con punto.
String fmtNum(double v, {int decimals = 1}) {
  if (v.isNaN || v.isInfinite) return '-';
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    final fromEnd = intPart.length - i;
    b.write(intPart[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) b.write('.');
  }
  var out = b.toString();
  if (parts.length > 1) {
    final dec = parts[1].replaceFirst(RegExp(r'0+$'), '');
    if (dec.isNotEmpty) out = '$out,$dec';
  }
  return neg ? '-$out' : out;
}

/// Acepta "1,5" o "1.5".
double? parseNum(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Gramos legibles: 350 g, 1,2 kg.
String fmtGrams(double g) {
  if (g >= 1000) return '${fmtNum(g / 1000, decimals: 2)} kg';
  return '${fmtNum(g, decimals: 0)} g';
}

/// Lunes de la semana de una fecha, como yyyy-mm-dd.
String weekStartOf(DateTime d) {
  final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  return isoDate(monday);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseIso(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String shiftWeek(String weekStart, int weeks) => isoDate(addDays(parseIso(weekStart), 7 * weeks));

DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

String fmtShortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
