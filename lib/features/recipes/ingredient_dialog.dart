import 'package:flutter/material.dart';

import '../../data/repo.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';
import '../../domain/units.dart';

/// Pide cantidad, unidad y nota para un alimento y devuelve el ingrediente
/// con los gramos ya resueltos.
Future<RecipeIngredient?> showIngredientDialog(
  BuildContext context, {
  required Food food,
  RecipeIngredient? initial,
}) async {
  final portions = await Repo.instance.portions(food.id);
  if (!context.mounted) return null;
  return showDialog<RecipeIngredient>(
    context: context,
    builder: (_) => _IngredientDialog(
      food: food,
      portions: portions,
      initial: initial,
    ),
  );
}

class _IngredientDialog extends StatefulWidget {
  final Food food;
  final List<Portion> portions;
  final RecipeIngredient? initial;

  const _IngredientDialog({
    required this.food,
    required this.portions,
    this.initial,
  });

  @override
  State<_IngredientDialog> createState() => _IngredientDialogState();
}

class _IngredientDialogState extends State<_IngredientDialog> {
  static const _otherPortion = '__otra__';

  late final TextEditingController _qty;
  late final TextEditingController _note;
  late List<String> _units;
  late String _unit;
  String? _error;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    final ini = widget.initial;
    _qty = TextEditingController(
        text: ini == null ? '' : fmtNum(ini.qty, decimals: 3));
    _note = TextEditingController(text: ini?.note ?? '');
    _units = [
      ...fixedUnits,
      ...widget.portions.map((p) => portionUnit(p.label, p.grams)),
    ];
    if (ini != null && !_units.contains(ini.unit)) _units.add(ini.unit);
    _unit = ini?.unit ?? 'g';
  }

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  String _label(String u) {
    if (isPortionUnit(u)) {
      return '${unitLabel(u)} (${fmtNum(portionGrams(u) ?? 0, decimals: 1)} g)';
    }
    switch (u) {
      case 'cdita':
        return 'cdita (5 ml)';
      case 'cda':
        return 'cda (15 ml)';
      case 'taza':
        return 'taza (250 ml)';
      default:
        return u;
    }
  }

  Future<void> _askPortion() async {
    final label = TextEditingController();
    final grams = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva porción'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: const InputDecoration(
                  labelText: 'Nombre (ej: 1 diente, 1 unidad mediana)'),
            ),
            TextField(
              controller: grams,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Peso', suffixText: 'g'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aceptar')),
        ],
      ),
    );
    final g = parseNum(grams.text);
    final l = label.text.trim();
    if (ok == true && g != null && g > 0 && l.isNotEmpty) {
      final u = portionUnit(l, g);
      if (widget.food.custom) {
        await Repo.instance.addCustomPortion(widget.food.id, Portion(l, g));
      }
      setState(() {
        if (!_units.contains(u)) _units.add(u);
        _unit = u;
      });
    }
  }

  void _save() {
    final q = parseNum(_qty.text);
    if (q == null || q <= 0) {
      setState(() => _error = 'Cantidad inválida');
      return;
    }
    final g = toGrams(qty: q, unit: _unit, density: widget.food.density);
    if (g == null) {
      setState(() => _error = 'No se puede convertir esa unidad');
      return;
    }
    Navigator.pop(
      context,
      RecipeIngredient(
        id: widget.initial?.id,
        foodId: widget.food.id,
        foodName: widget.food.name,
        qty: q,
        unit: _unit,
        grams: g,
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.food.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _qty,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Cantidad', errorText: _error),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('$_unit#$_rev'),
              initialValue: _unit,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Unidad'),
              items: [
                for (final u in _units)
                  DropdownMenuItem(value: u, child: Text(_label(u))),
                const DropdownMenuItem(
                    value: _otherPortion, child: Text('Otra porción…')),
              ],
              onChanged: (v) {
                if (v == null) return;
                if (v == _otherPortion) {
                  setState(() => _rev++);
                  _askPortion();
                } else {
                  setState(() => _unit = v);
                }
              },
            ),
            TextField(
              controller: _note,
              decoration:
                  const InputDecoration(labelText: 'Nota (ej: picada fina)'),
            ),
            if (volumeUnitsMl.containsKey(_unit) && widget.food.density == 1.0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Sin densidad cargada: se toma 1 ml = 1 g.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
