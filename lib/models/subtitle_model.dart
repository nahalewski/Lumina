/// Represents a single subtitle entry with timing and text
class SubtitleEntry {
  final int index;
  final Duration startTime;
  final Duration endTime;
  final String japaneseText;
  final String englishText;

  SubtitleEntry({
    required this.index,
    required this.startTime,
    required this.endTime,
    required this.japaneseText,
    required this.englishText,
  });

  String get displayText => englishText.isNotEmpty ? englishText : japaneseText;

  /// Convert to SRT format string
  String toSrt() {
    final start = _formatTime(startTime);
    final end = _formatTime(endTime);
    return '$index\n$start --> $end\n$japaneseText\n$englishText\n\n';
  }

  static String _formatTime(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final millis = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds,$millis';
  }

  /// Parse SRT format string
  static List<SubtitleEntry> fromSrt(String srtContent) {
    final entries = <SubtitleEntry>[];
    final blocks = srtContent.trim().split('\n\n');
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 3) continue;
      final index = int.tryParse(lines[0]) ?? 0;
      final timeParts = lines[1].split(' --> ');
      if (timeParts.length != 2) continue;
      final start = _parseTime(timeParts[0]);
      final end = _parseTime(timeParts[1]);
      final textLines = lines.sublist(2);
      final japanese = textLines.isNotEmpty ? textLines[0].trim() : '';
      final english = textLines.length > 1 ? textLines[1].trim() : '';
      entries.add(SubtitleEntry(
        index: index,
        startTime: start,
        endTime: end,
        japaneseText: japanese,
        englishText: english,
      ));
    }
    return entries;
  }

  static Duration _parseTime(String time) {
    final parts = time.replaceAll(',', '.').split(':');
    if (parts.length != 3) return Duration.zero;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final secParts = parts[2].split('.');
    final seconds = int.tryParse(secParts[0]) ?? 0;
    final millis = secParts.length > 1 ? int.tryParse(secParts[1].padRight(3, '0').substring(0, 3)) ?? 0 : 0;
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }
}

/// Subtitle mode enum
enum SubtitleMode {
  preprocessed,
  live,
}

/// Subtitle display options
class SubtitleDisplayOptions {
  bool showJapanese;
  bool showEnglish;
  double delaySeconds;
  double fontSize;
  bool alwaysOnTop;
  int colorValue; // ARGB
  int backgroundColorValue; // ARGB
  double verticalOffset; // pixels from bottom

  SubtitleDisplayOptions({
    this.showJapanese = false,
    this.showEnglish = true,
    this.delaySeconds = 0.0,
    this.fontSize = 18.0,
    this.alwaysOnTop = false,
    this.colorValue = 0xFFFFFFFF, // White
    this.backgroundColorValue = 0xB3000000, // Black 70%
    this.verticalOffset = 120.0,
  });
}
