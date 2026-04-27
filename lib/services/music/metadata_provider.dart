import '../../models/music_models.dart';

abstract class MusicMetadataProvider {
  String get providerName;
  bool get isEnabled;

  Future<List<MusicTrack>> searchTracks(String query, {int limit = 20});
  Future<List<MusicAlbum>> searchAlbums(String query, {int limit = 20});
  Future<List<MusicArtist>> searchArtists(String query, {int limit = 20});
  
  Future<MusicTrack?> getTrackDetails(String id);
  Future<MusicAlbum?> getAlbumDetails(String id);
  Future<MusicArtist?> getArtistDetails(String id);
  
  Future<List<MusicTrack>> getAlbumTracks(String albumId);
  Future<List<MusicAlbum>> getArtistAlbums(String artistId);
}
