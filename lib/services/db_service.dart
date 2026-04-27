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
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createLibraryTables(db);
    }
  }

  Future _createDB(Database db, int version) async {
    await _createMusicTables(db);
    if (version >= 2) {
      await _createLibraryTables(db);
    }
  }

  Future _createMusicTables(Database db) async {
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

  Future _createLibraryTables(Database db) async {
    await db.execute('''
      CREATE TABLE media_library (
        id TEXT PRIMARY KEY,
        file_path TEXT,
        file_name TEXT,
        thumbnail_path TEXT,
        duration INTEGER,
        added_at TEXT,
        updated_at TEXT,
        is_favorite INTEGER,
        content_type INTEGER,
        media_kind INTEGER,
        is_watched INTEGER,
        play_count INTEGER,
        resolution TEXT,
        language TEXT,
        metadata_id TEXT,
        movie_title TEXT,
        show_title TEXT,
        episode_title TEXT,
        synopsis TEXT,
        poster_url TEXT,
        backdrop_url TEXT,
        thumbnail_url TEXT,
        season_poster_url TEXT,
        trailer_url TEXT,
        release_date TEXT,
        release_year INTEGER,
        rating REAL,
        genres TEXT,
        cast_list TEXT,
        directors TEXT,
        writers TEXT,
        artist TEXT,
        album TEXT,
        track_number INTEGER,
        watch_progress REAL,
        last_played TEXT,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_status (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT
      )
    ''');
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
