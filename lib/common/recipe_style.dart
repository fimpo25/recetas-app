import 'package:flutter/material.dart';

/// Ícono y color de cada categoría, para reconocer las recetas de un vistazo.
class CategoryStyle {
  final IconData icon;
  final Color color;
  const CategoryStyle(this.icon, this.color);
}

const Map<String, CategoryStyle> _styles = {
  'Desayuno': CategoryStyle(Icons.free_breakfast, Color(0xFFFFB74D)),
  'Entrada': CategoryStyle(Icons.tapas, Color(0xFFFF8A65)),
  'Ensalada': CategoryStyle(Icons.eco, Color(0xFF81C784)),
  'Sopa': CategoryStyle(Icons.soup_kitchen, Color(0xFFE57373)),
  'Principal': CategoryStyle(Icons.dinner_dining, Color(0xFFEF5350)),
  'Guarnición': CategoryStyle(Icons.rice_bowl, Color(0xFFAED581)),
  'Postre': CategoryStyle(Icons.icecream, Color(0xFFF48FB1)),
  'Merienda / snack': CategoryStyle(Icons.cookie, Color(0xFFBCAAA4)),
  'Panadería': CategoryStyle(Icons.bakery_dining, Color(0xFFD7A86E)),
  'Salsa': CategoryStyle(Icons.water_drop, Color(0xFFFFD54F)),
  'Bebida': CategoryStyle(Icons.local_drink, Color(0xFF4FC3F7)),
  'Otra': CategoryStyle(Icons.restaurant, Color(0xFF90A4AE)),
};

CategoryStyle categoryStyle(String category) =>
    _styles[category] ?? _styles['Otra']!;

/// Nombre legible del recetario de origen (las recetas importadas guardan
/// una etiqueta por libro).
const Map<String, String> _bookNames = {
  'keto-proteica': 'Ensaladas keto y proteicas',
  'biblia-ensaladas': 'Biblia de las ensaladas 3',
  'biblia-ensaladas-1': 'Biblia de las ensaladas 1',
  'biblia-ensaladas-2': 'Biblia de las ensaladas 2',
  'vinagretas-salsas': 'Vinagretas y salsas',
  'cookies': 'Cookies saludables',
  'antiinflamatoria': 'Ensaladas antiinflamatorias',
  'vegana-vegetariana': 'Ensaladas veganas y vegetarianas',
  'jugos-detox': 'Jugos detox',
  'panes-galletitas': 'Panes y galletitas',
  'postres-antiinflamatorios': 'Postres antiinflamatorios',
  'wraps-sandwiches': 'Wraps y sándwiches',
  'desayunos-meriendas': 'Desayunos y meriendas',
  'budines': 'Budines saludables',
  'tartas': 'Tartas irresistibles',
  'internacionales-gourmet': 'Ensaladas internacionales',
  'rellenos-alfajores': 'Rellenos de alfajores',
  'deshidratados': 'Frutas y verduras deshidratadas',
  'hamburguesas': 'Hamburguesas saludables',
  'meal-prep': 'Meal prep',
  'toppings': 'Toppings crocantes',
  'emprender-ensaladas': 'Emprender con ensaladas',
  'antiinflamatorias-deliciosas': 'Antiinflamatorias y deliciosas',
};

/// Recetario de una receta según sus etiquetas, o null si es propia.
String? bookOf(String tags) {
  for (final t in tags.split(RegExp(r'[,\s]+'))) {
    final n = _bookNames[t.trim()];
    if (n != null) return n;
  }
  return null;
}

/// Ícono redondo de la categoría.
class CategoryAvatar extends StatelessWidget {
  final String category;
  final double size;
  const CategoryAvatar(this.category, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final s = categoryStyle(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(s.icon, color: s.color, size: size * 0.55),
    );
  }
}

/// Dato chico con ícono: "320 kcal", "25 g prot", "30 min".
class InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const InfoPill(this.icon, this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12.5, color: c)),
      ],
    );
  }
}
