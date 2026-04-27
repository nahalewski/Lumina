import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/media_provider.dart';
import '../providers/iptv_provider.dart';
import '../providers/music_provider.dart';
import '../models/media_model.dart';
import 'music/manual_match_queue_page.dart';
import '../widgets/side_nav_bar.dart';
import '../services/download_service.dart';
import '../services/iptv_service.dart';
import '../services/ebook_manga_metadata_service.dart';
import '../providers/remote_media_provider.dart';

/// Settings screen for application configuration
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    final provider = Provider.of<MediaProvider>(context);

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
                'Playback',
                [
                  if (!isAndroid)
                    _buildToggle(
                      context,
                      'Auto-start Transcription',
                      'Automatically begin transcribing video audio when playback starts.',
                      Icons.closed_caption_rounded,
                      provider.settings.autoProcessNewMedia,
                      (value) =>
                          Provider.of<MediaProvider>(context, listen: false)
                              .toggleAutoProcess(value),
                    ),
                  if (isAndroid)
                    _buildToggle(
                      context,
                      'Keep screen on',
                      'Prevent display from turning off during video playback.',
                      Icons.screen_lock_portrait_rounded,
                      provider.settings.keepScreenOn,
                      (value) =>
                          Provider.of<MediaProvider>(context, listen: false)
                              .setKeepScreenOn(value),
                    ),
                  _buildToggle(
                    context,
                    'Library Intro Video',
                    'Play a short intro before library videos (requires intro.mp4).',
                    Icons.movie_filter_rounded,
                    provider.settings.enableIntro,
                    (value) =>
                        Provider.of<MediaProvider>(context, listen: false)
                            .setEnableIntro(value),
                  ),
                  _buildToggle(
                    context,
                    'Background Menu Music',
                    'Play immersive music while browsing the library and menus.',
                    Icons.music_note_rounded,
                    provider.settings.enableMenuMusic,
                    (value) =>
                        Provider.of<MediaProvider>(context, listen: false)
                            .setEnableMenuMusic(value),
                  ),
                ],
              ),
              if (!isAndroid)
                _buildSection(
                  context,
                  'Artwork & Metadata',
                  [
                    _ArtworkScannerTile(),
                  ],
                ),
                _buildSection(
                  context,
                  'Cache',
                  [
                    _CacheStorageTile(),
                  ],
                ),
                _buildSection(
                  context,
                  'Storage',
                  [
                    _StorageSettingsTile(),
                  ],
                ),
                _buildSection(
                  context,
                  'E-book & Manga Metadata APIs',
                  [
                    _DocumentMetadataApiTile(),
                  ],
                ),
                _buildSection(
                  context,
                  'Library Organization',
                  [
                    _DocumentOrganizerTile(type: DocumentLibraryType.manga),
                    _DocumentOrganizerTile(type: DocumentLibraryType.comics),
                    _DocumentOrganizerTile(type: DocumentLibraryType.ebooks),
                  ],
                ),
                _buildSection(
                  context,
                  'Appearance',
                  [
                    _ParticleThemeTile(),
                  ],
                ),
                _buildSection(
                  context,
                  'Game Art API',
                  [
                    _GameArtApiTile(),
                  ],
                ),
                _buildSection(
                  context,
                  'Media Server & Network',
                  [
                    _MediaServerTile(),
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
                  'Dependencies',
                  [
                    _DependencyManagementTile(),
                  ],
                ),
              _MusicProvidersSection(),
              if (isAndroid)
                _buildSection(
                  context,
                  'Server Connection',
                  [
                    _buildServerAddressField(context),
                    _buildServerTokenField(context),
                  ],
                ),
              _buildSection(
                context,
                'IPTV Credentials',
                [
                  _IptvCredentialsTile(),
                ],
              ),
              if (!isAndroid)
                _buildSection(
                  context,
                  'IPTV Proxy Settings',
                  [
                    _IptvProxySettingsTile(),
                  ],
                ),
              if (!isAndroid)
                _buildSection(
                  context,
                  'About',
                  [
                  _buildInfoRow('Version', '1.0.0'),
                  if (!isAndroid)
                    _buildInfoRow('Engine', 'whisper.cpp (v1.8.4)'),
                  _buildInfoRow('Developer', 'Lumina Labs'),
                ],
              ),
              const SizedBox(height: 24),
              if (!isAndroid) _ApiScrapersSection(),
              _buildSection(
                context,
                'Secret Menu',
                [
                  _SecretMenuTile(),
                ],
              ),
              if (!isAndroid) const _PairedDevicesSection(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
      BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: const Color(0xFFAAC7FF).withOpacity(0.8),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
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
              color: const Color(0xFF0A84FF).withOpacity(0.1),
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
                    color: Colors.white.withOpacity(0.4),
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
            activeTrackColor: const Color(0xFF0A84FF).withOpacity(0.4),
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
              color: const Color(0xFFE9B3FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.psychology_rounded,
                color: Color(0xFFE9B3FF), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ollama Model',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  models.isEmpty
                      ? 'No models found'
                      : 'Select a model for translation',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4), fontSize: 12),
                ),
              ],
            ),
          ),
          if (models.isNotEmpty)
            DropdownButton<String>(
              value:
                  models.contains(selectedModel) ? selectedModel : models.first,
              dropdownColor: const Color(0xFF1E1E22),
              underline: Container(),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white54),
              items: models
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white)),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) provider.setOllamaModel(value);
              },
            ),
          if (models.isEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: Color(0xFF0A84FF), size: 20),
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
              color: const Color(0xFFFF9F0A).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.theater_comedy_rounded,
                color: Color(0xFFFF9F0A), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Translation Profile',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  'Switch between Standard (Anime) and Adult (Hentai) modes.',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4), fontSize: 12),
                ),
              ],
            ),
          ),
          DropdownButton<TranslationProfile>(
            value: selectedProfile,
            dropdownColor: const Color(0xFF1E1E22),
            underline: Container(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white54),
            items: [
              DropdownMenuItem(
                value: TranslationProfile.standard,
                child: const Text('Standard (Anime)',
                    style: TextStyle(fontSize: 13, color: Colors.white)),
              ),
              DropdownMenuItem(
                value: TranslationProfile.adult,
                child: const Text('Adult (Hentai)',
                    style: TextStyle(fontSize: 13, color: Colors.white)),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
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
      {
        'name': 'ggml-small.bin',
        'label': 'Small (Recommended)',
        'size': '465 MB'
      },
      {
        'name': 'ggml-medium.bin',
        'label': 'Medium (Accurate)',
        'size': '1.5 GB'
      },
      {
        'name': 'ggml-large-v3.bin',
        'label': 'Large v3 (Studio Quality)',
        'size': '2.9 GB'
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _buildToggle(
            context,
            'Qwen Translation',
            'Translate Japanese transcription to English using your local Qwen model.',
            Icons.auto_awesome_rounded,
            mediaProvider.settings.useOllamaTranslation,
            (value) => mediaProvider.toggleOllamaTranslation(value),
          ),
          if (mediaProvider.settings.useOllamaTranslation)
            _buildModelSelector(context),
          if (mediaProvider.settings.useOllamaTranslation)
            _buildProfileSelector(context),
          Divider(color: Colors.white.withOpacity(0.06), height: 16),
          ...models.map((model) {
            final name = model['name']!;
            final isInstalled = mediaProvider.installedModels[name] ?? false;
            final progress = mediaProvider.downloadProgress[name];
            final isDownloading = progress != null;

            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Icon(
                isInstalled
                    ? Icons.check_circle_rounded
                    : Icons.download_for_offline_rounded,
                color: isInstalled ? const Color(0xFF42E355) : Colors.white24,
              ),
              title: Text(
                model['label']!,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
              ),
              subtitle: isDownloading
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white10,
                        valueColor:
                            const AlwaysStoppedAnimation(Color(0xFF0A84FF)),
                        borderRadius: BorderRadius.circular(2),
                        minHeight: 4,
                      ),
                    )
                  : Text(
                      isInstalled
                          ? 'Installed — ${model['size']}'
                          : 'Not installed — ${model['size']}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12),
                    ),
              trailing: isInstalled
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.white38, size: 20),
                      onPressed: () => mediaProvider.deleteWhisperModel(name),
                      tooltip: 'Delete Model',
                    )
                  : isDownloading
                      ? Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                              color: Color(0xFF0A84FF),
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        )
                      : IconButton(
                          icon: const Icon(Icons.download_rounded,
                              color: Color(0xFF0A84FF), size: 20),
                          onPressed: () =>
                              mediaProvider.downloadWhisperModel(name),
                          tooltip: 'Download Model',
                        ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildServerAddressField(BuildContext context) {
    final remoteProvider = Provider.of<RemoteMediaProvider>(context);
    final controller =
        TextEditingController(text: remoteProvider.customBaseUrl ?? '');

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
                  color: const Color(0xFF0A84FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lan_rounded,
                    color: Color(0xFF0A84FF), size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lumina Server Address',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Manual IP or domain (e.g. 192.168.0.100:8080)',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Enter address...',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              suffixIcon: IconButton(
                icon: const Icon(Icons.save_rounded,
                    color: Color(0xFF0A84FF), size: 20),
                onPressed: () {
                  remoteProvider.setCustomBaseUrl(controller.text);
                  remoteProvider.connectAndFetch();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Server address updated — connecting...'),
                      backgroundColor: Color(0xFF0A84FF),
                    ),
                  );
                },
              ),
            ),
            onSubmitted: (value) {
              remoteProvider.setCustomBaseUrl(value);
              remoteProvider.connectAndFetch();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildServerTokenField(BuildContext context) {
    final remoteProvider = Provider.of<RemoteMediaProvider>(context);
    final controller =
        TextEditingController(text: remoteProvider.serverToken ?? '');

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
                  color: const Color(0xFFE9B3FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.vpn_key_rounded,
                    color: Color(0xFFE9B3FF), size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Remote Server Token',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: remoteProvider.authError != null
                                ? Colors.orange.withOpacity(0.1)
                                : (remoteProvider.isConnected
                                    ? const Color(0xFF42E355)
                                        .withOpacity(0.1)
                                    : const Color(0xFFFF4444)
                                        .withOpacity(0.1)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            remoteProvider.authError != null
                                ? 'UNAUTHORIZED'
                                : (remoteProvider.isConnected
                                    ? 'CONNECTED'
                                    : 'DISCONNECTED'),
                            style: TextStyle(
                              color: remoteProvider.authError != null
                                  ? Colors.orange
                                  : (remoteProvider.isConnected
                                      ? const Color(0xFF42E355)
                                      : const Color(0xFFFF4444)),
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'Enter the token required by your Lumina Media Server.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Enter token...',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF42E355), size: 20),
                onPressed: () {
                  remoteProvider.setServerToken(controller.text);
                  remoteProvider.connectAndFetch();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Server token updated — reconnecting...'),
                      backgroundColor: Color(0xFF42E355),
                    ),
                  );
                },
              ),
            ),
            onSubmitted: (value) {
              remoteProvider.setServerToken(value);
              remoteProvider.connectAndFetch();
            },
          ),
        ],
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
                  color: const Color(0xFFFF9F0A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.live_tv_rounded,
                    color: Color(0xFFFF9F0A), size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'IPTV Provider',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
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
          _buildField('Server', _serverController, hint: 'provider.example'),
          const SizedBox(height: 8),

          // Port field
          _buildField('Port', _portController,
              hint: '443', keyboardType: TextInputType.number),
          const SizedBox(height: 8),

          // Username field
          _buildField('Username', _usernameController, hint: 'username'),
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
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFFF9F0A))),
                  SizedBox(width: 8),
                  Text('Loading IPTV content...',
                      style: TextStyle(color: Color(0xFFFF9F0A), fontSize: 11)),
                ],
              ),
            ),

          if (provider.lastError != null && !isLoading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
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
                  label: const Text('Save & Reload',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF9F0A),
                    side: BorderSide(
                        color: const Color(0xFFFF9F0A).withOpacity(0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
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
                  side: BorderSide(color: Colors.white.withOpacity(0.1)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
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
              label: const Text('Save Debug Log to Desktop',
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: BorderSide(color: Colors.red.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
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

  Widget _buildField(String label, TextEditingController controller,
      {String? hint, TextInputType? keyboardType}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.25), fontSize: 13),
          labelText: label,
          labelStyle: TextStyle(
              color: Colors.white.withOpacity(0.4), fontSize: 11),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: _passwordController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        obscureText: !_showPassword,
        decoration: InputDecoration(
          hintText: '97364759',
          hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.25), fontSize: 13),
          labelText: 'Password',
          labelStyle: TextStyle(
              color: Colors.white.withOpacity(0.4), fontSize: 11),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: Icon(
              _showPassword
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
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
                  color: const Color(0xFFE9B3FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_stories_rounded,
                    color: Color(0xFFE9B3FF), size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Artwork Scanner',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
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
                  side: BorderSide(
                      color: const Color(0xFFE9B3FF).withOpacity(0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scrapes cover art, descriptions, and ratings from:\n'
              '• TMDB — Movies & TV Shows\n'
              '• Jikan (MyAnimeList) — Anime\n'
              '• iTunes — Music',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApiScrapersSection extends StatefulWidget {
  @override
  State<_ApiScrapersSection> createState() => _ApiScrapersSectionState();
}

class _ApiScrapersSectionState extends State<_ApiScrapersSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (context, provider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'API SCRAPERS',
              style: TextStyle(
                color: const Color(0xFFAAC7FF).withOpacity(0.8),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9B3FF).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.api_rounded,
                          color: Color(0xFFE9B3FF), size: 20),
                    ),
                    title: const Text('Scraper Sources',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                        'Controls metadata, subtitle, actor, weather and artwork providers.',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                    trailing: Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: Colors.white54),
                    onTap: () => setState(() => _expanded = !_expanded),
                  ),
                  if (_expanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          _scraperToggle(provider, 'TMDB',
                              'Movie and TV metadata', 'tmdb'),
                          _scraperToggle(provider, 'TVMaze',
                              'TV show metadata fallback', 'tvmaze'),
                          _scraperToggle(provider, 'OMDb',
                              'Optional movie metadata', 'omdb'),
                          _scraperToggle(
                              provider, 'Jikan', 'Anime metadata', 'jikan'),
                          _scraperToggle(
                              provider,
                              'AniList',
                              'Anime metadata and adult profile support',
                              'anilist'),
                          _scraperToggle(provider, 'Spotify',
                              'Music metadata and artwork', 'spotify'),
                          _scraperToggle(provider, 'MusicBrainz',
                              'Music metadata fallback', 'musicbrainz'),
                          _scraperToggle(provider, 'OpenSubtitles',
                              'Subtitle search', 'opensubtitles'),
                          _scraperToggle(provider, 'Subscene',
                              'Subtitle search', 'subscene'),
                          _scraperToggle(provider, 'YIFY Subtitles',
                              'Movie subtitle search', 'yifysubtitles'),
                          _scraperToggle(provider, 'Addic7ed',
                              'TV subtitle search', 'addic7ed'),
                          _scraperToggle(provider, 'Wikidata',
                              'Actor details and cast lookup', 'wikidata'),
                          _scraperToggle(provider, 'OpenWeather',
                              'Weather mood playlists', 'openweather'),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: provider.clearApiAndArtworkCaches,
                              icon: const Icon(Icons.delete_sweep_rounded,
                                  size: 16),
                              label: const Text(
                                  'Clear API, Artwork, IPTV and EPG Caches'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFFB4AB),
                                side: BorderSide(
                                    color: const Color(0xFFFFB4AB)
                                        .withOpacity(0.3)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _scraperToggle(
      MediaProvider provider, String title, String description, String key) {
    return SwitchListTile(
      dense: true,
      value: provider.isScraperEnabled(key),
      onChanged: (value) => provider.setScraperEnabled(key, value),
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      subtitle: Text(description,
          style: TextStyle(
              color: Colors.white.withOpacity(0.4), fontSize: 11)),
      activeColor: const Color(0xFFE9B3FF),
      activeTrackColor: const Color(0xFFE9B3FF).withOpacity(0.3),
    );
  }
}

class _CacheStorageTile extends StatefulWidget {
  @override
  State<_CacheStorageTile> createState() => _CacheStorageTileState();
}

class _CacheStorageTileState extends State<_CacheStorageTile> {
  late Future<int> _sizeFuture;
  bool _isPurging = false;

  @override
  void initState() {
    super.initState();
    _sizeFuture = _loadSize();
  }

  Future<int> _loadSize() {
    return Provider.of<MediaProvider>(context, listen: false).cacheSizeBytes();
  }

  void _refreshSize() {
    setState(() {
      _sizeFuture = _loadSize();
    });
  }

  Future<void> _purgeCache() async {
    setState(() => _isPurging = true);
    try {
      await Provider.of<MediaProvider>(context, listen: false)
          .clearApiAndArtworkCaches();
      _refreshSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cache purged'),
            backgroundColor: Color(0xFF42E355),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPurging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<int>(
        future: _sizeFuture,
        builder: (context, snapshot) {
          final sizeLabel = snapshot.connectionState == ConnectionState.waiting
              ? 'Calculating...'
              : _formatBytes(snapshot.data ?? 0);

          return Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFAAC7FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storage_rounded,
                    color: Color(0xFFAAC7FF), size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cache Storage',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Current cache size: $sizeLabel',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh cache size',
                onPressed: _isPurging ? null : _refreshSize,
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white54, size: 20),
              ),
              OutlinedButton.icon(
                onPressed: _isPurging ? null : _purgeCache,
                icon: _isPurging
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.delete_sweep_rounded, size: 16),
                label: const Text('Purge'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFFB4AB),
                  side: BorderSide(
                      color: const Color(0xFFFFB4AB).withOpacity(0.3)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
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
                  color: const Color(0xFF42E355).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.download_rounded,
                    color: Color(0xFF42E355), size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Download Location',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
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
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                  icon: const Icon(Icons.folder_open_rounded,
                      size: 16, color: Colors.white38),
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
                  label: const Text('Change Location',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0A84FF),
                    side: BorderSide(
                        color: const Color(0xFF0A84FF).withOpacity(0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
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
                  side: BorderSide(color: Colors.white.withOpacity(0.1)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
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
                  color: const Color(0xFFFF9F0A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_special_rounded,
                    color: Color(0xFFFF9F0A), size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Watch Folders',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded,
                            size: 14, color: Color(0xFFAAC7FF)),
                        SizedBox(width: 4),
                        Text('Scan',
                            style: TextStyle(
                                color: Color(0xFFAAC7FF),
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
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
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Center(
                child: Text(
                  'No folders added yet',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 12),
                ),
              ),
            )
          else
            ...List.generate(_folders.length, (index) {
              final folder = _folders[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_rounded,
                        size: 16, color: Colors.white.withOpacity(0.4)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        folder,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
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
                          child: Icon(Icons.close_rounded,
                              size: 16,
                              color: Colors.white.withOpacity(0.3)),
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
                side: BorderSide(
                    color: const Color(0xFF0A84FF).withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerHealthMeter extends StatefulWidget {
  @override
  State<_ServerHealthMeter> createState() => _ServerHealthMeterState();
}

class _ServerHealthMeterState extends State<_ServerHealthMeter> {
  int? _pingMs;
  Timer? _pingTimer;

  @override
  void initState() {
    super.initState();
    _ping();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _ping());
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _ping() async {
    final provider = Provider.of<MediaProvider>(context, listen: false);
    if (!provider.isMediaServerRunning) {
      if (mounted) setState(() => _pingMs = null);
      return;
    }
    final url = provider.mediaServerLocalUrl;
    if (url.isEmpty) return;
    try {
      final sw = Stopwatch()..start();
      await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
      sw.stop();
      if (mounted) setState(() => _pingMs = sw.elapsedMilliseconds);
    } catch (_) {
      if (mounted) setState(() => _pingMs = null);
    }
  }

  int _computeScore(MediaProvider provider) {
    if (!provider.isMediaServerRunning) return 0;
    int score = 50;
    if (provider.mediaServerError == null) score += 20;
    if (provider.isTunnelRunning) score += 15;
    if (_pingMs != null) {
      if (_pingMs! < 50) score += 15;
      else if (_pingMs! < 200) score += 8;
      else score += 3;
    }
    return score.clamp(0, 100);
  }

  static Color _scoreColor(int score) {
    if (score >= 80) return const Color(0xFF42E355);
    if (score >= 60) return const Color(0xFFFFD60A);
    if (score >= 30) return const Color(0xFFFF9F0A);
    return const Color(0xFFFF453A);
  }

  static String _scoreLabel(int score) {
    if (score >= 80) return 'Healthy';
    if (score >= 60) return 'Degraded';
    if (score >= 30) return 'Poor';
    return 'Offline';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (context, provider, _) {
        final score = _computeScore(provider);
        final color = _scoreColor(score);
        final label = _scoreLabel(score);

        return Column(
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(110, 110),
                    painter: _HealthArcPainter(score: score / 100.0),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$score',
                        style: TextStyle(
                          color: color,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        label,
                        style: TextStyle(
                            color: color.withOpacity(0.8), fontSize: 10),
                      ),
                      if (_pingMs != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${_pingMs}ms',
                          style: const TextStyle(
                              color: Colors.white24, fontSize: 9),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'SERVER HEALTH',
              style: TextStyle(
                color: Colors.white24,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HealthArcPainter extends CustomPainter {
  final double score; // 0.0–1.0

  const _HealthArcPainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;
    const strokeWidth = 9.0;
    const startAngle = 3 * math.pi / 4;  // 135°
    const sweepTotal = 3 * math.pi / 2;  // 270°

    // Background track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (score <= 0) return;

    final sweepAngle = sweepTotal * score;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final gradient = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + sweepTotal,
      colors: const [
        Color(0xFFFF453A), // red
        Color(0xFFFF9F0A), // orange
        Color(0xFFFFD60A), // yellow
        Color(0xFF42E355), // green
      ],
      stops: const [0.0, 0.33, 0.66, 1.0],
    );

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..shader = gradient.createShader(rect)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_HealthArcPainter old) => old.score != score;
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
              Center(child: _ServerHealthMeter()),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.lan_rounded,
                        color: Color(0xFF0A84FF), size: 20),
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
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusBadge(isRunning, error != null),
                          ],
                        ),
                        Text(
                          isRunning
                              ? 'Local: $localUrl'
                              : 'Server is stopped. Start it when you want local access.',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auto-start Server',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Launch server and tunnels automatically on startup.',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: provider.settings.autoStartServer,
                    onChanged: (value) => provider.toggleAutoStartServer(value),
                    activeColor: const Color(0xFF42E355),
                    activeTrackColor:
                        const Color(0xFF42E355).withOpacity(0.2),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: isRunning
                        ? provider.stopMediaServer
                        : () => provider.startMediaServer(),
                    icon: Icon(
                        isRunning
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        size: 16),
                    label: Text(
                        isRunning ? 'Stop Local Server' : 'Start Local Server'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isRunning
                          ? const Color(0xFFFFB4AB)
                          : const Color(0xFF42E355),
                      side: BorderSide(
                          color: (isRunning
                                  ? const Color(0xFFFFB4AB)
                                  : const Color(0xFF42E355))
                              .withOpacity(0.3)),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: provider.regenerateMediaServerToken,
                    icon: const Icon(Icons.key_rounded, size: 16),
                    label: const Text('Regenerate Token'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFAAC7FF),
                      side: BorderSide(
                          color:
                              const Color(0xFFAAC7FF).withOpacity(0.3)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                provider.mediaServerToken.isEmpty
                    ? 'Access token will be generated when the server starts.'
                    : 'Access token: ${provider.mediaServerToken}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              if (error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: Text(
                    error,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 11),
                  ),
                ),
              const Divider(color: Colors.white12, height: 24),
              const Text(
                'CLOUDFLARE TUNNEL',
                style: TextStyle(
                  color: Colors.white30,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<bool>(
                valueListenable: provider.cloudflareTunnel.isRunning,
                builder: (context, tunnelRunning, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF42E355).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.cloud_rounded,
                              color: tunnelRunning
                                  ? const Color(0xFF42E355)
                                  : Colors.white38,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Remote Tunnel',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                                ValueListenableBuilder<String>(
                                  valueListenable:
                                      provider.cloudflareTunnel.status,
                                  builder: (context, status, _) {
                                    return Text(
                                      tunnelRunning
                                          ? provider.tunnelUrl
                                          : status,
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: tunnelRunning,
                            onChanged: (value) => value
                                ? provider.startRemoteTunnel()
                                : provider.stopRemoteTunnel(),
                            activeColor: const Color(0xFF42E355),
                            activeTrackColor:
                                const Color(0xFF42E355).withOpacity(0.2),
                          ),
                        ],
                      ),
                      if (tunnelRunning) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          provider.tunnelUrl,
                          style: const TextStyle(
                              color: Color(0xFF42E355), fontSize: 11),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const Divider(color: Colors.white12, height: 24),
              const Text(
                'PRIVATE INTERNET ACCESS (PIA)',
                style: TextStyle(
                  color: Colors.white30,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0078D4).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.vpn_lock_rounded,
                        color: Color(0xFF0078D4), size: 20),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PIA VPN',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Auto-connect to VPN when server starts.',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: provider.settings.enablePiaVpn,
                    onChanged: (value) => provider.togglePiaVpn(value),
                    activeColor: const Color(0xFF0078D4),
                  ),
                ],
              ),
              if (provider.settings.enablePiaVpn) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: provider.settings.piaVpnRegion == 'custom'
                          ? 'custom'
                          : provider.settings.piaVpnRegion,
                      dropdownColor: const Color(0xFF1E1E22),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      icon: const Icon(Icons.arrow_drop_down,
                          color: Colors.white38),
                      isExpanded: true,
                      onChanged: (value) {
                        if (value != null) provider.setPiaVpnRegion(value);
                      },
                      items: const [
                        DropdownMenuItem(
                            value: 'ca-ontario',
                            child: Text('Canada (Ontario)')),
                        DropdownMenuItem(
                            value: 'ca-toronto',
                            child: Text('Canada (Toronto)')),
                        DropdownMenuItem(
                            value: 'ca-vancouver',
                            child: Text('Canada (Vancouver)')),
                        DropdownMenuItem(
                            value: 'us-east', child: Text('US East')),
                        DropdownMenuItem(
                            value: 'us-west', child: Text('US West')),
                        DropdownMenuItem(
                            value: 'uk-london', child: Text('UK London')),
                        DropdownMenuItem(
                            value: 'custom',
                            child: Text('Custom OVPN Profile...')),
                      ],
                    ),
                  ),
                ),
                if (provider.settings.piaVpnRegion == 'custom') ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['ovpn'],
                      );
                      if (result != null &&
                          result.files.single.path != null) {
                        provider.setPiaVpnCustomPath(
                            result.files.single.path!);
                      }
                    },
                    icon: const Icon(Icons.file_present_rounded, size: 16),
                    label: Text(
                      provider.settings.piaVpnCustomPath ??
                          'Select OVPN Profile',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFAAC7FF),
                      side: BorderSide(
                        color: const Color(0xFFAAC7FF).withOpacity(0.3),
                      ),
                    ),
                  ),
                ],
              ],
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
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.white.withOpacity(0.05)),
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
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
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

class _StorageSettingsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);

    return Column(
      children: [
        _StorageLocationRow(
          title: 'Movie Folder',
          description: 'Storage location for movies.',
          icon: Icons.movie_rounded,
          path: provider.settings.movieStoragePath,
          defaultLabel: 'Not set',
          onPathSelected: provider.setMovieStoragePath,
        ),
        _StorageLocationRow(
          title: 'TV Show Folder',
          description: 'Storage location for TV shows and episodes.',
          icon: Icons.tv_rounded,
          path: provider.settings.tvShowStoragePath,
          defaultLabel: 'Not set',
          onPathSelected: provider.setTvShowStoragePath,
        ),
        _StorageLocationRow(
          title: 'Not Safe For Work Folder',
          description: 'Storage location for adult content.',
          icon: Icons.no_adult_content_rounded,
          path: provider.settings.nsfwStoragePath,
          defaultLabel: 'Not set',
          onPathSelected: provider.setNsfwStoragePath,
        ),
        _StorageLocationRow(
          title: 'Music Folder',
          description: 'Storage location for downloaded music.',
          icon: Icons.library_music_rounded,
          path: provider.settings.musicSavePath,
          defaultLabel: 'Not set (defaults to App Documents/Music)',
          onPathSelected: provider.setMusicSavePath,
        ),
        _StorageLocationRow(
          title: 'E-books Folder',
          description: 'Storage location for e-books and text documents.',
          icon: Icons.menu_book_rounded,
          path: provider.settings.ebookStoragePath,
          defaultLabel: 'Not set',
          onPathSelected: provider.setEbookStoragePath,
        ),
        _StorageLocationRow(
          title: 'Manga Folder',
          description: 'Storage location for manga image files.',
          icon: Icons.auto_stories_rounded,
          path: provider.settings.mangaStoragePath,
          defaultLabel: 'Not set',
          onPathSelected: provider.setMangaStoragePath,
        ),
        _StorageLocationRow(
          title: 'Comics Folder',
          description: 'Storage location for comic books and comic images.',
          icon: Icons.collections_bookmark_rounded,
          path: provider.settings.comicsStoragePath,
          defaultLabel: 'Not set',
          onPathSelected: provider.setComicsStoragePath,
        ),
      ],
    );
  }
}

class _DocumentMetadataApiTile extends StatelessWidget {
  static const _providers = [
    ('googleBooks', 'Google Books', 'Book covers, authors and summaries.'),
    (
      'openLibraryCovers',
      'Open Library Covers',
      'Dedicated Open Library cover images by ISBN, OLID or cover ID.'
    ),
    ('openLibrary', 'Open Library', 'ISBN matching and alternate book covers.'),
    (
      'projectGutenberg',
      'Project Gutenberg',
      'Free book metadata and test content.'
    ),
    ('mangaDex', 'MangaDex', 'Primary manga covers, tags and descriptions.'),
    ('jikan', 'Jikan', 'MyAnimeList ratings, rankings and manga summaries.'),
    ('metaChan', 'MetaChan', 'Optional manga metadata provider.'),
    ('mangaVerse', 'MangaVerse', 'Optional manga metadata provider.'),
    ('comicVine', 'Comic Vine', 'Comic book covers, issue data and summaries.'),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE9B3FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.travel_explore_rounded,
                    color: Color(0xFFE9B3FF), size: 20),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Choose which APIs are used when scanning EPUB, PDF, TXT, MD, CBZ, CBR, manga and comic files.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        ..._providers.map((entry) {
          return SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: provider.isDocumentMetadataProviderEnabled(entry.$1),
            onChanged: (value) =>
                provider.setDocumentMetadataProviderEnabled(entry.$1, value),
            title: Text(entry.$2,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text(entry.$3,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            activeColor: const Color(0xFFE9B3FF),
          );
        }),
      ],
    );
  }
}

class _GameArtApiTile extends StatelessWidget {
  static const String _envClientId = String.fromEnvironment('TWITCH_CLIENT_ID');
  static const String _envClientSecret =
      String.fromEnvironment('TWITCH_CLIENT_SECRET');

  String get _clientId => _envClientId.isNotEmpty
      ? _envClientId
      : (Platform.environment['TWITCH_CLIENT_ID'] ?? '');

  String get _clientSecret => _envClientSecret.isNotEmpty
      ? _envClientSecret
      : (Platform.environment['TWITCH_CLIENT_SECRET'] ?? '');

  String _masked(String value) {
    if (value.isEmpty) return 'Not configured';
    if (value.length <= 8) return 'Configured';
    return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasClientId = _clientId.isNotEmpty;
    final hasSecret = _clientSecret.isNotEmpty;
    final ready = hasClientId && hasSecret;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF9146FF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.sports_esports_rounded,
                color: Color(0xFFB58CFF), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Twitch / IGDB Artwork Provider',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (ready
                                ? const Color(0xFF42E355)
                                : const Color(0xFFFFB4AB))
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ready ? 'READY' : 'MISSING',
                        style: TextStyle(
                          color: ready
                              ? const Color(0xFF42E355)
                              : const Color(0xFFFFB4AB),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Used for game cover art, screenshots and metadata through Twitch-backed game APIs.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Text(
                  'Client ID: ${_masked(_clientId)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Client Secret: ${hasSecret ? 'Configured' : 'Not configured'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageLocationRow extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String? path;
  final String defaultLabel;
  final ValueChanged<String> onPathSelected;

  const _StorageLocationRow({
    required this.title,
    required this.description,
    required this.icon,
    required this.path,
    required this.defaultLabel,
    required this.onPathSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFAAC7FF).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFFAAC7FF), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            path ?? defaultLabel,
            style: TextStyle(
              color: Colors.white.withOpacity(path == null ? 0.35 : 0.55),
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: IconButton(
        icon:
            const Icon(Icons.edit_rounded, color: Color(0xFFAAC7FF), size: 20),
        tooltip: 'Set Storage Location',
        onPressed: () async {
          final selectedDirectory = await FilePicker.getDirectoryPath();
          if (selectedDirectory != null) {
            onPathSelected(selectedDirectory);
          }
        },
      ),
    );
  }
}

class _SecretMenuTile extends StatefulWidget {
  @override
  State<_SecretMenuTile> createState() => _SecretMenuTileState();
}

class _SecretMenuTileState extends State<_SecretMenuTile> {
  final TextEditingController _passcodeController = TextEditingController();

  @override
  void dispose() {
    _passcodeController.dispose();
    super.dispose();
  }

  Future<void> _showUnlockDialog() async {
    _passcodeController.clear();
    final provider = Provider.of<MediaProvider>(context, listen: false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E22),
          title: const Text(
            'Secret Menu',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: _passcodeController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Passcode',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              enabledBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(color: Colors.white.withOpacity(0.12)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFAAC7FF)),
              ),
            ),
            onSubmitted: (_) => _unlock(dialogContext, provider),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _unlock(dialogContext, provider),
              child: const Text('Unlock'),
            ),
          ],
        );
      },
    );
  }

  void _unlock(BuildContext dialogContext, MediaProvider provider) {
    final unlocked = provider.unlockSecretMenu(_passcodeController.text);
    Navigator.of(dialogContext).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(unlocked
            ? 'Not Safe for Work tab revealed.'
            : 'Incorrect passcode.'),
        backgroundColor: unlocked ? const Color(0xFF42E355) : Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = Provider.of<MediaProvider>(context).settings.showNsfwTab;

    return ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFE9B3FF).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
          color: const Color(0xFFE9B3FF),
          size: 20,
        ),
      ),
      title: const Text(
        'Secret Menu',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        unlocked
            ? 'Not Safe for Work tab is visible in the sidebar.'
            : 'Enter the passcode to reveal the hidden Not Safe for Work tab.',
        style:
            TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
      ),
      trailing: IconButton(
        icon: Icon(
          unlocked ? Icons.check_circle_rounded : Icons.key_rounded,
          color: unlocked ? const Color(0xFF42E355) : const Color(0xFFE9B3FF),
          size: 20,
        ),
        tooltip: unlocked ? 'Unlocked' : 'Enter Passcode',
        onPressed: unlocked ? null : _showUnlockDialog,
      ),
      onTap: unlocked ? null : _showUnlockDialog,
    );
  }
}

