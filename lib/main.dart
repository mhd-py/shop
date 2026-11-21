import 'package:material_ui/material_ui.dart';

import 'core/module_screen.dart';
import 'data/database.dart';
import 'data/product_repository.dart';
import 'features/inventory/inventory_screen.dart';
import 'data/settings_repository.dart';

void main() {
  runApp(ShopApp(database: AppDatabase()));
}

class ShopApp extends StatelessWidget {
  const ShopApp({super.key, required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shop Manager',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      ),
      home: MainNavigation(database: database),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key, required this.database});
  final AppDatabase database;

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int selectedIndex = 0;

  late final List<Widget> pages = [
    const ModuleScreen(
      icon: Icons.receipt_long,
      title: 'Billing',
      subtitle: 'Create bills and accept payments',
    ),
    InventoryScreen(
      repo: ProductRepository(widget.database),
      settings: SettingsRepository(widget.database),
    ),
    const ModuleScreen(
      icon: Icons.menu_book,
      title: 'Khata',
      subtitle: 'Customer credit accounts',
    ),
    const ModuleScreen(
      icon: Icons.settings,
      title: 'Settings',
      subtitle: 'Export data and manage bills',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => setState(() => selectedIndex = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Billing'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Inventory'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Khata'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}
