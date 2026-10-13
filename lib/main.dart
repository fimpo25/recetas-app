import 'package:flutter/material.dart';

import 'data/db.dart';
import 'features/nutrition/nutrition_page.dart';
import 'features/plan/plan_page.dart';
import 'features/recipes/recipes_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/update_page.dart';
import 'features/shopping/shopping_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RecetasApp());
}

class RecetasApp extends StatelessWidget {
  const RecetasApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4CAF50),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Recetas',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(colorScheme: scheme, useMaterial3: true),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4CAF50)),
        useMaterial3: true,
      ),
      home: const _Boot(),
    );
  }
}

class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late final Future<void> _open = AppDb.instance.open();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _open,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No se pudo abrir la base de datos:\n${snap.error}'),
              ),
            ),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const HomeShell();
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) autoCheckForUpdate(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const RecipesPage(),
      const PlanPage(),
      const ShoppingPage(),
      const NutritionPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Recetas'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Plan'),
          NavigationDestination(
              icon: Icon(Icons.shopping_cart_outlined),
              selectedIcon: Icon(Icons.shopping_cart),
              label: 'Compras'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Nutrición'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Ajustes'),
        ],
      ),
    );
  }
}