class _DependencyManagementTile extends StatefulWidget {
  @override
  State<_DependencyManagementTile> createState() => _DependencyManagementTileState();
}

class _DependencyManagementTileState extends State<_DependencyManagementTile> {
  bool _isYtDlpInstalled = false;
  bool _isFfmpegInstalled = false;
  bool _isInstallingYtDlp = false;
  bool _isInstallingFfmpeg = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final provider = Provider.of<MediaProvider>(context, listen: false);
    final ytInstalled = await provider.isYtDlpInstalled();
    final ffmpegInstalled = await provider.isFfmpegInstalled();
    if (mounted) {
      setState(() {
        _isYtDlpInstalled = ytInstalled;
        _isFfmpegInstalled = ffmpegInstalled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDepRow(
            'yt-dlp',
            'Required for high-quality video/audio downloads.',
            Icons.download_rounded,
            _isYtDlpInstalled,
            _isInstallingYtDlp,
            () async {
              setState(() => _isInstallingYtDlp = true);
              try {
                await provider.installYtDlp();
                await _checkStatus();
              } finally {
                if (mounted) setState(() => _isInstallingYtDlp = false);
              }
            },
          ),
          const SizedBox(height: 16),
          _buildDepRow(
            'FFmpeg',
            'Required for converting downloads to MP3 format.',
            Icons.transform_rounded,
            _isFfmpegInstalled,
            _isInstallingFfmpeg,
            () async {
              setState(() => _isInstallingFfmpeg = true);
              try {
                await provider.installFfmpeg();
                await _checkStatus();
              } finally {
                if (mounted) setState(() => _isInstallingFfmpeg = false);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDepRow(String title, String desc, IconData icon, bool installed, bool installing, VoidCallback onInstall) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (installed ? const Color(0xFF42E355) : const Color(0xFF0A84FF)).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: installed ? const Color(0xFF42E355) : const Color(0xFF0A84FF), size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              Text(
                desc,
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
              ),
            ],
          ),
        ),
        if (installing)
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF0A84FF))))
        else if (installed)
          const Icon(Icons.check_circle_rounded, color: Color(0xFF42E355), size: 24)
        else
          TextButton(
            onPressed: onInstall,
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF0A84FF).withOpacity(0.1),
              foregroundColor: const Color(0xFF0A84FF),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Install', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}

