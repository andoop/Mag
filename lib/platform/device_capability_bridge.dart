import 'dart:io';

import 'package:flutter/services.dart';

class DeviceCapabilityFile {
  const DeviceCapabilityFile({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.size,
  });

  final String path;
  final String name;
  final String mimeType;
  final int size;

  factory DeviceCapabilityFile.fromJson(Map<String, dynamic> json) {
    return DeviceCapabilityFile(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? 'file',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

class DeviceCapabilityBridge {
  DeviceCapabilityBridge._();

  static const MethodChannel _channel =
      MethodChannel('mobile_agent/device_capabilities');

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static Future<dynamic> invoke(
      String capabilityId, Map<String, dynamic> input) {
    if (!isSupported) {
      throw UnsupportedError(
          'Device capabilities are only supported on Android and iOS.');
    }
    return _channel.invokeMethod<dynamic>('invoke', {
      'capabilityId': capabilityId,
      'input': input,
    });
  }

  static Future<List<DeviceCapabilityFile>> pickFiles({
    String? accept,
    bool multiple = false,
  }) async {
    final result = await invoke('files.pick', {
      'accept': accept ?? '',
      'multiple': multiple,
    });
    return (result as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) =>
            DeviceCapabilityFile.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.path.isNotEmpty)
        .toList();
  }

  static Future<DeviceCapabilityFile?> capturePhoto() async {
    final result = await invoke('media.capturePhoto', const {});
    if (result is! Map) return null;
    final file =
        DeviceCapabilityFile.fromJson(Map<String, dynamic>.from(result));
    return file.path.isEmpty ? null : file;
  }

  static Future<DeviceCapabilityFile?> recordAudio() async {
    final result = await invoke('media.recordAudio', const {});
    if (result is! Map) return null;
    final file =
        DeviceCapabilityFile.fromJson(Map<String, dynamic>.from(result));
    return file.path.isEmpty ? null : file;
  }

  static Future<DeviceCapabilityFile?> recordVideo() async {
    final result = await invoke('media.recordVideo', const {});
    if (result is! Map) return null;
    final file =
        DeviceCapabilityFile.fromJson(Map<String, dynamic>.from(result));
    return file.path.isEmpty ? null : file;
  }
}
