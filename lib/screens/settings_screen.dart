import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/media_provider.dart';
import '../providers/iptv_provider.dart';
import '../models/media_model.dart';
import '../services/download_service.dart';
import '../services/iptv_service.dart';

/// Settings screen for application configuration
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: Text(
            'Settings',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            children: [
              _buildSection(
                context,
                'Appearance',
                [
                  // Global player bar removed per request
                ],
              ),
              _buildSection(
                context,
                'AI Translation (Ollama)',
                [
                  _buildToggle(
                    context,
                    'Qwen Translation',
                    'Translate Japanese transcription to English using your local Qwen model.',
                    Icons.auto_awesome_rounded,
                    Provider.of<MediaProvider>(context).settings.useOllamaTranslation,
                    (value) => Provider.of<MediaProvider>(context, listen: false).toggleOllamaTranslation(value),
                  ),
                  if (Provider.of<MediaProvider>(context).settings.useOllamaTranslation)
                    _buildModelSelector(context),
                  if (Provider.of<MediaProvider>(context).settings.useOllamaTranslation)
                    _buildProfileSelector(context),
                ],
              ),
              _buildSection(
                context,
                'Playback',
                [
                  _buildToggle(
                    context,
                    'Auto-start Transcription',
                    'Automatically begin transcribing video audio when playback starts.',
                    Icons.closed_caption_rounded,
                    Provider.of<MediaProvider>(context).settings.autoProcessNewMedia,
                    (value) => Provider.of<MediaProvider>(context, listen: false).toggleAutoProcess(value),
                  ),
                  _buildToggle(
                    context,
                    'Library Intro Video',
                    'Play a short intro before library videos (requires intro.mp4).',
                    Icons.movie_filter_rounded,
                    Provider.of<MediaProvider>(context).settings.enableIntro,
                    (value) => Provider.of<MediaProvider>(context, listen: false).setEnableIntro(value),
                  ),
                  _buildToggle(
                    context,
                    'Background Menu Music',
                    'Play immersive music while browsing the library and menus.',
                    Icons.music_note_rounded,
                    Provider.of<MediaProvider>(context).settings.enableMenuMusic,
                    (value) => Provider.of<MediaProvider>(context, listen: false).setEnableMenuMusic(value),
                  ),
                ],
              ),
              _buildSection(
                context,
                'Library Folders',
                [
                  _LibraryFoldersTile(),
                ],
              ),
              _buildSection(
                context,
                'Artwork & Metadata',
                [
                  _ArtworkScannerTile(),
                ],
              ),
              _buildSection(
                context,
                'Downloads',
                [
                  _buildDownloadLocation(context),
                ],
              ),
              _buildSection(
                context,
                'Media Server',
                [
                  _MediaServerTile(),
                ],
              ),
              _buildSection(
                context,
                'IPTV Credentials',
                [
                  _IptvCredentialsTile(),
                ],
              ),
              _buildSection(
                context,
                'Model Management',

                [
                  _buildModelManager(context),
                ],
              ),
              _buildSection(
                context,
                'About',
                [
                  _buildInfoRow('Version', '1.0.0'),
                  _buildInfoRow('Engine', 'whisper.cpp (v1.8.4)'),
                  _buildInfoRow('Developer', 'Lumina Labs'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: const Color(0xFFAAC7FF).withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildToggle(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF0A84FF), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFFAAC7FF),
            activeTrackColor: const Color(0xFF0A84FF).withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelector(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);
    final models = provider.ollamaModels;
    final selectedModel = provider.settings.ollamaModel;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE9B3FF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.psychology_rounded, color: Color(0xFFE9B3FF), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ollama Model',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  models.isEmpty ? 'No models found' : 'Select a model for translation',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                ),
              ],
            ),
          ),
          if (models.isNotEmpty)
            DropdownButton<String>(
              value: models.contains(selectedModel) ? selectedModel : models.first,
              dropdownColor: const Color(0xFF1E1E22),
              underline: Container(),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
              items: models.map((m) => DropdownMenuItem(
                value: m,
                child: Text(m, style: const TextStyle(fontSize: 13, color: Colors.white)),
              )).toList(),
              onChanged: (value) {
                if (value != null) provider.setOllamaModel(value);
              },
            ),
          if (models.isEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF0A84FF), size: 20),
              onPressed: () => provider.fetchOllamaModels(),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileSelector(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);
    final selectedProfile = provider.settings.translationProfile;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9F0A).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.theater_comedy_rounded, color: Color(0xFFFF9F0A), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Translation Profile',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Switch between Standard (Anime) and Adult (Hentai) modes.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                ),
              ],
            ),
          ),
          DropdownButton<TranslationProfile>(
            value: selectedProfile,
            dropdownColor: const Color(0xFF1E1E22),
            underline: Container(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
            items: [
              DropdownMenuItem(
                value: TranslationProfile.standard,
                child: const Text('Standard (Anime)', style: TextStyle(fontSize: 13, color: Colors.white)),
              ),
              DropdownMenuItem(
                value: TranslationProfile.adult,
                child: const Text('Adult (Hentai)', style: TextStyle(fontSize: 13, color: Colors.white)),
              ),
            ],
            onChanged: (TranslationProfile? value) {
              if (value != null) provider.setTranslationProfile(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadLocation(BuildContext context) {
    return DownloadLocationTile();
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelManager(BuildContext context) {
    final mediaProvider = Provider.of<MediaProvider>(context);
    const models = [
      {'name': 'ggml-tiny.bin', 'label': 'Tiny (Low Latency)', 'size': '75 MB'},
      {'name': 'ggml-base.bin', 'label': 'Base (Balanced)', 'size': '145 MB'},
      {'name': 'ggml-small.bin', 'label': 'Small (Recommended)', 'size': '465 MB'},
      {'name': 'ggml-medium.bin', 'label': 'Medium (Accurate)', 'size': '1.5 GB'},
      {'name': 'ggml-large-v3.bin', 'label': 'Large v3 (Studio Quality)', 'size': '2.9 GB'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: models.map((model) {
          final name = model['name']!;
          final isInstalled = mediaProvider.installedModels[name] ?? false;
          final progress = mediaProvider.downloadProgress[name];
          final isDownloading = progress != null;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Icon(
              isInstalled ? Icons.check_circle_rounded : Icons.download_for_offline_rounded,
              color: isInstalled ? const Color(0xFF42E355) : Colors.white24,
            ),
            title: Text(
              model['label']!,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: isDownloading
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF0A84FF)),
                      borderRadius: BorderRadius.circular(2),
                      minHeight: 4,
                    ),
                  )
                : Text(
                    isInstalled ? 'Installed — ${model['size']}' : 'Not installed — ${model['size']}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                  ),
            trailing: isInstalled
                ? IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                    onPressed: () => mediaProvider.deleteWhisperModel(name),
                    tooltip: 'Delete Model',
                  )
                : isDownloading
                    ? Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(color: Color(0xFF0A84FF), fontSize: 12, fontWeight: FontWeight.bold),
                      )
                    : IconButton(
                        icon: const Icon(Icons.download_rounded, color: Color(0xFF0A84FF), size: 20),
                        onPressed: () => mediaProvider.downloadWhisperModel(name),
                        tooltip: 'Download Model',
                      ),
          );
        }).toList(),
      ),
    );
  }
}

