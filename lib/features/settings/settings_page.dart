import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/models.dart';
import '../../domain/targets.dart';
import '../../domain/text.dart';
import '../../data/updater.dart';
import 'custom_food_page.dart';
import 'import_pack.dart';
import 'update_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    void go(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Perfil y energía'),
            subtitle: const Text('Calcular kcal diarias (Mifflin-St Jeor)'),
            onTap: () => go(const ProfilePage()),
          ),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Metas diarias de nutrientes'),
            subtitle: const Text('Valores de referencia para el % VD'),
            onTap: () => go(const TargetsPage()),
          ),
          ListTile(
            leading: const Icon(Icons.egg_outlined),
            title: const Text('Alimentos propios'),
            subtitle: const Text('Productos cargados desde la etiqueta'),
            onTap: () => go(const CustomFoodsPage()),
          ),
          ListTile(
            leading: const Icon(Icons.library_add_outlined),
            title: const Text('Importar recetario'),
            subtitle: const Text('Agregar recetas desde un archivo .json'),
            onTap: () => importRecipePackFlow(context),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Respaldo'),
            subtitle: const Text('Exportar o importar todos tus datos'),
            onTap: () => go(const BackupPage()),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Buscar actualización'),
            subtitle: Text('Versión instalada: $appVersion'),
            onTap: () => go(const UpdatePage()),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Datos nutricionales'),
            subtitle: Text(
                'USDA FoodData Central (SR Legacy), dominio público. Los alimentos propios se guardan solo en este teléfono.'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ perfil

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _male = true;
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  String _activity = activityFactors.keys.first;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = Repo.instance;
    final sex = await r.setting('profile_sex');
    _age.text = await r.setting('profile_age') ?? '';
    _weight.text = await r.setting('profile_weight') ?? '';
    _height.text = await r.setting('profile_height') ?? '';
    final act = await r.setting('profile_activity');
    if (!mounted) return;
    setState(() {
      _male = sex != 'f';
      if (act != null && activityFactors.containsKey(act)) _activity = act;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _age.dispose();
    _weight.dispose();
    _height.dispose();
    super.dispose();
  }

  double? get _kcal {
    final a = int.tryParse(_age.text.trim());
    final w = parseNum(_weight.text);
    final h = parseNum(_height.text);
    if (a == null || w == null || h == null) return null;
    return dailyEnergy(
      male: _male,
      weightKg: w,
      heightCm: h,
      age: a,
      activityFactor: activityFactors[_activity]!,
    );
  }

  Future<void> _apply() async {
    final kcal = _kcal;
    if (kcal == null) return;
    final r = Repo.instance;
    await r.setSetting('profile_sex', _male ? 'm' : 'f');
    await r.setSetting('profile_age', _age.text.trim());
    await r.setSetting('profile_weight', _weight.text.trim());
    await r.setSetting('profile_height', _height.text.trim());
    await r.setSetting('profile_activity', _activity);
    // Escala energía y macros respecto de la referencia de 2000 kcal.
    final f = kcal / 2000.0;
    for (final code in ['energy_kcal', 'protein_g', 'fat_g', 'sat_fat_g', 'carbs_g', 'fiber_g', 'sugars_g']) {
      final d = defaultTargets[code]!;
      await r.setTarget(code, d.value * f, d.upperLimit);
    }
    if (mounted) {
      showSnack(context, 'Metas actualizadas a ${fmtNum(kcal, decimals: 0)} kcal');
    }
  }

  @override
  Widget build(BuildContext context) {
    final kcal = _kcal;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil y energía')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Hombre')),
                    ButtonSegment(value: false, label: Text('Mujer')),
                  ],
                  selected: {_male},
                  onSelectionChanged: (s) => setState(() => _male = s.first),
                ),
                TextField(
                  controller: _age,
                  decoration: const InputDecoration(labelText: 'Edad', suffixText: 'años'),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _weight,
                  decoration: const InputDecoration(labelText: 'Peso', suffixText: 'kg'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _height,
                  decoration: const InputDecoration(labelText: 'Altura', suffixText: 'cm'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _activity,
                  decoration: const InputDecoration(labelText: 'Actividad física'),
                  items: [
                    for (final a in activityFactors.keys)
                      DropdownMenuItem(value: a, child: Text(a)),
                  ],
                  onChanged: (v) => setState(() => _activity = v ?? _activity),
                ),
                const SizedBox(height: 24),
                Text(
                  kcal == null
                      ? 'Completá los datos para calcular.'
                      : 'Energía diaria estimada: ${fmtNum(kcal, decimals: 0)} kcal',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: kcal == null ? null : _apply,
                  child: const Text('Aplicar a mis metas'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ajusta energía y macronutrientes en proporción a la referencia de 2000 kcal. Los micronutrientes no cambian. Es una estimación, no reemplaza a un profesional.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
    );
  }
}

// ------------------------------------------------------------------ metas

class TargetsPage extends StatefulWidget {
  const TargetsPage({super.key});

  @override
  State<TargetsPage> createState() => _TargetsPageState();
}

class _TargetsPageState extends State<TargetsPage> {
  List<Nutrient> _nutrients = [];
  Map<String, Target> _targets = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ns = await Repo.instance.nutrients();
    final ts = await Repo.instance.targets();
    if (!mounted) return;
    setState(() {
      _nutrients = ns;
      _targets = ts;
    });
  }

  Future<void> _edit(Nutrient n) async {
    final t = _targets[n.code];
    final v = await askNumber(context,
        title: 'Meta diaria de ${n.nameEs}', initial: t?.value, suffix: n.unit);
    if (v == null || v <= 0) return;
    await Repo.instance.setTarget(n.code, v, t?.upper ?? false);
    _load();
  }

  Future<void> _reset() async {
    final ok = await confirm(context, 'Restablecer metas',
        'Vuelven los valores de referencia de 2000 kcal.');
    if (!ok) return;
    await Repo.instance.resetTargets();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas diarias'),
        actions: [
          IconButton(
              tooltip: 'Restablecer',
              icon: const Icon(Icons.restart_alt),
              onPressed: _reset),
        ],
      ),
      body: ListView(
        children: [
          for (final n in _nutrients)
            ListTile(
              title: Text(n.nameEs),
              subtitle: Text((_targets[n.code]?.upper ?? false)
                  ? 'Límite máximo'
                  : 'Meta mínima'),
              trailing: Text(_targets[n.code] == null
                  ? '-'
                  : '${fmtNum(_targets[n.code]!.value, decimals: 1)} ${n.unit}'),
              onTap: () => _edit(n),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ alimentos propios

class CustomFoodsPage extends StatefulWidget {
  const CustomFoodsPage({super.key});

  @override
  State<CustomFoodsPage> createState() => _CustomFoodsPageState();
}

class _CustomFoodsPageState extends State<CustomFoodsPage> {
  List<Food> _foods = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await Repo.instance.customFoods();
    if (mounted) setState(() => _foods = f);
  }

  Future<void> _open([Food? f]) async {
    await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => CustomFoodPage(food: f)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alimentos propios')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _open(),
        child: const Icon(Icons.add),
      ),
      body: _foods.isEmpty
          ? const EmptyState(
              icon: Icons.egg_outlined,
              text: 'Cargá productos con su tabla nutricional para usarlos en recetas.',
            )
          : ListView.builder(
              itemCount: _foods.length,
              itemBuilder: (context, i) {
                final f = _foods[i];
                return ListTile(
                  title: Text(f.name),
                  subtitle: Text(f.category),
                  onTap: () => _open(f),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await confirm(context, 'Borrar alimento',
                          'Las recetas que lo usan quedan con ese ingrediente sin datos nutricionales.');
                      if (!ok) return;
                      await Repo.instance.deleteCustomFood(f.id);
                      _load();
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ------------------------------------------------------------------ respaldo

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<void> _export(BuildContext context) async {
    final json = await Repo.instance.exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      showSnack(context,
          'Respaldo copiado (${fmtNum(json.length / 1024, decimals: 0)} KB). Pegalo en un mail o en Drive.');
    }
  }

  Future<void> _import(BuildContext context) async {
    final ctrl = TextEditingController();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    ctrl.text = clip?.text ?? '';
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar respaldo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Reemplaza todas tus recetas, plan, despensa y ajustes.'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'Pegá acá el texto del respaldo',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Importar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.instance.importJson(ctrl.text);
      if (context.mounted) showSnack(context, 'Respaldo importado.');
    } catch (e) {
      if (context.mounted) showSnack(context, 'No se pudo importar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Tus datos viven solo en este teléfono. Exportá un respaldo antes de cambiar de teléfono o desinstalar.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _export(context),
            icon: const Icon(Icons.upload),
            label: const Text('Exportar (copiar al portapapeles)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _import(context),
            icon: const Icon(Icons.download),
            label: const Text('Importar desde texto'),
          ),
        ],
      ),
    );
  }
}
