import 'dart:io';

import 'package:flutter/services.dart';

class StoredConnection {
  const StoredConnection({required this.hostUrl, required this.deviceToken, required this.deviceId, required this.deviceName});
  final String hostUrl;
  final String deviceToken;
  final String deviceId;
  final String deviceName;
}

class ConnectionStore {
  static const MethodChannel _channel = MethodChannel('com.geumyi.gscm/secure_storage');

  Future<StoredConnection?> load() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('loadConnection');
      if (raw == null) return null;
      final host = (raw['host'] as String? ?? '').trim();
      final token = (raw['token'] as String? ?? '').trim();
      final deviceId = (raw['deviceId'] as String? ?? '').trim();
      final deviceName = (raw['deviceName'] as String? ?? _fallbackDeviceName).trim();
      if (host.isEmpty || token.isEmpty || deviceId.isEmpty) return null;
      return StoredConnection(hostUrl: host, deviceToken: token, deviceId: deviceId, deviceName: deviceName);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  String get _fallbackDeviceName => Platform.isIOS ? 'iPhone' : Platform.isAndroid ? 'Android' : 'GSCM device';

  Future<String> deviceId() async {
    try {
      return (await _channel.invokeMethod<String>('deviceId')) ?? '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  Future<String> defaultDeviceName() async {
    try {
      return (await _channel.invokeMethod<String>('deviceName')) ?? _fallbackDeviceName;
    } on PlatformException {
      return _fallbackDeviceName;
    } on MissingPluginException {
      return _fallbackDeviceName;
    }
  }

  Future<void> save(StoredConnection value) async {
    await _channel.invokeMethod<void>('saveConnection', {
      'host': value.hostUrl,
      'token': value.deviceToken,
      'deviceId': value.deviceId,
      'deviceName': value.deviceName,
    });
  }

  Future<void> clear() => _channel.invokeMethod<void>('clearConnection');
}
