import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/subtitle_provider.dart';
import '../models/subtitle_model.dart';

/// Screen to view and manage starred vocabulary phrases
class VocabularyScreen extends StatelessWidget {
  const VocabularyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SubtitleProvider>(
      builder: (context, provider, _) {
        final starred = provider.starredSubtitles;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(32, 24, 32, 16),
              child: Text(
                'Vocabulary List',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            if (starred.isEmpty)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_outline_rounded, size: 64, color: Colors.white10),
                      SizedBox(height: 16),
                      Text(
                        'No starred phrases yet.',
                        style: TextStyle(color: Colors.white38, fontSize: 16),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Star subtitles in the player to save them here.',
                        style: TextStyle(color: Colors.white24, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  itemCount: starred.length,
                  itemBuilder: (context, index) {
                    final entry = starred[index];
                    return _buildVocabCard(context, provider, entry);
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildVocabCard(BuildContext context, SubtitleProvider provider, SubtitleEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.englishText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.japaneseText,
                    style: const TextStyle(
                      color: Color(0xFFAAC7FF),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Timestamp: ${entry.startTime.toString().split('.').first}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.star_rounded, color: Color(0xFFFFD700)),
              onPressed: () => provider.unstarSubtitle(entry),
            ),
          ],
        ),
      ),
    );
  }
}
