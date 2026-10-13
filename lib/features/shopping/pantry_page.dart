import 'package:flutter/material.dart';

import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/models.dart';
import '../../domain/shopping_list.dart';
import '../../domain/text.dart';
import '../recipes/food_picker_page.dart';

/// Lo que ya hay en casa; se descuenta de la lista de compras.
class PantryPage extends StatefulWidget {
  const PantryPage({super.key});

  @override
  State<PantryPage> createState() => _PantryPageState();
}

class _PantryPageState extends State<PantryPage> {
  List<ShoppingItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await Repo.instance.pantryItems();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _add() async {
    final food = await Navigator.push<Food>(
      context,
      MaterialPageRoute(builder: (_) => const FoodPickerPage()),
    );
    if (food == null || !mounted) return;
    final g = await askNumber(context,
        title: 'Cantidad de ${food.name}', suffix: 'g');
    if (g == null) return;
    await Repo.instance.setPantry(food, g);
    _load();
  }

  Future<void> _edit(ShoppingItem it) async {
    final g = await askNumber(context,
        title: 'Cantidad de ${it.name}', initial: it.grams, suffix: 'g');
    if (g == null) return;
    await Repo.instance.setPantry(
        Food(id: it.foodId, name: it.name, category: it.category), g);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Despensa')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: _items.isEmpty
          ? const EmptyState(
              icon: Icons.kitchen_outlined,
              text: 'Cargá lo que ya tenés en casa y se descuenta de la lista de compras.',
            )
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final it = _items[i];
                return ListTile(
                  title: Text(it.name),
                  subtitle: Text(it.category),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(fmtGrams(it.grams)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await Repo.instance.removePantry(it.foodId);
                          _load();
                        },
                      ),
                    ],
                  ),
                  onTap: () => _edit(it),
                );
              },
            ),
    );
  }
}
