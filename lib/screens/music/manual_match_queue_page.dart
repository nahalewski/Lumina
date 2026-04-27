import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/music_provider.dart';
import '../../providers/media_provider.dart';
import '../../models/music_models.dart';
import '../../models/media_model.dart';

class ManualMatchQueuePage extends StatefulWidget {
  const ManualMatchQueuePage({super.key});

  @override
  State<ManualMatchQueuePage> createState() => _ManualMatchQueuePageState();
}

class _ManualMatchQueuePageState extends State<ManualMatchQueuePage> {
  List<MediaFile> _unmatchedFiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUnmatched();
  }

  Future<void> _loadUnmatched() async {
    final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    
    final unmatched = <MediaFile>[];
    for (final file in mediaProvider.mediaFiles) {
      if (file.mediaKind == MediaKind.audio) {
        // This is a bit inefficient but for a queue it's okay
        // In a real app we'd have a 'isMatched' flag in the local DB
        unmatched.add(file);
      }
    }

    if (mounted) {
      setState(() {
        _unmatchedFiles = unmatched;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF131315),
      appBar: AppBar(
        title: const Text('Manual Match Queue', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _unmatchedFiles.isEmpty
              ? const Center(child: Text('All files are matched!', style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _unmatchedFiles.length,
                  itemBuilder: (context, index) {
                    final file = _unmatchedFiles[index];
                    return _UnmatchedFileTile(file: file);
                  },
                ),
    );
  }
}

class _UnmatchedFileTile extends StatelessWidget {
  final MediaFile file;

  const _UnmatchedFileTile({required this.file});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        leading: const Icon(Icons.music_note_rounded, color: Color(0xFFAAC7FF)),
        title: Text(file.fileName, style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(file.filePath, style: const TextStyle(color: Colors.white38, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: ElevatedButton(
          onPressed: () {
            // TODO: Open search dialog to find metadata for this file
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFAAC7FF).withValues(alpha: 0.1),
            foregroundColor: const Color(0xFFAAC7FF),
          ),
          child: const Text('MATCH'),
        ),
      ),
    );
  }
}
