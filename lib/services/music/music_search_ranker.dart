import '../../models/music_models.dart';

enum SearchMode {
  exact,
  smart,
  broad,
}

class SearchScore {
  double titleScore = 0;
  double artistScore = 0;
  double albumScore = 0;
  double durationScore = 0;
  double idMatchScore = 0;
  double popularityBonus = 0;
  double providerBonus = 0;
  List<String> penalties = [];
  double total = 0;
  List<String> matchReasons = [];
}

class MusicSearchRanker {
  static String normalize(String input, {String? searchQuery}) {
    if (input.isEmpty) return '';
    
    String text = input.toLowerCase();
    
    // Normalize special characters and apostrophes
    text = text
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('´', "'")
        .replaceAll('`', "'")
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    // Remove featuring annotations unless searched
    if (searchQuery == null || !_containsAny(searchQuery, ['feat', 'ft', 'featuring'])) {
      text = text.replaceAll('feat.', '').replaceAll('ft.', '').replaceAll('featuring', '');
    }
    
    // Remove edition tags unless searched
    final editionTags = ['remaster', 'deluxe', 'explicit', 'radio edit', 'single version', 'remastered'];
    for (final tag in editionTags) {
      if (searchQuery == null || !searchQuery.contains(tag)) {
        text = text.replaceAll(tag, '');
      }
    }
    
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  
  static bool _containsAny(String text, List<String> terms) {
    final lower = text.toLowerCase();
    return terms.any((term) => lower.contains(term));
  }
  
  static double fuzzyMatchScore(String a, String b) {
    final normA = normalize(a);
    final normB = normalize(b);
    
    if (normA == normB) return 1.0;
    if (normA.contains(normB) || normB.contains(normA)) return 0.8;
    
    final wordsA = normA.split(' ').toSet();
    final wordsB = normB.split(' ').toSet();
    
    final intersection = wordsA.intersection(wordsB).length;
    final union = wordsA.union(wordsB).length;
    
    return union == 0 ? 0 : intersection / union;
  }
  
  static SearchScore calculateScore(MusicTrack track, String searchQuery) {
    final score = SearchScore();
    final normQuery = normalize(searchQuery);
    
    final normTitle = normalize(track.title, searchQuery: searchQuery);
    final normArtist = normalize(track.artistName, searchQuery: searchQuery);
    final normAlbum = normalize(track.albumName ?? '', searchQuery: searchQuery);
    
    // Exact matches
    if (normTitle == normQuery) {
      score.titleScore = 50;
      score.matchReasons.add('Exact title match');
    } else {
      score.titleScore = fuzzyMatchScore(track.title, searchQuery) * 25;
      if (score.titleScore > 15) {
        score.matchReasons.add('Title matches');
      }
    }
    
    if (normArtist == normQuery) {
      score.artistScore = 40;
      score.matchReasons.add('Exact artist match');
    } else {
      score.artistScore = fuzzyMatchScore(track.artistName, searchQuery) * 25;
      if (score.artistScore > 15) {
        score.matchReasons.add('Artist matches');
      }
    }
    
    if (normAlbum == normQuery) {
      score.albumScore = 30;
      score.matchReasons.add('Exact album match');
    } else {
      score.albumScore = fuzzyMatchScore(track.albumName ?? '', searchQuery) * 20;
    }
    
    // ID matching bonus
    if (track.isrc != null && track.isrc!.isNotEmpty) {
      score.idMatchScore += 10;
    }
    
    if (track.musicBrainzId != null && track.musicBrainzId!.isNotEmpty) {
      score.idMatchScore += 20;
    }
    
    // Popularity bonus (max 10)
    score.popularityBonus = (track.popularity ?? 0).toDouble() / 10.0;
    
    score.providerBonus = 0;
    
    // Penalties
    final lowerTitle = track.title.toLowerCase();
    
    if (!_containsAny(searchQuery, ['remix', 'live', 'acoustic', 'remaster'])) {
      if (_containsAny(lowerTitle, ['remix', 'live', 'acoustic', 'remaster', 'version'])) {
        score.penalties.add('Remix/Version penalized');
        score.total -= 20;
      }
    }
    
    if (!_containsAny(searchQuery, ['karaoke', 'instrumental', 'cover'])) {
      if (_containsAny(lowerTitle, ['karaoke', 'instrumental', 'cover', 'tribute'])) {
        score.penalties.add('Karaoke/Instrumental penalized');
        score.total -= 30;
      }
    }
    
    // Calculate final total
    score.total = score.titleScore +
        score.artistScore +
        score.albumScore +
        score.durationScore +
        score.idMatchScore +
        score.popularityBonus +
        score.providerBonus +
        score.total; // includes penalties
    
    return score;
  }
  
  static List<ScoredTrack> rankResults(List<MusicTrack> tracks, String query, SearchMode mode) {
    final scored = tracks.map((track) {
      final score = calculateScore(track, query);
      return ScoredTrack(track, score);
    }).toList();
    
    // Sort descending by score
    scored.sort((a, b) => b.score.total.compareTo(a.score.total));
    
    // Filter based on search mode
    switch (mode) {
      case SearchMode.exact:
        return scored.where((s) => s.confidence >= 0.85).toList();
      case SearchMode.smart:
        return scored.where((s) => s.confidence >= 0.60).toList();
      case SearchMode.broad:
        return scored;
    }
  }
}

class ScoredTrack {
  final MusicTrack track;
  final SearchScore score;
  
  ScoredTrack(this.track, this.score);
  
  double get confidence => score.total.clamp(0, 100) / 100;
  
  Map<String, dynamic> toDebugMap() {
    return {
      'titleScore': score.titleScore,
      'artistScore': score.artistScore,
      'albumScore': score.albumScore,
      'durationScore': score.durationScore,
      'idMatchScore': score.idMatchScore,
      'popularityBonus': score.popularityBonus,
      'providerBonus': score.providerBonus,
      'penalties': score.penalties,
      'total': score.total,
      'confidence': confidence,
    };
  }
}