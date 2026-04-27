import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DBService {
  static final DBService instance = DBService._init();
  static Database? _database;

  DBService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('lumina_music.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // Tracks table
    await db.execute('''
      CREATE TABLE music_tracks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist_id TEXT NOT NULL,
        artist_name TEXT NOT NULL,
        album_id TEXT,
        album_name TEXT,
        album_artwork_url TEXT,
        duration_ms INTEGER,
        track_number INTEGER,
        disc_number INTEGER,
        release_date TEXT,
        popularity INTEGER,
        genres TEXT,
        musicbrainz_id TEXT,
        isrc TEXT,
        external_urls TEXT
      )
    ''');

    // Albums table
    await db.execute('''
      CREATE TABLE music_albums (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        artist_id TEXT NOT NULL,
        artist_name TEXT NOT NULL,
        artwork_url TEXT,
        release_date TEXT,
        total_tracks INTEGER,
        genres TEXT,
        musicbrainz_id TEXT,
        type TEXT
      )
    ''');

    // Artists table
    await db.execute('''
      CREATE TABLE music_artists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        image_url TEXT,
        bio TEXT,
        genres TEXT,
        popularity INTEGER,
        musicbrainz_id TEXT,
        tags TEXT
      )
    ''');

    // Matches table
    await db.execute('''
      CREATE TABLE music_matches (
        track_id TEXT PRIMARY KEY,
        local_file_path TEXT,
        remote_source_url TEXT,
        confidence TEXT NOT NULL,
        matched_by TEXT,
        matched_at TEXT NOT NULL,
        is_manual INTEGER NOT NULL
      )
    ''');

    // Artwork cache
    await db.execute('''
      CREATE TABLE music_artwork_cache (
        url TEXT PRIMARY KEY,
        local_path TEXT NOT NULL,
        cached_at TEXT NOT NULL,
        size INTEGER
      )
    ''');

    // Provider Credentials
    await db.execute('''
      CREATE TABLE music_provider_credentials (
        provider TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Scan jobs
    await db.execute('''
      CREATE TABLE music_scan_jobs (
        id TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        status TEXT NOT NULL,
        last_run TEXT,
        error TEXT
      )
    ''');
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
