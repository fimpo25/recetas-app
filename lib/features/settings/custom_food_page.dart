import 'package:flutter/material.dart';

import '../../data/repo.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';

const List<String> foodCategories = [
  'Verdulería',
  'Frutas',
  'Carnicería',
  'Pescadería',
  'Granja y huevos',
  'Lácteos',
  'Panadería y cereales',
  'Legumbres y frutos secos',
  'Almacén',
  'Aceites y grasas',
  'Especias',
  'Bebidas',
  'Fiambrería',
  'Dulces',
  'Otros',
];

/// Alta o edición de un alimento propio (datos por 100 g, de la etiqueta).
class CustomFoodPage extends StatefulWidget {
  final Food? food;
  final String initialName;
  const CustomFoodPage({super.key, this.food, this.initialName = ''});

  @override
  State<CustomFoodPage> createState() => _CustomFoodPageState();
}

class _CustomFoodPageState extends State<CustomFoodPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _density;
  final _portionLabel = TextEditingController();
  final _portionGrams = TextEditingController();
  String _category = 'Almacén';
  List<Nutrient> _nutrients = [];
  final Map<int, TextEditingController> _values = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.food?.name ?? widget.initialName);
    _density = TextEditingController(
        text: fmtNum(widget.food?.density ?? 1.0, decimals: 3));
    if (widget.food != null && foodCategories.contains(widget.food!.category)) {
      _category = widget.food!.category;
    }
    _load();
  }

  Future<void> _load() async {
    final ns = await Repo.instance.nutrients();
    Map<int, double> existing = {};
    List<Portion> portions = [];
    if (widget.food != null) {
      existing = (await Repo.instance.per100({widget.food!.id}))[widget.food!.id] ?? {};
      portions = await Repo.instance.portions(widget.food!.id);
    }
    if (!mounted) return;
    setState(() {
      _nutrients = ns;
      for (final n in ns) {
        final v = existing[n.id];
        _values[n.id] =
            TextEditingController(text: v == null ? '' : fmtNum(v, decimals: 3));
      }
      if (portions.isNotEmpty) {
        _portionLabel.text = portions.first.label;
        _portionGrams.text = fmtNum(portions.first.grams, decimals: 1);
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _density.dispose();
    _portionLabel.dispose();
    _portionGrams.dispose();
    for (final c in _values.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final values = <int, double>{};
    _values.forEach((id, c) {
      final v = parseNum(c.text);
      if (v != null) values[id] = v;
    });
    final portions = <Portion>[];
    final pg = parseNum(_portionGrams.text);
    if (_portionLabel.text.trim().isNotEmpty && pg != null && pg > 0) {
      portions.add(Portion(_portionLabel.text.trim(), pg));
    }
    final id = await Repo.instance.saveCustomFood(
      id: widget.food?.id,
      name: _name.text.trim(),
      category: _category,
      density: parseNum(_density.text) ?? 1.0,
      values: values,
      portions: portions,
    );
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.food == null ? 'Alimento propio' : 'Editar alimento'),
        actions: [
          TextButton(onPressed: _loaded ? _save : null, child: const Text('Guardar')),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Poné un nombre' : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Categoría de compra'),
                    items: [
                      for (final c in foodCategories)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() => _category = v ?? _category),
                  ),
                  TextFormField(
                    controller: _density,
                    decoration: const InputDecoration(
                        labelText: 'Densidad (g/ml, para medidas en volumen)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  Text('Porción casera (opcional)', style: theme.textTheme.titleSmall),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _portionLabel,
                          decoration: const InputDecoration(
                              labelText: 'Nombre (ej: 1 paquete)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _portionGrams,
                          decoration: const InputDecoration(
                              labelText: 'Peso', suffixText: 'g'),
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Valores por 100 g', style: theme.textTheme.titleSmall),
                  const Text(
                    'Copiá la tabla nutricional del envase. Lo que dejes vacío cuenta como "sin dato".',
                    style: TextStyle(fontSize: 12),
                  ),
                  for (final n in _nutrients)
                    TextFormField(
                      controller: _values[n.id],
                      decoration: InputDecoration(
                          labelText: n.nameEs, suffixText: n.unit),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
