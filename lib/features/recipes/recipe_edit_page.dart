import 'package:flutter/material.dart';

import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';
import '../../domain/units.dart';
import 'food_picker_page.dart';
import 'ingredient_dialog.dart';

/// Alta y edición de recetas. Devuelve el id guardado.
class RecipeEditPage extends StatefulWidget {
  final Recipe? recipe;
  const RecipeEditPage({super.key, this.recipe});

  @override
  State<RecipeEditPage> createState() => _RecipeEditPageState();
}

class _RecipeEditPageState extends State<RecipeEditPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _servings;
  late final TextEditingController _prep;
  late final TextEditingController _cook;
  late final TextEditingController _tags;
  late final TextEditingController _instructions;
  late List<RecipeIngredient> _ingredients;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    _name = TextEditingController(text: r?.name ?? '');
    _servings = TextEditingController(text: fmtNum(r?.servings ?? 4));
    _prep = TextEditingController(text: r?.prepMin?.toString() ?? '');
    _cook = TextEditingController(text: r?.cookMin?.toString() ?? '');
    _tags = TextEditingController(text: r?.tags ?? '');
    _instructions = TextEditingController(text: r?.instructions ?? '');
    _ingredients = r == null
        ? []
        : r.ingredients
            .map((i) => RecipeIngredient(
                  id: i.id,
                  foodId: i.foodId,
                  foodName: i.foodName,
                  qty: i.qty,
                  unit: i.unit,
                  grams: i.grams,
                  note: i.note,
                ))
            .toList();
  }

  @override
  void dispose() {
    for (final c in [_name, _servings, _prep, _cook, _tags, _instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addIngredient() async {
    final food = await Navigator.push<Food>(
      context,
      MaterialPageRoute(builder: (_) => const FoodPickerPage()),
    );
    if (food == null || !mounted) return;
    final ing = await showIngredientDialog(context, food: food);
    if (ing == null) return;
    setState(() => _ingredients.add(ing));
  }

  Future<void> _editIngredient(int index) async {
    final current = _ingredients[index];
    final foods = await Repo.instance.foodsByIds({current.foodId});
    if (!mounted) return;
    final food = foods[current.foodId] ??
        Food(id: current.foodId, name: current.foodName, category: 'Almacén');
    final ing =
        await showIngredientDialog(context, food: food, initial: current);
    if (ing == null) return;
    setState(() => _ingredients[index] = ing);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final r = Recipe(
      id: widget.recipe?.id,
      name: _name.text.trim(),
      servings: parseNum(_servings.text) ?? 1,
      prepMin: int.tryParse(_prep.text.trim()),
      cookMin: int.tryParse(_cook.text.trim()),
      tags: _tags.text.trim(),
      instructions: _instructions.text.trim(),
      ingredients: _ingredients,
    );
    final id = await Repo.instance.saveRecipe(r);
    if (!mounted) return;
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipe == null ? 'Nueva receta' : 'Editar receta'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Guardar'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Poné un nombre' : null,
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _servings,
                    decoration: const InputDecoration(labelText: 'Porciones'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = parseNum(v ?? '');
                      return (n == null || n <= 0) ? 'Mayor a cero' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _prep,
                    decoration:
                        const InputDecoration(labelText: 'Prep. (min)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cook,
                    decoration:
                        const InputDecoration(labelText: 'Cocción (min)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(
                  labelText: 'Etiquetas (ej: vegetariano, rápido)'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Ingredientes', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addIngredient,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            if (_ingredients.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Agregá ingredientes desde la base de alimentos.'),
              ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (oldI, newI) {
                setState(() {
                  if (newI > oldI) newI -= 1;
                  final it = _ingredients.removeAt(oldI);
                  _ingredients.insert(newI, it);
                });
              },
              children: [
                for (var i = 0; i < _ingredients.length; i++)
                  ListTile(
                    key: ObjectKey(_ingredients[i]),
                    contentPadding: EdgeInsets.zero,
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(_ingredients[i].foodName),
                    subtitle: Text(
                      '${fmtNum(_ingredients[i].qty, decimals: 2)} ${unitLabel(_ingredients[i].unit)}'
                      ' · ${fmtGrams(_ingredients[i].grams)}'
                      '${_ingredients[i].note.isEmpty ? '' : ' · ${_ingredients[i].note}'}',
                    ),
                    onTap: () => _editIngredient(i),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirm(context, 'Quitar ingrediente',
                            'Se quita ${_ingredients[i].foodName}.');
                        if (ok) setState(() => _ingredients.removeAt(i));
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _instructions,
              decoration: const InputDecoration(
                labelText: 'Preparación',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              minLines: 5,
              maxLines: 20,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