/// Tile for IPTV credentials configuration
class _IptvCredentialsTile extends StatefulWidget {
  @override
  State<_IptvCredentialsTile> createState() => _IptvCredentialsTileState();
}

class _IptvCredentialsTileState extends State<_IptvCredentialsTile> {
  late TextEditingController _serverController;
  late TextEditingController _portController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<IptvProvider>(context, listen: false);
    _serverController = TextEditingController(text: provider.server);
    _portController = TextEditingController(text: provider.port);
    _usernameController = TextEditingController(text: provider.username);
    _passwordController = TextEditingController(text: provider.password);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _save() {
    final provider = Provider.of<IptvProvider>(context, listen: false);
    provider.updateCredentials(
      server: _serverController.text.trim(),
      port: _portController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('IPTV credentials saved — reloading...'),
        backgroundColor: Color(0xFF0A84FF),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _resetDefaults() {
    _serverController.text = IptvService.defaultServer;
    _portController.text = IptvService.defaultPort;
    _usernameController.text = IptvService.defaultUsername;
    _passwordController.text = IptvService.defaultPassword;
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<IptvProvider>(context);
    final isLoading = provider.isLoading;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9F0A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.live_tv_rounded, color: Color(0xFFFF9F0A), size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'IPTV Provider',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'M3U credentials for live TV, movies & series',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Server field
          _buildField('Server', _serverController, hint: 'primevip.day'),
          const SizedBox(height: 8),

          // Port field
          _buildField('Port', _portController, hint: '443', keyboardType: TextInputType.number),
          const SizedBox(height: 8),

          // Username field
          _buildField('Username', _usernameController, hint: '549310740'),
          const SizedBox(height: 8),

          // Password field
          _buildPasswordField(),
          const SizedBox(height: 16),

          // Status
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF9F0A))),
                  SizedBox(width: 8),
                  Text('Loading IPTV content...', style: TextStyle(color: Color(0xFFFF9F0A), fontSize: 11)),
                ],
              ),
            ),

          if (provider.lastError != null && !isLoading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Text(
                provider.lastError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ),

          if (provider.hasLoaded && !isLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Loaded ${provider.liveChannels.length} channels, ${provider.movies.length} movies, ${provider.tvShows.length} shows',
                style: const TextStyle(color: Color(0xFF42E355), fontSize: 11),
              ),
            ),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save & Reload', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF9F0A),
                    side: BorderSide(color: const Color(0xFFFF9F0A).withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _resetDefaults,
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Reset', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white54,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saveDebugLog,
              icon: const Icon(Icons.bug_report_rounded, size: 16),
              label: const Text('Save Debug Log to Desktop', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDebugLog() async {
    final service = IptvService();
    service.updateCredentials(
      server: _serverController.text.trim(),
      port: _portController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fetching debug log...'),
        backgroundColor: Color(0xFFFF9F0A),
        duration: Duration(seconds: 1),
      ),
    );
    final path = await service.saveDebugLog();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Debug log saved to: $path'),
          backgroundColor: const Color(0xFF42E355),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }


  Widget _buildField(String label, TextEditingController controller, {String? hint, TextInputType? keyboardType}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 13),
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: _passwordController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        obscureText: !_showPassword,
        decoration: InputDecoration(
          hintText: '97364759',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 13),
          labelText: 'Password',
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: Icon(
              _showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              size: 16,
              color: Colors.white38,
            ),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
      ),
    );
  }
}


