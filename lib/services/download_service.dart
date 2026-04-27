import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Represents a single download task
class DownloadTask {
  final String id;
  final String url;
  final String fileName;
  final String savePath;
  final double progress;
  final DownloadStatus status;
  final String? errorMessage;
  final DateTime createdAt;
  final int? totalBytes;
  final int? receivedBytes;

  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.progress = 0.0,
    this.status = DownloadStatus.pending,
    this.errorMessage,
    DateTime? createdAt,
    this.totalBytes,
    this.receivedBytes,
  }) : createdAt = createdAt ?? DateTime.now();

  DownloadTask copyWith({
    String? id,
    String? url,
    String? fileName,
    String? savePath,
    double? progress,
    DownloadStatus? status,
    String? errorMessage,
    DateTime? createdAt,
    int? totalBytes,
    int? receivedBytes,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      savePath: savePath ?? this.savePath,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      totalBytes: totalBytes ?? this.totalBytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'fileName': fileName,
    'savePath': savePath,
    'progress': progress,
    'status': status.index,
    'errorMessage': errorMessage,
    'createdAt': createdAt.toIso8601String(),
    'totalBytes': totalBytes,
    'receivedBytes': receivedBytes,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
    id: json['id'] as String,
    url: json['url'] as String,
    fileName: json['fileName'] as String,
    savePath: json['savePath'] as String,
    progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
    status: json['status'] != null 
        ? DownloadStatus.values[json['status'] as int] 
        : DownloadStatus.pending,
    errorMessage: json['errorMessage'] as String?,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    totalBytes: json['totalBytes'] as int?,
    receivedBytes: json['receivedBytes'] as int?,
  );
}

enum DownloadStatus {
  pending,
  downloading,
  completed,
  failed,
  cancelled,
}

/// Callback for download progress updates
typedef DownloadProgressCallback = void Function(String taskId, double progress, int received, int total);

/// Service for managing file downloads from the browser
class DownloadService extends ChangeNotifier {
  final Dio _dio = Dio();
  final List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _cancelTokens = {};
  DownloadProgressCallback? onProgress;

  /// Default download directory
  String _downloadDirectory = '';
  
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  String get downloadDirectory => _downloadDirectory;

  /// Initialize the download service and load saved tasks
  Future<void> initialize() async {
    await _loadDownloadDirectory();
    await _loadTasks();
  }

  /// Get the default download directory
  Future<String> getDefaultDownloadDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final defaultDir = p.join(docDir.path, 'downloads');
    final dir = Directory(defaultDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return defaultDir;
  }

