import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/knowledge_page.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  Database? _database;

  static Future<void> configureForCurrentPlatform() async {
    if (Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    final directory = await getApplicationSupportDirectory();
    final databasePath = path.join(directory.path, 'confluence_knowledge_base.db');
    _database = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pages (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            space_key TEXT NOT NULL,
            body_html TEXT NOT NULL,
            version INTEGER NOT NULL,
            updated_at TEXT,
            page_path TEXT NOT NULL,
            web_url TEXT NOT NULL,
            sync_run TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX pages_title_idx ON pages(title)');
        await db.execute('CREATE INDEX pages_space_idx ON pages(space_key)');
      },
    );
    return _database!;
  }

  Future<List<KnowledgePage>> searchPages(String query) async {
    final db = await database;
    final terms = query.trim();
    final rows = terms.isEmpty
        ? await db.query('pages', orderBy: 'title COLLATE NOCASE ASC')
        : await db.query(
            'pages',
            where: '''
              title LIKE ? COLLATE NOCASE
              OR space_key LIKE ? COLLATE NOCASE
              OR page_path LIKE ? COLLATE NOCASE
              OR body_html LIKE ? COLLATE NOCASE
            ''',
            whereArgs: List<String>.filled(4, '%$terms%'),
            orderBy: 'title COLLATE NOCASE ASC',
          );
    return rows.map(KnowledgePage.fromRow).toList(growable: false);
  }

  Future<void> replaceAllPages(List<KnowledgePage> pages, String syncRun) async {
    final db = await database;
    await db.transaction((transaction) async {
      final batch = transaction.batch();
      for (final page in pages) {
        batch.insert('pages', page.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      // This is executed only after every page has been received successfully.
      await transaction.delete('pages', where: 'sync_run != ?', whereArgs: <Object?>[syncRun]);
    });
  }

  Future<int> countPages() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM pages')) ?? 0;
  }
}
