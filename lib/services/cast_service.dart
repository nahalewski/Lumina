import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_chrome_cast/cast_context.dart';
import 'package:flutter_chrome_cast/discovery.dart';
import 'package:flutter_chrome_cast/session.dart';
import 'package:flutter_chrome_cast/media.dart';
import 'package:flutter_chrome_cast/enums.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:http/http.dart' as http;
import '../models/media_model.dart';
import '../models/cast_device_model.dart';

class CastService extends ChangeNotifier {
  static final CastService _instance = CastService._internal();
  factory CastService() => _instance;
  CastService._internal();

  MDnsClient? _mdnsClient;
  
  List<UnifiedDevice> _devices = [];
  UnifiedDevice? _connectedDevice;
  bool _isConnecting = false;

  List<UnifiedDevice> get devices => _devices;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _connectedDevice != null;
  UnifiedDevice? get connectedDevice => _connectedDevice;

  Future<void> initialize() async {
    const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;
    GoogleCastOptions? options;

    if (Platform.isIOS) {
      options = IOSGoogleCastOptions(
        GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
      );
    } else if (Platform.isAndroid) {
      options = GoogleCastOptionsAndroid(
        appId: appId,
      );
    }

    if (options != null) {
      await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
    }

    GoogleCastDiscoveryManager.instance.devicesStream.listen((googleDevices) {
      _updateGoogleDevices(googleDevices);
    });
  }

  void _updateGoogleDevices(List<GoogleCastDevice> googleDevices) {
    _devices.removeWhere((d) => d.type == DeviceType.chromecast);
    for (var d in googleDevices) {
      _devices.add(UnifiedDevice(
        id: d.deviceID,
        name: d.friendlyName,
        ip: '',
        port: 0,
        type: DeviceType.chromecast,
        originalDevice: d,
      ));
    }
    notifyListeners();
  }

  Future<void> startDiscovery() async {
    GoogleCastDiscoveryManager.instance.startDiscovery();
    _startAirPlayDiscovery();
  }

  Future<void> _startAirPlayDiscovery() async {
    _mdnsClient = MDnsClient();
    await _mdnsClient!.start();

    const String name = '_airplay._tcp.local';
    await for (final PtrResourceRecord ptr in _mdnsClient!.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(name))) {
      await for (final SrvResourceRecord srv in _mdnsClient!.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))) {
        await for (final IPAddressResourceRecord ip in _mdnsClient!.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))) {
          
          final existing = _devices.indexWhere((d) => d.id == ptr.domainName);
          if (existing == -1) {
            _devices.add(UnifiedDevice(
              id: ptr.domainName,
              name: ptr.domainName.split('.').first,
              ip: ip.address.address,
              port: srv.port,
              type: DeviceType.airplay,
            ));
            notifyListeners();
          }
        }
      }
    }
  }

  void stopDiscovery() {
    GoogleCastDiscoveryManager.instance.stopDiscovery();
    _mdnsClient?.stop();
    _mdnsClient = null;
  }

  Future<bool> connectToDevice(UnifiedDevice device) async {
    _isConnecting = true;
    notifyListeners();

    if (device.type == DeviceType.chromecast) {
      try {
        await GoogleCastSessionManager.instance.startSessionWithDevice(device.originalDevice as GoogleCastDevice);
        _connectedDevice = device;
        _isConnecting = false;
        notifyListeners();
        return true;
      } catch (e) {
        debugPrint('[CastService] Chromecast connection error: $e');
      }
    } else {
      _connectedDevice = device;
      _isConnecting = false;
      notifyListeners();
      return true;
    }

    _isConnecting = false;
    notifyListeners();
    return false;
  }

  Future<void> disconnect() async {
    if (_connectedDevice?.type == DeviceType.chromecast) {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    }
    _connectedDevice = null;
    notifyListeners();
  }

  Future<void> castMedia(MediaFile media, String streamUrl, {Duration? startPosition}) async {
    if (_connectedDevice == null) return;

    if (_connectedDevice!.type == DeviceType.chromecast) {
      await _castToChromecast(media, streamUrl, startPosition);
    } else {
      await _castToAirPlay(media, streamUrl, startPosition);
    }
  }

  Future<void> _castToChromecast(MediaFile media, String streamUrl, Duration? startPosition) async {
    final mediaInfo = GoogleCastMediaInformationIOS(
      contentId: media.id,
      contentUrl: Uri.parse(streamUrl),
      streamType: CastMediaStreamType.buffered,
      contentType: _getMimeType(media.extension),
      metadata: GoogleCastMovieMediaMetadata(
        title: media.title,
        studio: 'Lumina Media',
        releaseDate: DateTime.now(),
        images: [
          if (media.thumbnailUrl != null)
            GoogleCastImage(url: Uri.parse(media.thumbnailUrl!)),
        ],
      ),
    );

    await GoogleCastRemoteMediaClient.instance.loadMedia(
      mediaInfo,
      autoPlay: true,
      playPosition: startPosition ?? Duration.zero,
    );
  }

  Future<void> _castToAirPlay(MediaFile media, String streamUrl, Duration? startPosition) async {
    final device = _connectedDevice!;
    final url = 'http://${device.ip}:${device.port}/play';
    
    final body = 'Content-Location: $streamUrl\n'
                 'Start-Position: ${startPosition?.inSeconds.toDouble() ?? 0.0}\n';
    
    try {
      await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'text/parameters',
          'User-Agent': 'MediaControl/1.0',
          'X-Apple-Session-ID': '00000000-0000-0000-0000-000000000000',
        },
        body: body,
      );
    } catch (e) {
      debugPrint('[CastService] AirPlay error: $e');
    }
  }

  Future<void> play() async {
    if (_connectedDevice?.type == DeviceType.chromecast) {
      await GoogleCastRemoteMediaClient.instance.play();
    } else {
       await _airplayCommand('rate?value=1');
    }
  }

  Future<void> pause() async {
    if (_connectedDevice?.type == DeviceType.chromecast) {
      await GoogleCastRemoteMediaClient.instance.pause();
    } else {
       await _airplayCommand('rate?value=0');
    }
  }

  Future<void> stop() async {
    if (_connectedDevice?.type == DeviceType.chromecast) {
      await GoogleCastRemoteMediaClient.instance.stop();
    } else {
       await _airplayCommand('stop');
    }
  }

  Future<void> seek(Duration position) async {
    if (_connectedDevice?.type == DeviceType.chromecast) {
      await GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(position: position),
      );
    } else {
      await _airplayCommand('scrub?position=${position.inSeconds.toDouble()}');
    }
  }

  Future<void> _airplayCommand(String command) async {
    if (_connectedDevice == null) return;
    final url = 'http://${_connectedDevice!.ip}:${_connectedDevice!.port}/$command';
    try {
      await http.post(Uri.parse(url), headers: {'User-Agent': 'MediaControl/1.0'});
    } catch (e) {
      debugPrint('[CastService] AirPlay Command error: $e');
    }
  }

  String _getMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case '.mp4': return 'video/mp4';
      case '.mkv': return 'video/x-matroska';
      case '.mp3': return 'audio/mpeg';
      case '.wav': return 'audio/wav';
      default: return 'video/mp4';
    }
  }
}