/// Tile for scanning artwork and metadata for the library
class _ArtworkScannerTile extends StatefulWidget {
  @override
  State<_ArtworkScannerTile> createState() => _ArtworkScannerTileState();
}

class _ArtworkScannerTileState extends State<_ArtworkScannerTile> {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);
    final isScanning = provider.isScanningArtwork;
    final scanned = provider.artworkScanned;
    final total = provider.artworkTotal;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE9B3FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_stories_rounded, color: Color(0xFFE9B3FF), size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Artwork Scanner',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Auto-detect media type and fetch cover art from TMDB, Jikan, and iTunes',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isScanning) ...[
            // Progress bar
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(
                value: total > 0 ? scanned / total : null,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation(Color(0xFFE9B3FF)),
                borderRadius: BorderRadius.circular(2),
                minHeight: 4,
              ),
            ),
            Text(
              'Scanning $scanned of $total files...',
              style: const TextStyle(color: Color(0xFFE9B3FF), fontSize: 11),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => provider.scanArtwork(),
                icon: const Icon(Icons.search_rounded, size: 16),
                label: Text(
                  total > 0 ? 'Scan All Media ($total files)' : 'Scan Library',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE9B3FF),
                  side: BorderSide(color: const Color(0xFFE9B3FF).withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scrapes cover art, descriptions, and ratings from:\n'
              '• TMDB — Movies & TV Shows\n'
              '• Jikan (MyAnimeList) — Anime\n'
              '• iTunes — Music',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}



/// Tile for configuring the download location


/// Tile for configuring the download location
class DownloadLocationTile extends StatefulWidget {

  @override
  State<DownloadLocationTile> createState() => _DownloadLocationTileState();
}

class _DownloadLocationTileState extends State<DownloadLocationTile> {
  final DownloadService _downloadService = DownloadService();
  String _downloadPath = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPath();
  }

  Future<void> _loadPath() async {
    await _downloadService.initialize();
    if (mounted) {
      setState(() {
        _downloadPath = _downloadService.downloadDirectory;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDownloadLocation() async {
    final selectedDirectory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Download Location',
      initialDirectory: _downloadPath,
    );

    if (selectedDirectory != null) {
      // Verify the directory exists
      final dir = Directory(selectedDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      await _downloadService.saveDownloadDirectory(selectedDirectory);
      if (mounted) {
        setState(() {
          _downloadPath = selectedDirectory;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download location set to: $selectedDirectory'),
            backgroundColor: const Color(0xFF0A84FF),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _resetToDefault() async {
    final defaultPath = await _downloadService.getDefaultDownloadDirectory();
    await _downloadService.saveDownloadDirectory(defaultPath);
    if (mounted) {
      setState(() {
        _downloadPath = defaultPath;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download location reset to default'),
          backgroundColor: Color(0xFF0A84FF),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openDownloadFolder() async {
    final dir = Directory(_downloadPath);
    if (await dir.exists()) {
      await Process.run('open', [dir.path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF42E355).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.download_rounded, color: Color(0xFF42E355), size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Download Location',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Choose where downloaded files are saved',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Current path display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _downloadPath,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open_rounded, size: 16, color: Colors.white38),
                  onPressed: _openDownloadFolder,
                  tooltip: 'Open Folder',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDownloadLocation,
                  icon: const Icon(Icons.folder_rounded, size: 16),
                  label: const Text('Change Location', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0A84FF),
                    side: BorderSide(color: const Color(0xFF0A84FF).withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _resetToDefault,
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Reset', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white54,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _downloadService.dispose();
    super.dispose();
  }
}

/// Tile for managing library watch folders
class _LibraryFoldersTile extends StatefulWidget {
  @override
  State<_LibraryFoldersTile> createState() => _LibraryFoldersTileState();
}

class _LibraryFoldersTileState extends State<_LibraryFoldersTile> {
  List<String> _folders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final provider = Provider.of<MediaProvider>(context, listen: false);
    final folders = await provider.getLibraryFolders();
    if (mounted) {
      setState(() {
        _folders = folders;
        _isLoading = false;
      });
    }
  }

  Future<void> _addFolder() async {
    final selectedDirectory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Library Folder',
    );

    if (selectedDirectory != null) {
      final provider = Provider.of<MediaProvider>(context, listen: false);
      await provider.addLibraryFolder(selectedDirectory);
      await _loadFolders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added library folder: $selectedDirectory'),
            backgroundColor: const Color(0xFF0A84FF),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _removeFolder(String folder) async {
    final provider = Provider.of<MediaProvider>(context, listen: false);
    provider.removeLibraryFolder(folder);
    await _loadFolders();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed library folder'),
          backgroundColor: const Color(0xFF0A84FF),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _scanFolders() async {
    final provider = Provider.of<MediaProvider>(context, listen: false);
    provider.scanLibraryFolders();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Library scan complete'),
          backgroundColor: Color(0xFF0A84FF),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9F0A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_special_rounded, color: Color(0xFFFF9F0A), size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Watch Folders',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Folders scanned for media files',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Scan button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _scanFolders,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 14, color: Color(0xFFAAC7FF)),
                        SizedBox(width: 4),
                        Text('Scan', style: TextStyle(color: Color(0xFFAAC7FF), fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_folders.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Center(
                child: Text(
                  'No folders added yet',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                ),
              ),
            )
          else
            ...List.generate(_folders.length, (index) {
              final folder = _folders[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_rounded, size: 16, color: Colors.white.withValues(alpha: 0.4)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        folder,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _removeFolder(folder),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded, size: 16, color: Colors.white.withValues(alpha: 0.3)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addFolder,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Folder', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0A84FF),
                side: BorderSide(color: const Color(0xFF0A84FF).withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile for displaying Media Server status and logs
class _MediaServerTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (context, provider, _) {
        final isRunning = provider.isMediaServerRunning;
        final error = provider.mediaServerError;
        final localUrl = provider.mediaServerLocalUrl;
        final logs = provider.mediaServerLogs;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.lan_rounded, color: Color(0xFF0A84FF), size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Server Status',
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusBadge(isRunning, error != null),
                          ],
                        ),
                        Text(
                          isRunning ? 'Local: $localUrl' : 'Server is starting automatically...',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                  ),
                ),
              
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9F0A).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.cloud_rounded, color: Color(0xFFFF9F0A), size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Remote Access (Tunnel)',
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusBadge(provider.isTunnelRunning, provider.tunnelStatus.contains('Error')),
                          ],
                        ),
                        Text(
                          provider.isTunnelRunning ? provider.tunnelUrl : provider.tunnelStatus.isEmpty ? 'Connecting...' : provider.tunnelStatus,
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'TUNNEL DEBUG LOGS',
                style: TextStyle(
                  color: Colors.white30,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: provider.tunnelLogs.isEmpty
                    ? const Center(
                        child: Text(
                          'Waiting for tunnel data...',
                          style: TextStyle(color: Colors.white24, fontSize: 11),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: provider.tunnelLogs.length,
                        reverse: true,
                        itemBuilder: (context, index) {
                          final log = provider.tunnelLogs[provider.tunnelLogs.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              log,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontFamily: 'Courier',
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              const Text(
                'LOCAL SERVER DEBUG LOGS',
                style: TextStyle(
                  color: Colors.white30,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: logs.isEmpty
                    ? const Center(
                        child: Text(
                          'No logs yet...',
                          style: TextStyle(color: Colors.white24, fontSize: 11),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: logs.length,
                        reverse: true,
                        itemBuilder: (context, index) {
                          final log = logs[logs.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              log,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontFamily: 'Courier',
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(bool isRunning, bool hasError) {
    String text = 'STOPPED';
    Color color = Colors.grey;
    
    if (hasError) {
      text = 'ERROR';
      color = Colors.redAccent;
    } else if (isRunning) {
      text = 'RUNNING';
      color = const Color(0xFF42E355);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

