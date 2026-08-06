import 'package:flutter/material.dart';

import 'screens/pos_screen.dart';
import 'sync/sync_engine.dart';

/// SIMS AI mobile — offline-first POS.
///
/// The local SQLite database is the primary data store; every mutation is
/// appended to the outbox and the [SyncEngine] pushes it (and pulls server
/// deltas) whenever connectivity returns. The app is fully usable with the
/// network off — that is the point (dissertation §4.6).
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SyncEngine.instance.start(); // listens for connectivity, syncs opportunistically
  runApp(const SimsApp());
}

class SimsApp extends StatelessWidget {
  const SimsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF2A78D6);
    return MaterialApp(
      title: 'SIMS AI',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: brand),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const PosScreen(),
    );
  }
}
