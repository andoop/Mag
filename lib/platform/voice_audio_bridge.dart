import 'dart:async';

import 'package:flutter/services.dart';

class VoiceAudioBridge {
  VoiceAudioBridge._();

  static final VoiceAudioBridge instance = VoiceAudioBridge._();

  static const MethodChannel _methodChannel =
      MethodChannel('mobile_agent/voice_audio');
  static const EventChannel _eventChannel =
      EventChannel('mobile_agent/voice_audio_stream');

  Stream<Uint8List>? _audioStream;

  Stream<Uint8List> get audioStream {
    return _audioStream ??= _eventChannel.receiveBroadcastStream().map(
      (event) {
        if (event is Uint8List) return event;
        if (event is ByteData) return event.buffer.asUint8List();
        if (event is List<int>) return Uint8List.fromList(event);
        throw StateError('Unexpected audio chunk type: ${event.runtimeType}');
      },
    );
  }

  Future<bool> hasPermission() async {
    return await _methodChannel.invokeMethod<bool>('hasPermission') ?? false;
  }

  Future<bool> requestPermission() async {
    return await _methodChannel.invokeMethod<bool>('requestPermission') ??
        false;
  }

  Future<void> start({int sampleRate = 16000}) async {
    await _methodChannel.invokeMethod<void>('start', {
      'sampleRate': sampleRate,
    });
  }

  Future<void> stop() async {
    await _methodChannel.invokeMethod<void>('stop');
  }
}
