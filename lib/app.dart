import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import 'application/setup_controller.dart';
import 'data/sqlite_repositories.dart';
import 'domain/repositories.dart';
import 'ui/home_screen.dart';

/// Wires the layers together: SQLite repositories at the bottom, controllers
/// above them, screens on top. Screens only see the interfaces and controllers.
class CricketScorerApp extends StatelessWidget {
  const CricketScorerApp({super.key, required this.database});

  final Database database;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<TeamRepository>.value(value: SqliteTeamRepository(database)),
        Provider<PlayerRepository>.value(
            value: SqlitePlayerRepository(database)),
        Provider<MatchRepository>.value(value: SqliteMatchRepository(database)),
        ChangeNotifierProvider<SetupController>(
          create: (context) => SetupController(
            context.read<TeamRepository>(),
            context.read<PlayerRepository>(),
            context.read<MatchRepository>(),
          )..load(),
        ),
      ],
      child: MaterialApp(
        title: 'Cricket Scorer',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
