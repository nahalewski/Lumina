import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subtitle_model.dart';
import '../providers/subtitle_provider.dart';

/// Netflix-style floating subtitle overlay
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SubtitleProvider>(
      builder: (context, provider, _) {
        final subtitle = provider.currentSubtitle;
        final options = provider.displayOptions;

        if (subtitle == null) return const SizedBox.shrink();

        bool showEN = options.showEnglish;
        bool showJA = options.showJapanese;

        String displayEN = subtitle.englishText;
        String displayJA = subtitle.japaneseText;

        // In live mode, we often only have Japanese.
        // If English is empty, we show Japanese in the primary slot.
        if (provider.mode == SubtitleMode.live && displayEN.isEmpty && displayJA.isNotEmpty) {
          displayEN = displayJA;
          displayJA = '';
        } else if (showEN && displayEN.isEmpty && displayJA.isNotEmpty) {
          // Fallback for preprocessed mode
          displayEN = displayJA;
        }

        // Determine visibility based on content and toggles
        // If we moved Japanese to English slot for live mode, it should obey the English toggle
        // OR we can make it obey "any" toggle. Let's make it smarter.
        final hasEnglish = showEN && displayEN.isNotEmpty;
        final hasJapanese = showJA && displayJA.isNotEmpty;

        if (!hasEnglish && !hasJapanese && !(provider.mode == SubtitleMode.live && displayEN.isNotEmpty)) {
           return const SizedBox.shrink();
        }
        
        // Final fallback for live mode: if everything is hidden but we have text, show it
        String finalEN = hasEnglish ? displayEN : (provider.mode == SubtitleMode.live && !showJA ? displayEN : '');
        String finalJA = hasJapanese ? displayJA : '';

        if (finalEN.isEmpty && finalJA.isEmpty) return const SizedBox.shrink();

        // Find the index of the current subtitle for editing
        final currentIndex = provider.subtitles.indexOf(subtitle);

        return Positioned(
          bottom: options.verticalOffset,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onLongPress: currentIndex >= 0
                  ? () => _showEditDialog(context, provider, currentIndex, subtitle)
                  : null,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Color(options.backgroundColorValue),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (finalEN.isNotEmpty)
                          Text(
                            finalEN,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(options.colorValue),
                              fontSize: options.fontSize,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Inter',
                              height: 1.3,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 2)),
                              ],
                            ),
                          ),
                        if (finalJA.isNotEmpty && finalEN.isNotEmpty) const SizedBox(height: 6),
                        if (finalJA.isNotEmpty)
                          Text(
                            finalJA,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(options.colorValue).withValues(alpha: 0.7),
                              fontSize: options.fontSize * 0.8,
                              fontWeight: FontWeight.w400,
                              fontFamily: 'Inter',
                              height: 1.3,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 2)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    // Phase 3: Star Button (Top Right)
                    Positioned(
                      top: -16,
                      right: -16,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (provider.isStarred(subtitle)) {
                              provider.unstarSubtitle(subtitle);
                            } else {
                              provider.starSubtitle(subtitle);
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              provider.isStarred(subtitle) ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: provider.isStarred(subtitle) ? const Color(0xFFFFD700) : Colors.white38,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Phase 3: A-B Repeat Button (Top Left)
                    Positioned(
                      top: -16,
                      left: -16,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => provider.toggleABRepeat(),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: provider.isABRepeatEnabled 
                                  ? const Color(0xFF0A84FF).withValues(alpha: 0.3)
                                  : Colors.black.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.repeat_one_rounded,
                              color: provider.isABRepeatEnabled ? const Color(0xFF0A84FF) : Colors.white38,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Edit indicator (#2): subtle pencil icon when long-press available
                    if (currentIndex >= 0)
                      Positioned(
                        bottom: -12,
                        right: -8,
                        child: Icon(
                          Icons.edit_rounded,
                          color: Colors.white.withValues(alpha: 0.2),
                          size: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Show edit dialog for subtitle correction (#2)
  void _showEditDialog(BuildContext context, SubtitleProvider provider, int index, SubtitleEntry entry) {
    final japaneseController = TextEditingController(text: entry.japaneseText);
    final englishController = TextEditingController(text: entry.englishText);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.edit_rounded, color: Color(0xFFAAC7FF), size: 20),
            const SizedBox(width: 8),
            const Text(
              'Edit Subtitle',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Japanese text field
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('日本語', style: TextStyle(color: Color(0xFFE9B3FF), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const Spacer(),
                        Text('${entry.startTime.inSeconds}s', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: japaneseController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 3,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Japanese text...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // English text field
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ENGLISH', style: TextStyle(color: Color(0xFF42E355), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: englishController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 3,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'English translation...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () {
              provider.editSubtitle(
                index,
                japaneseText: japaneseController.text,
                englishText: englishController.text,
              );
              provider.saveEditedSrt();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Subtitle updated and saved'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Color(0xFF0A84FF),
                ),
              );
            },
            child: const Text('Save', style: TextStyle(color: Color(0xFFAAC7FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// Learning mode: tap subtitle to see phrase breakdown
class LearningSubtitleOverlay extends StatelessWidget {
  const LearningSubtitleOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SubtitleProvider>(
      builder: (context, provider, _) {
        final subtitle = provider.currentSubtitle;
        if (subtitle == null) return const SizedBox.shrink();

        return Positioned(
          bottom: 120,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () => _showPhraseDetail(context, subtitle.japaneseText, subtitle.englishText),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFAAC7FF).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      subtitle.englishText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: provider.displayOptions.fontSize,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle.japaneseText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFE9B3FF),
                        fontSize: provider.displayOptions.fontSize * 0.85,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(
                      Icons.touch_app_rounded,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPhraseDetail(BuildContext context, String japanese, String english) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F1F21),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Phrase Breakdown',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Manrope',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '日本語',
                    style: TextStyle(
                      color: const Color(0xFFAAC7FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    japanese,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ENGLISH',
                    style: TextStyle(
                      color: const Color(0xFF42E355),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    english,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Provider.of<SubtitleProvider>(context, listen: false)
                      .savePhrase(japanese, english);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Phrase saved to flashcards!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.save_rounded, color: Color(0xFFAAC7FF)),
                label: const Text(
                  'Save to Flashcards',
                  style: TextStyle(color: Color(0xFFAAC7FF)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A subtle flashcard that pops up when a vocabulary match is detected
class VocabularyMatchOverlay extends StatelessWidget {
  const VocabularyMatchOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SubtitleProvider>(
      builder: (context, provider, _) {
        final current = provider.currentSubtitle;
        if (current == null) return const SizedBox.shrink();

        final match = provider.findVocabularyMatch(current);
        if (match == null) return const SizedBox.shrink();

        return Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 400),
              tween: Tween(begin: 0.0, end: 1.0),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFE9B3FF).withValues(alpha: 0.9),
                      const Color(0xFFB39DDB).withValues(alpha: 0.9),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE9B3FF).withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          match.japaneseText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Inter',
                          ),
                        ),
                        Text(
                          match.englishText,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.star_rounded, color: Colors.white70, size: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
