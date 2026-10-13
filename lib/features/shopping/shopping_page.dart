import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/shopping_list.dart';
import '../../domain/text.dart';
import 'pantry_page.dart';

class ShoppingPage extends StatefulWidget {
  const ShoppingPage({super.key});

  @override
  State<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends State<ShoppingPage> {
  String _week = weekStartOf(DateTime.now());
  List<ShoppingItem> _items = [];
  Set<int> _checked = {};
  bool _loaded = false;

  String get _checkedKey => 'checked_$_week';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = Repo.instance;
    final items = await repo.shoppingList(_week);
    final saved = await repo.setting(_checkedKey) ?? '';
    if (!mounted) return;
    setState(() {
      _items = items;
      _checked = saved
          .split(',')
          .where((s) => s.isNotEmpty)
          .map(int.parse)
          .toSet();
      _loaded = true;
    });
  }

  Future<void> _toggle(int foodId) async {
    setState(() {
      if (!_checked.remove(foodId)) _checked.add(foodId);
    });
    await Repo.instance.setSetting(_checkedKey, _checked.join(','));
  }

  Future<void> _copy() async {
    final b = StringBuffer('Lista de compras · semana ${fmtShortDate(parseIso(_week))}\n');
    String? cat;
    for (final it in _items) {
      if (_checked.contains(it.foodId)) continue;
      if (it.category != cat) {
        cat = it.category;
        b.writeln('\n${cat.toUpperCase()}');
      }
      b.writeln('- ${it.name}: ${fmtGrams(roundUpPurchase(it.grams))}');
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (mounted) showSnack(context, 'Lista copiada. Pegala en WhatsApp o donde quieras.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];
    String? cat;
    for (final it in _items) {
      if (it.category != cat) {
        cat = it.category;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(cat, style: theme.textTheme.titleSmall),
        ));
      }
      final done = _checked.contains(it.foodId);
      children.add(CheckboxListTile(
        value: done,
        onChanged: (_) => _toggle(it.foodId),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        title: Text(
          it.name,
          style: done
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        secondary: Text(fmtGrams(roundUpPurchase(it.grams))),
      ));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de compras'),
        actions: [
          IconButton(
            tooltip: 'Despensa',
            icon: const Icon(Icons.kitchen_outlined),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PantryPage()));
              _load();
            },
          ),
          IconButton(
            tooltip: 'Copiar lista',
            icon: const Icon(Icons.copy),
            onPressed: _items.isEmpty ? null : _copy,
          ),
        ],
      ),
      body: Column(
        children: [
          WeekSelector(
            weekStart: _week,
            onChanged: (w) {
              _week = w;
              _load();
            },
          ),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const EmptyState(
                        icon: Icons.shopping_cart_outlined,
                        text: 'No hay nada que comprar esta semana. Armá el plan en la pestaña Plan.',
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: children,
                      ),
          ),
        ],
      ),
    );
  }
}
