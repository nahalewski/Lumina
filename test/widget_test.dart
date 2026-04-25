import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_media/models/media_model.dart';
import 'package:lumina_media/providers/media_provider.dart';
import 'package:lumina_media/providers/subtitle_provider.dart';
import 'package:lumina_media/screens/library_screen.dart';
import 'package:provider/provider.dart';

void main() {
  group('Plex-style TV filename parsing', () {
    test('detects SxxExx filenames', () {
      final parsed = parseEpisodeInfoFromFileName('Naruto.S02E04.mkv');

      expect(parsed.showTitle, 'Naruto');
      expect(parsed.season, 2);
      expect(parsed.episode, 4);
    });

    test('detects 1x01 episode titles', () {
      final parsed = parseEpisodeInfoFromFileName(
        'Show Name - 1x01 - Episode Title.mp4',
      );

      expect(parsed.showTitle, 'Show Name');
      expect(parsed.season, 1);
      expect(parsed.episode, 1);
      expect(parsed.episodeTitle, 'Episode Title');
    });

    test('detects Season 1 Episode 1 filenames', () {
      final media = MediaFile(
        id: '1',
        filePath: '/media/Show Name Season 1 Episode 1.mkv',
        fileName: 'Show Name Season 1 Episode 1.mkv',
      );

      expect(media.mediaKind, MediaKind.tv);
      expect(media.parsedShowTitle, 'Show Name');
      expect(media.parsedSeason, 1);
      expect(media.parsedEpisode, 1);
    });
  });

  testWidgets('Library screen exposes Movies and TV Shows sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MediaProvider()),
          ChangeNotifierProvider(create: (_) => SubtitleProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: LibraryScreen())),
      ),
    );

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('TV Shows'), findsOneWidget);
    expect(find.text('No movies yet'), findsOneWidget);
  });
}