  /// Load the saved download directory from settings
  Future<void> _loadDownloadDirectory() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final settingsFile = File(p.join(docDir.path, 'download_settings.json'));
      if (await settingsFile.exists()) {
        final json = jsonDecode(await settingsFile.readAsString());
        _downloadDirectory = json['downloadDirectory'] as String? ?? '';
      }
    } catch (e) {
      debugPrint('Error loading download directory: $e');
    }
    
    if (_downloadDirectory.isEmpty) {
      _downloadDirectory = await getDefaultDownloadDirectory();
    }
  }

  /// Save the download directory to settings
  Future<void> saveDownloadDirectory(String path) async {
    _downloadDirectory = path;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final settingsFile = File(p.join(docDir.path, 'download_settings.json'));
      await settingsFile.writeAsString(jsonEncode({
        'downloadDirectory': path,
      }));
    } catch (e) {
      debugPrint('Error saving download directory: $e');
    }
  }

  /// Load saved download tasks
  Future<void> _loadTasks() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final tasksFile = File(p.join(docDir.path, 'download_tasks.json'));
      if (await tasksFile.exists()) {
        final json = jsonDecode(await tasksFile.readAsString()) as List;
        _tasks.clear();
        for (final item in json) {
          final task = DownloadTask.fromJson(item as Map<String, dynamic>);
          // Only load pending/completed tasks, not in-progress ones
          if (task.status == DownloadStatus.downloading) {
            _tasks.add(task.copyWith(status: DownloadStatus.pending));
          } else {
            _tasks.add(task);
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading download tasks: $e');
    }
  }

  /// Save download tasks to disk
  Future<void> _saveTasks() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final tasksFile = File(p.join(docDir.path, 'download_tasks.json'));
      final json = _tasks.map((t) => t.toJson()).toList();
      await tasksFile.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('Error saving download tasks: $e');
    }
  }

  /// Generate a unique task ID
  String _generateTaskId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_tasks.length}';
  }

  /// Extract a filename from a URL
  String extractFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final segments = path.split('/');
      if (segments.isNotEmpty && segments.last.isNotEmpty) {
        return segments.last;
      }
    } catch (_) {}
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Start downloading a file from the given URL
  Future<DownloadTask> startDownload(String url, {String? fileName, String? savePath, String? customSaveDir}) async {
    final effectiveDir = customSaveDir ?? _downloadDirectory;
    
    // Ensure directory exists
    final dir = Directory(effectiveDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final name = fileName ?? extractFileName(url);
    final finalSavePath = savePath ?? p.join(effectiveDir, name);

    // Check if already exists
    if (await File(finalSavePath).exists()) {
      // Add a number suffix
      final base = p.basenameWithoutExtension(finalSavePath);
      final ext = p.extension(finalSavePath);
      int counter = 1;
      String newPath;
      do {
        newPath = p.join(effectiveDir, '${base}_($counter)$ext');
        counter++;
      } while (await File(newPath).exists());
      return startDownload(url, fileName: p.basename(newPath), customSaveDir: effectiveDir);
    }

    final task = DownloadTask(
      id: _generateTaskId(),
      url: url,
      fileName: name,
      savePath: finalSavePath,
      status: DownloadStatus.pending,
    );

    _tasks.add(task);
    notifyListeners();
    _saveTasks();

    // Start the download
    _executeDownload(task.id);

    return task;
  }

  /// Manually add a task (useful for external downloads like yt-dlp)
  void addManualTask(DownloadTask task) {
    _tasks.add(task);
    notifyListeners();
    _saveTasks();
  }

  /// Update an existing task
  void updateTask(String taskId, {DownloadStatus? status, double? progress, String? errorMessage}) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(
        status: status,
        progress: progress,
        errorMessage: errorMessage,
      );
      notifyListeners();
      _saveTasks();
    }
  }

  /// Execute the actual download
  Future<void> _executeDownload(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    _tasks[index] = task.copyWith(status: DownloadStatus.downloading);
    notifyListeners();

    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;

    try {
      // Ensure directory exists
      final dir = Directory(p.dirname(task.savePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await _dio.download(
        task.url,
        task.savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final progress = total != -1 ? received / total : 0.0;
          final idx = _tasks.indexWhere((t) => t.id == taskId);
          if (idx != -1) {
            _tasks[idx] = _tasks[idx].copyWith(
              progress: progress,
              receivedBytes: received,
              totalBytes: total,
            );
            onProgress?.call(taskId, progress, received, total);
            notifyListeners();
          }
        },
      );

      // Mark as completed
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        _tasks[idx] = _tasks[idx].copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
        );
        notifyListeners();
        _saveTasks();
      }
    } catch (e) {
      if (cancelToken.isCancelled) {
        final idx = _tasks.indexWhere((t) => t.id == taskId);
        if (idx != -1) {
          _tasks[idx] = _tasks[idx].copyWith(status: DownloadStatus.cancelled);
        }
      } else {
        final idx = _tasks.indexWhere((t) => t.id == taskId);
        if (idx != -1) {
          _tasks[idx] = _tasks[idx].copyWith(
            status: DownloadStatus.failed,
            errorMessage: e.toString(),
          );
        }
      }
      notifyListeners();
      _saveTasks();
    } finally {
      _cancelTokens.remove(taskId);
    }
  }

  /// Cancel a download
  Future<void> cancelDownload(String taskId) async {
    final cancelToken = _cancelTokens[taskId];
    if (cancelToken != null) {
      cancelToken.cancel();
    }
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1 && _tasks[idx].status == DownloadStatus.downloading) {
      _tasks[idx] = _tasks[idx].copyWith(status: DownloadStatus.cancelled);
      notifyListeners();
      _saveTasks();
    }
  }

  /// Remove a task from the list
  Future<void> removeTask(String taskId) async {
    await cancelDownload(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
    _saveTasks();
  }

  /// Clear all completed tasks
  Future<void> clearCompleted() async {
    _tasks.removeWhere((t) => 
      t.status == DownloadStatus.completed || 
      t.status == DownloadStatus.failed || 
      t.status == DownloadStatus.cancelled
    );
    notifyListeners();
    _saveTasks();
  }

  /// Retry a failed download
  Future<void> retryDownload(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    
    _tasks[index] = _tasks[index].copyWith(
      status: DownloadStatus.pending,
      progress: 0.0,
      errorMessage: null,
    );
    notifyListeners();
    _saveTasks();
    
    _executeDownload(taskId);
  }

  /// Open a specific directory
  Future<void> openDirectory(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [dir.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir.path]);
      } else {
        // Linux or other
        await Process.run('xdg-open', [dir.path]);
      }
    }
  }

  /// Open the default download directory
  Future<void> openDownloadDirectory() async {
    await openDirectory(_downloadDirectory);
  }

  /// Get the file path for a completed download
  String? getDownloadedFilePath(String taskId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return null;
    final task = _tasks[index];
    if (task.status == DownloadStatus.completed) {
      return task.savePath;
    }
    return null;
  }

  /// Get active download count
  int get activeDownloadCount => _tasks.where((t) => 
    t.status == DownloadStatus.downloading || t.status == DownloadStatus.pending
  ).length;

  void dispose() {
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    _cancelTokens.clear();
    _tasks.clear();
  }
}

// Custom debug print helper removed to avoid conflict with Flutter's debugPrint
