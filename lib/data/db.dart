import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Abre la base nutricional (precargada, solo lectura) y la base de usuario.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  late Database nut;
  late Database user;
  bool _opened = false;

  Future<void> open() async {
    if (_opened) return;
    final dir = await getDatabasesPath();
    await Directory(dir).create(recursive: true);

    // Copia la base nutricional del APK si falta o cambió.
    final nutPath = p.join(dir, 'nutrition.db');
    final data = await rootBundle.load('assets/db/nutrition.db');
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final f = File(nutPath);
    if (!await f.exists() || await f.length() != bytes.length) {
      await f.writeAsBytes(bytes, flush: true);
    }
    nut = await openDatabase(nutPath, readOnly: true);

    user = await openDatabase(
      p.join(dir, 'user.db'),
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createUserSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              "ALTER TABLE recipe ADD COLUMN category TEXT NOT NULL DEFAULT 'Otra'");
        }
      },
    );
    _opened = true;
  }

  static Future<void> _createUserSchema(Database db) async {
    final stmts = <String>[
      '''CREATE TABLE custom_food (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'Almacén',
        density REAL NOT NULL DEFAULT 1.0,
        edible REAL NOT NULL DEFAULT 1.0,
        search_text TEXT NOT NULL DEFAULT ''
      )''',
      '''CREATE TABLE custom_food_nutrient (
        food_id INTEGER NOT NULL REFERENCES custom_food(id) ON DELETE CASCADE,
        nutrient_id INTEGER NOT NULL,
        per_100g REAL NOT NULL,
        PRIMARY KEY (food_id, nutrient_id)
      )''',
      '''CREATE TABLE custom_portion (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        food_id INTEGER NOT NULL,
        label TEXT NOT NULL,
        grams REAL NOT NULL
      )''',
      '''CREATE TABLE recipe (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        servings REAL NOT NULL,
        prep_min INTEGER,
        cook_min INTEGER,
        instructions TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT 'Otra',
        created_at INTEGER,
        updated_at INTEGER
      )''',
      '''CREATE TABLE recipe_ingredient (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL REFERENCES recipe(id) ON DELETE CASCADE,
        food_id INTEGER NOT NULL,
        food_name TEXT NOT NULL,
        qty REAL NOT NULL,
        unit TEXT NOT NULL,
        grams REAL NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0
      )''',
      '''CREATE TABLE plan_entry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        week_start TEXT NOT NULL,
        day INTEGER NOT NULL,
        slot TEXT NOT NULL,
        recipe_id INTEGER NOT NULL REFERENCES recipe(id) ON DELETE CASCADE,
        servings REAL NOT NULL DEFAULT 1
      )''',
      'CREATE INDEX idx_plan_week ON plan_entry(week_start)',
      '''CREATE TABLE nutrient_target (
        code TEXT PRIMARY KEY,
        daily_target REAL NOT NULL,
        is_upper INTEGER NOT NULL DEFAULT 0
      )''',
      '''CREATE TABLE pantry_item (
        food_id INTEGER PRIMARY KEY,
        food_name TEXT NOT NULL,
        category TEXT NOT NULL,
        grams REAL NOT NULL
      )''',
      '''CREATE TABLE setting (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''',
    ];
    for (final s in stmts) {
      await db.execute(s);
    }
  }
}
