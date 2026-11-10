/// Opens the app's local SQLite database. Everything is stored on the device,
/// so the app works with no Internet connection.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

class AppDatabase {
  AppDatabase._();

  /// Opens (and on first run creates) the database file.
  /// Pass [path] to use a different file, e.g. in tests.
  static Future<Database> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'cricket_scorer.db');
    return openDatabase(
      dbPath,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final statement in schemaStatements) {
          await db.execute(statement);
        }
      },
    );
  }
}
