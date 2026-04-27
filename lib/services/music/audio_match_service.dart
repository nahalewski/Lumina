import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/music_models.dart';
import '../../models/media_model.dart';
import '../db_service.dart';
import 'package:sqflite/sqflite.dart';

class AudioMatchService {
  final DBService _db = DBService.instance;

  /// Find a local file match for a metadata track
  Future<MusicMatch?> findMatch(MusicTrack track, List<MediaFile> localLibrary) async {
    // 1. Check existing matches in DB
    final existingMatch = await _getStoredMatch(track.id);
    if (existingMatch != null) return existingMatch;

    // 2. Try to find a high-confidence match in local library
    for (final file in localLibrary) {
      if (file.mediaKind != MediaKind.audio) continue;

      final confidence = _calculateMatchConfidence(track, file);
      if (confidence == MatchConfidence.high) {
        final match = MusicMatch(
          trackId: track.id,
          localFilePath: file.filePath,
          confidence: MatchConfidence.high,
          matchedBy: 'LocalHeuristic',
          matchedAt: DateTime.now(),
        );
        await _storeMatch(match);
        return match;
      }
    }

    return null;
  }

  MatchConfidence _calculateMatchConfidence(MusicTrack track, MediaFile file) {
    final trackTitle = track.title.toLowerCase();
    final fileTitle = file.title.toLowerCase();
    final trackArtist = track.artistName.toLowerCase();
    final fileArtist = file.artist?.toLowerCase() ?? '';

    // Exact match
    if (trackTitle == fileTitle && (trackArtist == fileArtist || fileArtist.isEmpty)) {
      return MatchConfidence.high;
    }

    // Fuzzy match (simplified)
    if (trackTitle.contains(fileTitle) || fileTitle.contains(trackTitle)) {
      if (trackArtist == fileArtist || fileArtist.isEmpty) {
        return MatchConfidence.medium;
      }
    }

    return MatchConfidence.none;
  }

  Future<MusicMatch?> _getStoredMatch(String trackId) async {
    final db = await _db.database;
    final results = await db.query(
      'music_matches',
      where: 'track_id = ?',
      whereArgs: [trackId],
    );

    if (results.isNotEmpty) {
      final row = results.first;
      return MusicMatch(
        trackId: row['track_id'] as String,
        localFilePath: row['local_file_path'] as String?,
        remoteSourceUrl: row['remote_source_url'] as String?,
        confidence: MatchConfidence.values.firstWhere(
          (e) => e.name == row['confidence'],
          orElse: () => MatchConfidence.none,
        ),
        matchedBy: row['matched_by'] as String?,
        matchedAt: DateTime.parse(row['matched_at'] as String),
        isManual: (row['is_manual'] as int) == 1,
      );
    }
    return null;
  }

  Future<void> _storeMatch(MusicMatch match) async {
    final db = await _db.database;
    await db.insert(
      'music_matches',
      {
        'track_id': match.trackId,
        'local_file_path': match.localFilePath,
        'remote_source_url': match.remoteSourceUrl,
        'confidence': match.confidence.name,
        'matched_by': match.matchedBy,
        'matched_at': match.matchedAt.toIso8601String(),
        'is_manual': match.isManual ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
