import 'package:flutter/material.dart';

import 'app.dart';
import 'data/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Everything is stored in a local SQLite file: no Internet needed.
  final database = await AppDatabase.open();
  runApp(CricketScorerApp(database: database));
}
