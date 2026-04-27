enum DeviceType { chromecast, airplay }

class UnifiedDevice {
  final String id;
  final String name;
  final String ip;
  final int port;
  final DeviceType type;
  final dynamic originalDevice; // Store GoogleCastDevice or MDNS data

  UnifiedDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.type,
    this.originalDevice,
  });
}
