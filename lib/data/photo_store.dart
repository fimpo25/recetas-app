import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Fotos de recetas guardadas como archivos junto a la base de datos.
class PhotoStore {
  PhotoStore._();

  static String? _dir;

  /// Se llama al abrir la base (antes de mostrar cualquier foto).
  static Future<void> init() async {
    final d = p.join(await getDatabasesPath(), 'photos');
    await Directory(d).create(recursive: true);
    _dir = d;
  }

  /// Archivo de una foto, o null si no hay nombre o todavía no se inicializó.
  static File? file(String? name) {
    if (name == null || name.isEmpty || _dir == null) return null;
    return File(p.join(_dir!, name));
  }

  static Future<String> save(int recipeId, List<int> bytes) async {
    final name = 'r${recipeId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(p.join(_dir!, name)).writeAsBytes(bytes, flush: true);
    return name;
  }

  static Future<List<int>?> read(String name) async {
    final f = file(name);
    if (f == null || !await f.exists()) return null;
    return f.readAsBytes();
  }

  static Future<void> delete(String? name) async {
    final f = file(name);
    if (f != null && await f.exists()) await f.delete();
  }
}
