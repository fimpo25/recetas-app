import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repo.dart';
import '../../domain/models.dart';
import '../settings/custom_food_page.dart';

/// Buscador de alimentos. Devuelve el [Food] elegido.
class FoodPickerPage extends StatefulWidget {
  const FoodPickerPage({super.key});

  @override
  State<FoodPickerPage> createState() => _FoodPickerPageState();
}

class _FoodPickerPageState extends State<FoodPickerPage> {
  final _ctrl = TextEditingController();
  List<Food> _results = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final r = await Repo.instance.searchFoods(q);
    if (!mounted) return;
    setState(() {
      _results = r;
      _loading = false;
    });
  }

  Future<void> _createCustom() async {
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(
          builder: (_) => CustomFoodPage(initialName: _ctrl.text.trim())),
    );
    if (id == null || !mounted) return;
    final foods = await Repo.instance.foodsByIds({id});
    if (!mounted) return;
    final f = foods[id];
    if (f != null) Navigator.pop(context, f);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Buscar alimento (ej: tomate, harina)',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCustom,
        icon: const Icon(Icons.add),
        label: const Text('Alimento propio'),
      ),
      body: _loading && _results.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_ctrl.text.isEmpty
                        ? 'Escribí para buscar. Los alimentos usados recientemente aparecen acá.'
                        : 'Sin resultados. Probá en inglés o creá un alimento propio.'),
                  ),
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final f = _results[i];
                    final sub = <String>[
                      f.category,
                      if (f.custom) 'propio',
                      if (f.nameEn != null && f.nameEn != f.name) f.nameEn!,
                    ].join(' · ');
                    return ListTile(
                      title: Text(f.name),
                      subtitle: Text(sub,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, f),
                    );
                  },
                ),
    );
  }
}
