import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/recipe_pack.dart';
import '../../domain/text.dart';

/// Elegir un recetario .json del teléfono y agregar sus recetas.
/// Devuelve true si se agregó al menos una receta.
Future<bool> importRecipePackFlow(BuildContext context) async {
  final FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
  } catch (e) {
    if (context.mounted) showSnack(context, 'No se pudo abrir el selector: $e');
    return false;
  }
  if (picked == null || picked.files.isEmpty) return false;
  final file = picked.files.single;

  String text;
  try {
    if (file.bytes != null) {
      text = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      text = await File(file.path!).readAsString();
    } else {
      throw const FormatException('No se pudo leer el archivo');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'No se pudo leer el archivo: $e');
    return false;
  }

  final RecipePack pack;
  try {
    pack = parseRecipePack(text);
  } catch (_) {
    if (context.mounted) {
      showSnack(context,
          'Ese archivo no es un recetario. Elegí el .json de recetas (no un respaldo).');
    }
    return false;
  }
  if (!context.mounted) return false;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Importar recetario'),
      content: Text(
        '${pack.title}\n\n'
        '${pack.recipes.length} recetas. Se agregan a las tuyas sin borrar nada; '
        'las que tengan el mismo nombre que una existente se saltean.'
        '${pack.plan.isEmpty ? '' : '\n\nIncluye un plan de ${pack.planDays} días: después elegís desde qué día cargarlo.'}',
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
  if (ok != true || !context.mounted) return false;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Importando recetas…')),
        ],
      ),
    ),
  );
  final (int, int) res;
  try {
    res = await Repo.instance.importRecipePack(text);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showSnack(context, 'No se pudo importar: $e');
    }
    return false;
  }
  final (added, skipped) = res;
  if (!context.mounted) return added > 0;
  Navigator.of(context, rootNavigator: true).pop();
  final msg = skipped == 0
      ? 'Se agregaron $added recetas.'
      : 'Se agregaron $added recetas ($skipped ya estaban).';
  if (pack.plan.isEmpty) {
    showSnack(context, msg);
    return added > 0;
  }
  String? planMsg;
  try {
    planMsg = await _importPlan(context, pack);
  } catch (e) {
    planMsg = 'No se pudo cargar el plan: $e';
  }
  if (context.mounted) {
    showSnack(context, planMsg == null ? msg : '$msg $planMsg');
  }
  return true;
}

/// Pregunta el primer día y si reemplazar lo cargado; devuelve el mensaje
/// para mostrar o null si se canceló.
Future<String?> _importPlan(BuildContext context, RecipePack pack) async {
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final start = await showDatePicker(
    context: context,
    initialDate: tomorrow,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 2),
    helpText: 'Primer día del plan (${pack.planDays} días)',
  );
  if (start == null || !context.mounted) return null;
  final replace = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cargar plan'),
      content: Text(
          'Se cargan ${pack.plan.length} comidas en ${pack.planDays} días desde el '
          '${fmtShortDate(start)}. ¿Qué hago con lo que ya tengas planificado esos días?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Agregar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reemplazar')),
      ],
    ),
  );
  if (replace == null) return null;
  final (added, missing) =
      await Repo.instance.importPackPlan(pack, start, replace: replace);
  var out = missing == 0
      ? 'Plan cargado: $added comidas.'
      : 'Plan cargado: $added comidas ($missing sin receta).';
  if (pack.targets.isNotEmpty && context.mounted) {
    final kcal = pack.targets['energy_kcal'];
    final prot = pack.targets['protein_g'];
    final desc = [
      if (kcal != null) '${fmtNum(kcal, decimals: 0)} kcal',
      if (prot != null) '${fmtNum(prot, decimals: 0)} g de proteína',
    ].join(' y ');
    final set = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Metas diarias'),
        content: Text('El plan está armado para $desc por día. '
            '¿Uso esos valores como tus metas diarias?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí')),
        ],
      ),
    );
    if (set == true) {
      for (final e in pack.targets.entries) {
        await Repo.instance.setTarget(e.key, e.value, false);
      }
      out += ' Metas actualizadas.';
    }
  }
  return out;
}
