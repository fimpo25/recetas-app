import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../common/widgets.dart';
import '../../data/repo.dart';
import '../../domain/recipe_pack.dart';

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
        'las que tengan el mismo nombre que una existente se saltean.',
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
  try {
    final (added, skipped) = await Repo.instance.importRecipePack(text);
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showSnack(
        context,
        skipped == 0
            ? 'Se agregaron $added recetas.'
            : 'Se agregaron $added recetas ($skipped ya estaban).',
      );
    }
    return added > 0;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showSnack(context, 'No se pudo importar: $e');
    }
    return false;
  }
}
