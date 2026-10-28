import 'package:flutter/material.dart';

import '../../common/recipe_style.dart';
import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';
import '../settings/import_pack.dart';
import 'recipe_detail_page.dart';
import 'recipe_edit_page.dart';

enum _Sort { name, protein, lowKcal, quick }

const _sortLabels = {
  _Sort.name: 'Nombre (A-Z)',
  _Sort.protein: 'Más proteína',
  _Sort.lowKcal: 'Menos calorías',
  _Sort.quick: 'Más rápidas',
};

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  String _query = '';
  String? _category;
  String? _book;
  _Sort _sort = _Sort.name;
  List<Recipe> _all = [];
  Map<int, RecipeSummary> _sum = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await Repo.instance.recipes();
    final sum = await Repo.instance.recipeSummaries();
    if (!mounted) return;
    setState(() {
      _all = all;
      _sum = sum;
      _loaded = true;
    });
  }

  // ------------------------------------------------------------ filtros

  bool _matchesText(Recipe r) {
    final q = normalize(_query.trim());
    if (q.isEmpty) return true;
    final hay = normalize('${r.name} ${r.tags} ${r.category} ${bookOf(r.tags) ?? ''}');
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  List<Recipe> get _visible {
    final list = _all
        .where((r) => _category == null || r.category == _category)
        .where((r) => _book == null || (bookOf(r.tags) ?? 'Mis recetas') == _book)
        .where(_matchesText)
        .toList();
    int byName(Recipe a, Recipe b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    RecipeSummary s(Recipe r) => _sum[r.id] ?? const RecipeSummary(0, 0, 0, 0);
    switch (_sort) {
      case _Sort.name:
        list.sort(byName);
      case _Sort.protein:
        list.sort((a, b) => s(b).protein.compareTo(s(a).protein));
      case _Sort.lowKcal:
        list.sort((a, b) => s(a).kcal.compareTo(s(b).kcal));
      case _Sort.quick:
        int t(Recipe r) {
          final m = (r.prepMin ?? 0) + (r.cookMin ?? 0);
          return m == 0 ? 1 << 20 : m;
        }
        list.sort((a, b) {
          final c = t(a).compareTo(t(b));
          return c != 0 ? c : byName(a, b);
        });
    }
    return list;
  }

  Map<String, int> _counts(String Function(Recipe) key) {
    final m = <String, int>{};
    for (final r in _all) {
      final k = key(r);
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  Future<void> _pickBook() async {
    final counts = _counts((r) => bookOf(r.tags) ?? 'Mis recetas');
    final books = counts.keys.toList()..sort();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Recetario',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              ListTile(
                leading: const Icon(Icons.library_books_outlined),
                title: const Text('Todos'),
                trailing: Text('${_all.length}'),
                selected: _book == null,
                onTap: () => Navigator.pop(ctx, ''),
              ),
              for (final b in books)
                ListTile(
                  leading: Icon(b == 'Mis recetas'
                      ? Icons.person_outline
                      : Icons.menu_book_outlined),
                  title: Text(b),
                  trailing: Text('${counts[b]}'),
                  selected: _book == b,
                  onTap: () => Navigator.pop(ctx, b),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _book = picked.isEmpty ? null : picked);
  }

  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<_Sort>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in _sortLabels.entries)
              ListTile(
                leading: Icon(e.key == _sort
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                title: Text(e.value),
                onTap: () => Navigator.pop(ctx, e.key),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _sort = picked);
  }

  // ------------------------------------------------------------ navegación

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

  // ------------------------------------------------------------ vista

  @override
  Widget build(BuildContext context) {
    final visible = _loaded ? _visible : const <Recipe>[];
    final catCounts = _counts((r) => r.category);
    final cats = recipeCategories.where(catCounts.containsKey).toList();
    // agrupar por categoría cuando se ve todo ordenado por nombre
    final grouped = _category == null && _sort == _Sort.name;
    final items = <Object>[];
    if (grouped) {
      for (final c in recipeCategories) {
        final rs = visible.where((r) => r.category == c).toList();
        if (rs.isEmpty) continue;
        items.add(_Header(c, rs.length));
        items.addAll(rs);
      }
    } else {
      items.addAll(visible);
    }

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
            child: SearchBar(
              hintText: 'Buscar: "pollo", "budín", "keto"…',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (cats.length > 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('Todas · ${_all.length}'),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null),
                    ),
                  ),
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: Icon(categoryStyle(c).icon,
                            size: 18, color: categoryStyle(c).color),
                        label: Text('$c · ${catCounts[c]}'),
                        selected: _category == c,
                        onSelected: (_) => setState(
                            () => _category = _category == c ? null : c),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text(_book ?? 'Todos los recetarios',
                      overflow: TextOverflow.ellipsis),
                  onPressed: _pickBook,
                ),
                if (_book != null)
                  IconButton(
                    tooltip: 'Quitar filtro',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _book = null),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pickSort,
                  icon: const Icon(Icons.sort, size: 18),
                  label: Text(_sortLabels[_sort]!),
                ),
              ],
            ),
          ),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? EmptyState(
                        icon: Icons.menu_book_outlined,
                        text: _all.isNotEmpty
                            ? 'No hay recetas que coincidan con el filtro.'
                            : 'Todavía no hay recetas. Tocá "Nueva receta" para cargar la primera, o importá un recetario con el botón de arriba.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final it = items[i];
                          if (it is _Header) return _HeaderRow(it);
                          final r = it as Recipe;
                          return _RecipeCard(
                            recipe: r,
                            summary: _sum[r.id],
                            showCategory: !grouped,
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

class _Header {
  final String category;
  final int count;
  const _Header(this.category, this.count);
}

class _HeaderRow extends StatelessWidget {
  final _Header h;
  const _HeaderRow(this.h);

  @override
  Widget build(BuildContext context) {
    final s = categoryStyle(h.category);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Row(
        children: [
          Icon(s.icon, color: s.color, size: 20),
          const SizedBox(width: 8),
          Text(h.category,
              style: TextStyle(
                  color: s.color, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text('${h.count}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          Expanded(
              child: Divider(color: s.color.withValues(alpha: 0.35), height: 1)),
        ],
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final RecipeSummary? summary;
  final bool showCategory;
  final VoidCallback onTap;

  const _RecipeCard({
    required this.recipe,
    required this.summary,
    required this.showCategory,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = recipe;
    final s = summary;
    final style = categoryStyle(r.category);
    final scheme = Theme.of(context).colorScheme;
    final time = (r.prepMin ?? 0) + (r.cookMin ?? 0);
    final book = bookOf(r.tags);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: style.color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      RecipeThumb(category: r.category, photo: r.photo, size: 64),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15.5, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 12,
                              runSpacing: 2,
                              children: [
                                if (s != null && s.kcal > 0)
                                  InfoPill(Icons.local_fire_department,
                                      '${fmtNum(s.kcal, decimals: 0)} kcal',
                                      color: const Color(0xFFFFB74D)),
                                if (s != null && s.protein > 0)
                                  InfoPill(Icons.fitness_center,
                                      '${fmtNum(s.protein, decimals: 0)} g prot',
                                      color: const Color(0xFF81C784)),
                                if (time > 0)
                                  InfoPill(Icons.schedule, '$time min'),
                                InfoPill(Icons.people_outline,
                                    '${fmtNum(r.servings)} porc.'),
                              ],
                            ),
                            if (showCategory || book != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                [
                                  if (showCategory) r.category,
                                  if (book != null) book,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: scheme.outline),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