class _PairedDevicesSection extends StatefulWidget {
  const _PairedDevicesSection();

  @override
  State<_PairedDevicesSection> createState() => _PairedDevicesSectionState();
}

class _PairedDevicesSectionState extends State<_PairedDevicesSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);
    final pairedDevices = provider.settings.pairedDevices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  'PAIRED DEVICES',
                  style: TextStyle(
                    color: const Color(0xFFAAC7FF).withOpacity(0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFAAC7FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    pairedDevices.length.toString(),
                    style: const TextStyle(
                      color: Color(0xFFAAC7FF),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  _isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.white24,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: pairedDevices.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No devices paired yet.',
                        style: TextStyle(color: Colors.white24, fontSize: 13),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pairedDevices.length,
                    separatorBuilder: (context, index) => Divider(
                      color: Colors.white.withOpacity(0.05),
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                    itemBuilder: (context, index) {
                      final deviceId = pairedDevices.keys.elementAt(index);
                      final deviceName = pairedDevices[deviceId]!;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF42E355).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.smartphone_rounded,
                              color: Color(0xFF42E355), size: 18),
                        ),
                        title: Text(
                          deviceName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'ID: ${deviceId.substring(0, math.min(12, deviceId.length))}...',
                          style: const TextStyle(
                              color: Colors.white24, fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.no_accounts_rounded,
                              color: Colors.redAccent, size: 20),
                          tooltip: 'Revoke Access',
                          onPressed: () => _confirmRevoke(
                              context, provider, deviceId, deviceName),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  void _confirmRevoke(
      BuildContext context, MediaProvider provider, String id, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title:
            const Text('Revoke Access?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to disconnect "$name"? They will need to be re-approved the next time they try to connect.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              provider.revokePairing(id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Access revoked for $name'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
            child:
                const Text('Revoke', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}


/// Tile for IPTV Proxy Settings (Connection Limiting & User-Agent)
class _IptvProxySettingsTile extends StatefulWidget {
  @override
  State<_IptvProxySettingsTile> createState() => _IptvProxySettingsTileState();
}

class _IptvProxySettingsTileState extends State<_IptvProxySettingsTile> {
  late TextEditingController _uaController;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<MediaProvider>(context, listen: false);
    _uaController =
        TextEditingController(text: provider.settings.iptvUserAgent);
  }

  @override
  void dispose() {
    _uaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);
    final settings = provider.settings;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.speed_rounded,
                    color: Color(0xFFFF3B30), size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Max Concurrent IPTV Streams',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Limit concurrent connections to your IPTV provider.',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              DropdownButton<int>(
                value: settings.iptvMaxConnections,
                dropdownColor: const Color(0xFF1E1E22),
                underline: Container(),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white54),
                items: [1, 2, 3, 4, 5, 10]
                    .map((val) => DropdownMenuItem(
                          value: val,
                          child: Text('$val',
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white)),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) provider.setIptvMaxConnections(val);
                },
              ),
            ],
          ),
        ),
        Divider(color: Colors.white.withOpacity(0.05), height: 1),
        Padding(
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
                      color: const Color(0xFF5856D6).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.terminal_rounded,
                        color: Color(0xFF5856D6), size: 20),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IPTV User-Agent',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Spoof a specific player or browser for IPTV streams.',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _uaController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter User-Agent string...',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.save_rounded,
                        color: Color(0xFF0A84FF), size: 20),
                    onPressed: () {
                      provider.setIptvUserAgent(_uaController.text);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('IPTV User-Agent updated'),
                          backgroundColor: Color(0xFF0A84FF),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.1)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lumina proxies and de-duplicates IPTV streams to protect your account from multiple active user bans.',
                    style: TextStyle(color: Colors.blue, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DocumentOrganizerTile extends StatelessWidget {
  final DocumentLibraryType type;
  const _DocumentOrganizerTile({required this.type});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);
    final isLoading = provider.isLoading;

    final String title;
    final String description;
    final IconData icon;
    final bool autoOrganize;
    final ValueChanged<bool> onToggle;
    final VoidCallback onOrganize;
    final Color themeColor;

    switch (type) {
      case DocumentLibraryType.manga:
        title = 'Manga Organizer';
        description = 'Physically organize manga into series folders';
        icon = Icons.auto_awesome_motion_rounded;
        autoOrganize = provider.settings.autoOrganizeManga;
        onToggle = provider.setAutoOrganizeManga;
        onOrganize = provider.organizeMangaLibrary;
        themeColor = const Color(0xFFE9B3FF);
        break;
      case DocumentLibraryType.comics:
        title = 'Comics Organizer';
        description = 'Group comics by series/volume folders';
        icon = Icons.collections_bookmark_rounded;
        autoOrganize = provider.settings.autoOrganizeComics;
        onToggle = provider.setAutoOrganizeComics;
        onOrganize = provider.organizeComicsLibrary;
        themeColor = const Color(0xFFE9B3FF);
        break;
      case DocumentLibraryType.ebooks:
        title = 'E-book Organizer';
        description = 'Organize books by series or author folders';
        icon = Icons.menu_book_rounded;
        autoOrganize = provider.settings.autoOrganizeEbooks;
        onToggle = provider.setAutoOrganizeEbooks;
        onOrganize = provider.organizeEbooksLibrary;
        themeColor = const Color(0xFFE9B3FF);
        break;
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
                  color: themeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: themeColor, size: 20),
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
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      description,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('Auto-Organize $title',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text(
                'Automatically group new files when scanning.',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            value: autoOrganize,
            onChanged: onToggle,
            activeColor: themeColor,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isLoading ? null : onOrganize,
              icon: isLoading
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: themeColor))
                  : const Icon(Icons.folder_copy_rounded, size: 16),
              label: Text(isLoading ? 'Organizing...' : 'Organize $title Now'),
              style: OutlinedButton.styleFrom(
                foregroundColor: themeColor,
                side: BorderSide(color: themeColor.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticleThemeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MediaProvider>(context);
    final currentTheme = provider.settings.particleTheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.palette_rounded, color: Color(0xFFAAC7FF), size: 20),
              SizedBox(width: 16),
              Text(
                'Background Theme',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ThemeOption(
                  label: 'Sakura',
                  icon: Icons.filter_vintage_rounded,
                  selected: currentTheme == ParticleTheme.sakura,
                  color: const Color(0xFFE9B3FF),
                  onTap: () => provider.setParticleTheme(ParticleTheme.sakura),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ThemeOption(
                  label: 'Skulls',
                  icon: Icons.dangerous,
                  selected: currentTheme == ParticleTheme.skulls,
                  color: Colors.white70,
                  onTap: () => provider.setParticleTheme(ParticleTheme.skulls),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.15)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? color : Colors.white24, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white38,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicProvidersSection extends StatelessWidget {
  _MusicProvidersSection();

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final settings = musicProvider.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Music Providers'),
        _buildProviderCard(
          context,
          'Spotify',
          'Primary metadata and search provider',
          Icons.music_note_rounded,
          const Color(0xFF1DB954),
          settings.enableSpotify,
          (val) {
            settings.enableSpotify = val;
            musicProvider.saveSettings();
          },
          [
            _buildTextField(
              'Client ID',
              settings.spotifyClientId,
              (val) => settings.spotifyClientId = val,
              obscure: true,
            ),
            _buildTextField(
              'Client Secret',
              settings.spotifyClientSecret,
              (val) => settings.spotifyClientSecret = val,
              obscure: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    musicProvider.saveSettings();
                  },
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save Credentials'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954).withOpacity(0.2),
                    foregroundColor: const Color(0xFF1DB954),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Implement test connection
                  },
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Test Connection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954).withOpacity(0.2),
                    foregroundColor: const Color(0xFF1DB954),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    settings.spotifyClientId = '';
                    settings.spotifyClientSecret = '';
                    musicProvider.saveSettings();
                  },
                  child: const Text('Clear Credentials', style: TextStyle(color: Colors.redAccent)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ManualMatchQueuePage()),
                    );
                  },
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                  label: const Text('Review Match Queue'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE9B3FF).withOpacity(0.1),
                    foregroundColor: const Color(0xFFE9B3FF),
                  ),
                ),
              ],
            ),
          ],
        ),
        _buildProviderCard(
          context,
          'MusicBrainz',
          'Open music encyclopedia fallback',
          Icons.library_music_rounded,
          const Color(0xFFEB743B),
          settings.enableMusicBrainz,
          (val) {
            settings.enableMusicBrainz = val;
            musicProvider.saveSettings();
          },
          [
            _buildTextField(
              'User Agent',
              settings.mbUserAgent,
              (val) => settings.mbUserAgent = val,
            ),
            _buildTextField(
              'Contact Email',
              settings.mbContactEmail,
              (val) => settings.mbContactEmail = val,
            ),
            SwitchListTile(
              title: const Text('Rate Limiting', style: TextStyle(color: Colors.white, fontSize: 13)),
              value: settings.mbRateLimit,
              onChanged: (val) {
                settings.mbRateLimit = val;
                musicProvider.saveSettings();
              },
              dense: true,
            ),
          ],
        ),
        _buildProviderCard(
          context,
          'Last.fm',
          'Artist bios, tags, and similar tracks',
          Icons.favorite_rounded,
          const Color(0xFFD01F3C),
          settings.enableLastFm,
          (val) {
            settings.enableLastFm = val;
            musicProvider.saveSettings();
          },
          [
            _buildTextField(
              'API Key',
              settings.lastFmApiKey,
              (val) => settings.lastFmApiKey = val,
              obscure: true,
            ),
            CheckboxListTile(
              title: const Text('Enable Artist Bios', style: TextStyle(color: Colors.white, fontSize: 13)),
              value: settings.enableArtistBios,
              onChanged: (val) {
                settings.enableArtistBios = val ?? true;
                musicProvider.saveSettings();
              },
              dense: true,
            ),
            CheckboxListTile(
              title: const Text('Enable Tags', style: TextStyle(color: Colors.white, fontSize: 13)),
              value: settings.enableTags,
              onChanged: (val) {
                settings.enableTags = val ?? true;
                musicProvider.saveSettings();
              },
              dense: true,
            ),
          ],
        ),
        _buildProviderCard(
          context,
          'ListenBrainz',
          'Recommendations and history sync',
          Icons.headphones_rounded,
          const Color(0xFF35303D),
          settings.enableListenBrainz,
          (val) {
            settings.enableListenBrainz = val;
            musicProvider.saveSettings();
          },
          [
            _buildTextField(
              'User Token',
              settings.lbUserToken,
              (val) => settings.lbUserToken = val,
              obscure: true,
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildProviderCard(
    BuildContext context,
    String name,
    String description,
    IconData icon,
    Color color,
    bool enabled,
    ValueChanged<bool> onToggle,
    List<Widget> children,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        subtitle: Text(description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: Switch(
          value: enabled,
          onChanged: onToggle,
          activeColor: color,
        ),
        childrenPadding: const EdgeInsets.all(16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildTextField(String label, String value, ValueChanged<String> onChanged, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: TextEditingController(text: value)..selection = TextSelection.fromPosition(TextPosition(offset: value.length)),
        onChanged: onChanged,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFAAC7FF))),
        ),
      ),
    );
  }

}
