import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/media_model.dart';
import 'db_service.dart';
import 'package:sqflite/sqflite.dart';

class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  final DBService _dbService = DBService.instance;

  /// Fetch changes from the server and apply them to the local database.
  Future<void> performSync({
    required String serverUrl,
    required String token,
    required String deviceId,
  }) async {
    final db = await _dbService.database;
    
    // 1. Get last sync time
    final lastSync = await _getLastSyncTime(db);
    
    debugPrint('[Sync] Performing incremental sync since $lastSync');

    try {
      final uri = Uri.parse('$serverUrl/api/library/changes').replace(
        queryParameters: {
          'since': lastSync,
          if (token.isNotEmpty) 'token': token,
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'x-lumina-device-id': deviceId,
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List updated = data['updated'] ?? [];
        final List deleted = data['deleted'] ?? [];
        final String serverTime = data['serverTime'];

        if (updated.isNotEmpty || deleted.isNotEmpty) {
          await db.transaction((txn) async {
            // Apply updates
            for (final json in updated) {
              final media = MediaFile.fromJson(json);
              await _upsertMedia(txn, media);
            }

            // Apply deletions
            for (final id in deleted) {
              await txn.delete(
                'media_library',
                where: 'id = ?',
                whereArgs: [id],
              );
            }
          });
          debugPrint('[Sync] Applied ${updated.length} updates and ${deleted.length} deletions');
        }

        // Update last sync time
        await _setLastSyncTime(db, serverTime);
      } else {
        debugPrint('[Sync] Failed to fetch changes: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[Sync] Error during sync: $e');
    }
  }

  /// Load all cached media from the local database.
  Future<List<MediaFile>> loadCachedLibrary() async {
    final db = await _dbService.database;
    final List<Map<String, dynamic>> maps = await db.query('media_library', where: 'is_deleted = 0');
    
    return List.generate(maps.length, (i) {
      return _mapToMediaFile(maps[i]);
    });
  }

  /// Clear the local media library cache.
  Future<void> clearCache() async {
    final db = await _dbService.database;
    await db.delete('media_library');
    await db.delete('sync_status', where: 'key = ?', whereArgs: ['last_sync_time']);
    debugPrint('[Sync] Local cache cleared');
  }

  Future<void> _upsertMedia(Transaction txn, MediaFile media) async {
    final row = _mediaFileToMap(media);
    await txn.insert(
      'media_library',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> _getLastSyncTime(Database db) async {
    final List<Map<String, dynamic>> maps = await db.query(
      'sync_status',
      where: 'key = ?',
      whereArgs: ['last_sync_time'],
    );
    if (maps.isEmpty) return '1970-01-01T00:00:00Z';
    return maps.first['value'];
  }

  Future<void> _setLastSyncTime(Database db, String time) async {
    await db.insert(
      'sync_status',
      {
        'key': 'last_sync_time',
        'value': time,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, dynamic> _mediaFileToMap(MediaFile media) {
    return {
      'id': media.id,
      'file_path': media.filePath,
      'file_name': media.fileName,
      'thumbnail_path': media.thumbnailPath,
      'duration': media.duration.inMilliseconds,
      'added_at': media.addedAt.toIso8601String(),
      'updated_at': media.updatedAt.toIso8601String(),
      'is_favorite': media.isFavorite ? 1 : 0,
      'content_type': media.contentType.index,
      'media_kind': media.mediaKind.index,
      'is_watched': media.isWatched ? 1 : 0,
      'play_count': media.playCount,
      'resolution': media.resolution,
      'language': media.language,
      'metadata_id': media.metadataId,
      'movie_title': media.movieTitle,
      'show_title': media.showTitle,
      'episode_title': media.episodeTitle,
      'synopsis': media.synopsis,
      'poster_url': media.posterUrl,
      'backdrop_url': media.backdropUrl,
      'thumbnail_url': media.thumbnailUrl,
      'season_poster_url': media.seasonPosterUrl,
      'trailer_url': media.trailerUrl,
      'release_date': media.releaseDate,
      'release_year': media.releaseYear,
      'rating': media.rating,
      'genres': jsonEncode(media.genres),
      'cast_list': jsonEncode(media.cast),
      'directors': jsonEncode(media.directors),
      'writers': jsonEncode(media.writers),
      'artist': media.artist,
      'album': media.album,
      'track_number': media.trackNumber,
      'watch_progress': media.watchProgress,
      'last_played': media.lastPlayed?.toIso8601String(),
      'is_deleted': media.isDeleted ? 1 : 0,
    };
  }

  MediaFile _mapToMediaFile(Map<String, dynamic> map) {
    return MediaFile(
      id: map['id'],
      filePath: map['file_path'],
      fileName: map['file_name'],
      thumbnailPath: map['thumbnail_path'],
      duration: Duration(milliseconds: map['duration'] ?? 0),
      addedAt: DateTime.tryParse(map['added_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] ?? '') ?? DateTime.now(),
      isFavorite: map['is_favorite'] == 1,
      contentType: ContentType.values[map['content_type'] ?? 0],
      mediaKind: MediaKind.values[map['media_kind'] ?? 0],
      isWatched: map['is_watched'] == 1,
      playCount: map['play_count'] ?? 0,
      resolution: map['resolution'],
      language: map['language'],
      metadataId: map['metadata_id'],
      movieTitle: map['movie_title'],
      showTitle: map['show_title'],
      episodeTitle: map['episode_title'],
      synopsis: map['synopsis'],
      posterUrl: map['poster_url'],
      backdropUrl: map['backdrop_url'],
      thumbnailUrl: map['thumbnail_url'],
      seasonPosterUrl: map['season_poster_url'],
      trailerUrl: map['trailer_url'],
      releaseDate: map['release_date'],
      releaseYear: map['release_year'],
      rating: map['rating'],
      genres: _decodeList(map['genres']),
      cast: _decodeList(map['cast_list']),
      directors: _decodeList(map['directors']),
      writers: _decodeList(map['writers']),
      artist: map['artist'],
      album: map['album'],
      trackNumber: map['track_number'],
      watchProgress: map['watch_progress'] ?? 0.0,
      lastPlayed: DateTime.tryParse(map['last_played'] ?? ''),
      isDeleted: map['is_deleted'] == 1,
    );
  }

  List<String> _decodeList(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final List decoded = jsonDecode(json);
      return decoded.cast<String>();
    } catch (_) {
      return [];
    }
  }
}
