import 'package:flutter/material.dart';

import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';
import '../settings/import_pack.dart';
import 'recipe_detail_page.dart';
import 'recipe_edit_page.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  String _query = '';
  String? _category;
  List<String> _usedCategories = [];
  List<Recipe> _recipes = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Repo.instance.recipes(query: _query, category: _category);
    final all = await Repo.instance.recipes();
    final used = all.map((e) => e.category).toSet();
    if (!mounted) return;
    setState(() {
      _recipes = r;
      _usedCategories =
          recipeCategories.where(used.contains).toList();
      _loaded = true;
    });
  }

  Future<void> _open(Recipe r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecipeDetailPage(recipeId: r.id!)),
    );
    _load();
  }

  Future<void> _new() async {
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => const RecipeEditPage()),
    );
    await _load();
    if (id != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RecipeDetailPage(recipeId: id)),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recetas'),
        actions: [
          IconButton(
            tooltip: 'Importar recetario (.json)',
            icon: const Icon(Icons.library_add_outlined),
            onPressed: () async {
              if (await importRecipePackFlow(context)) _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('Nueva receta'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nombre, etiqueta o categoría',
              ),
              onChanged: (v) {
                _query = v;
                _load();
              },
            ),
          ),
          if (_usedCategories.length > 1 || _category != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: CategoryFilter(
                categories: _usedCategories,
                selected: _category,
                onChanged: (c) {
                  _category = c;
                  _load();
                },
              ),
            ),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _recipes.isEmpty
                    ? EmptyState(
                        icon: Icons.menu_book_outlined,
                        text: (_category != null || _query.trim().isNotEmpty)
                            ? 'No hay recetas que coincidan con el filtro.'
                            : 'Todavía no hay recetas. Tocá "Nueva receta" para cargar la primera, o importá un recetario con el botón de arriba.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: _recipes.length,
                        itemBuilder: (context, i) {
                          final r = _recipes[i];
                          final time = (r.prepMin ?? 0) + (r.cookMin ?? 0);
                          final parts = <String>[
                            r.category,
                            '${fmtNum(r.servings)} porciones',
                            if (time > 0) '$time min',
                            if (r.tags.trim().isNotEmpty) r.tags,
                          ];
                          return ListTile(
                            title: Text(r.name),
                            subtitle: Text(parts.join(' · ')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(r),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
