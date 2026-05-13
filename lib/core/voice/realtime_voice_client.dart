import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models.dart';

enum VoiceRealtimeUpdateType {
  connected,
  partial,
  finalText,
  error,
  closed,
}

class VoiceRealtimeUpdate {
  const VoiceRealtimeUpdate({
    required this.type,
    this.text = '',
    this.message = '',
  });

  final VoiceRealtimeUpdateType type;
  final String text;
  final String message;
}

abstract class VoiceRealtimeClient {
  Stream<VoiceRealtimeUpdate> get updates;

  Future<void> connect();

  Future<void> sendAudio(Uint8List pcm16);

  Future<void> finish();

  Future<void> close();
}

VoiceRealtimeClient createVoiceRealtimeClient(VoiceRealtimeConfig config) {
  switch (config.provider) {
    case VoiceRealtimeProvider.qwen:
      return QwenRealtimeVoiceClient(config);
    case VoiceRealtimeProvider.doubao:
      return DoubaoRealtimeVoiceClient(config);
  }
}

class QwenRealtimeVoiceClient implements VoiceRealtimeClient {
  QwenRealtimeVoiceClient(this.config);

  final VoiceRealtimeConfig config;
  final _updates = StreamController<VoiceRealtimeUpdate>.broadcast();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  String _lastText = '';

  @override
  Stream<VoiceRealtimeUpdate> get updates => _updates.stream;

  @override
  Future<void> connect() async {
    final qwen = config.qwen;
    if (!qwen.isConfigured) {
      throw StateError('Qwen DashScope API Key is required.');
    }
    final base = Uri.parse(qwen.endpoint);
    final uri = base.replace(
      queryParameters: {
        ...base.queryParameters,
        'model': qwen.model,
      },
    );
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer ${qwen.apiKey}',
        'OpenAI-Beta': 'realtime=v1',
      },
    );
    _socket = socket;
    _subscription = socket.listen(
      _handleMessage,
      onError: (error) {
        _updates.add(VoiceRealtimeUpdate(
          type: VoiceRealtimeUpdateType.error,
          message: error.toString(),
        ));
      },
      onDone: () {
        _updates.add(const VoiceRealtimeUpdate(
          type: VoiceRealtimeUpdateType.closed,
        ));
      },
    );
    _sendJson({
      'event_id': _eventId(),
      'type': 'session.update',
      'session': {
        'modalities': ['text'],
        'input_audio_format': 'pcm',
        'sample_rate': config.sampleRate,
        'input_audio_transcription': {
          'language': config.language,
        },
        if (config.serverVad)
          'turn_detection': {'type': 'server_vad'}
        else
          'turn_detection': null,
      },
    });
    _updates.add(const VoiceRealtimeUpdate(
      type: VoiceRealtimeUpdateType.connected,
    ));
  }

  @override
  Future<void> sendAudio(Uint8List pcm16) async {
    if (pcm16.isEmpty) return;
    _sendJson({
      'event_id': _eventId(),
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm16),
    });
  }

  @override
  Future<void> finish() async {
    if (!config.serverVad) {
      _sendJson({
        'event_id': _eventId(),
        'type': 'input_audio_buffer.commit',
      });
    }
    _sendJson({
      'event_id': _eventId(),
      'type': 'session.finish',
    });
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    await _updates.close();
  }

  void _sendJson(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null) return;
    socket.add(jsonEncode(payload));
  }

  void _handleMessage(dynamic message) {
    if (message is! String) return;
    final decoded = jsonDecode(message);
    if (decoded is! Map) return;
    final data = Map<String, dynamic>.from(decoded);
    final type = data['type'] as String? ?? '';
    if (type == 'conversation.item.input_audio_transcription.text' ||
        type == 'conversation.item.input_audio_transcription.delta') {
      final text = _extractText(data, preferDelta: true);
      if (text.isNotEmpty) {
        _lastText = text;
        _updates.add(VoiceRealtimeUpdate(
          type: VoiceRealtimeUpdateType.partial,
          text: _lastText,
        ));
      }
      return;
    }
    if (type == 'conversation.item.input_audio_transcription.completed' ||
        type == 'session.finished') {
      final text = _extractText(data, preferDelta: false);
      if (text.isNotEmpty) _lastText = text;
      _updates.add(VoiceRealtimeUpdate(
        type: VoiceRealtimeUpdateType.finalText,
        text: _lastText,
      ));
      return;
    }
    if (type.contains('input_audio_transcription')) {
      final text = _extractText(data, preferDelta: true);
      if (text.isNotEmpty && text != _lastText) {
        _lastText = text;
        _updates.add(VoiceRealtimeUpdate(
          type: VoiceRealtimeUpdateType.partial,
          text: _lastText,
        ));
      }
      return;
    }
    if (type.endsWith('.error') || type == 'error') {
      _updates.add(VoiceRealtimeUpdate(
        type: VoiceRealtimeUpdateType.error,
        message: _extractError(data),
      ));
    }
  }
}

class DoubaoRealtimeVoiceClient implements VoiceRealtimeClient {
  DoubaoRealtimeVoiceClient(this.config);

  final VoiceRealtimeConfig config;
  final _updates = StreamController<VoiceRealtimeUpdate>.broadcast();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  int _sequence = 1;
  String _lastText = '';

  @override
  Stream<VoiceRealtimeUpdate> get updates => _updates.stream;

  @override
  Future<void> connect() async {
    final doubao = config.doubao;
    if (!doubao.isConfigured) {
      throw StateError('Doubao voice credentials are required.');
    }
    final requestId = _uuidV4();
    final headers = <String, dynamic>{
      'X-Api-Resource-Id': doubao.resourceId,
      'X-Api-Request-Id': requestId,
      'X-Api-Sequence': '-1',
      'X-Api-Connect-Id': requestId,
    };
    if (doubao.usesNewApiKey) {
      headers['X-Api-Key'] = doubao.apiKey;
    } else {
      headers['X-Api-App-Key'] = doubao.appKey;
      headers['X-Api-Access-Key'] = doubao.accessKey;
    }
    final socket = await WebSocket.connect(
      doubao.endpoint,
      headers: headers,
    );
    _socket = socket;
    _subscription = socket.listen(
      _handleMessage,
      onError: (error) {
        _updates.add(VoiceRealtimeUpdate(
          type: VoiceRealtimeUpdateType.error,
          message: error.toString(),
        ));
      },
      onDone: () {
        _updates.add(const VoiceRealtimeUpdate(
          type: VoiceRealtimeUpdateType.closed,
        ));
      },
    );
    socket.add(_buildFrame(
      messageType: 0x1,
      flags: 0x0,
      serialization: 0x1,
      compression: 0x1,
      payload: utf8.encode(jsonEncode(_initialDoubaoRequest(requestId))),
    ));
    _updates.add(const VoiceRealtimeUpdate(
      type: VoiceRealtimeUpdateType.connected,
    ));
  }

  @override
  Future<void> sendAudio(Uint8List pcm16) async {
    if (pcm16.isEmpty) return;
    _socket?.add(_buildFrame(
      messageType: 0x2,
      flags: 0x1,
      serialization: 0x0,
      compression: 0x1,
      sequence: _sequence++,
      payload: pcm16,
    ));
  }

  @override
  Future<void> finish() async {
    _socket?.add(_buildFrame(
      messageType: 0x2,
      flags: 0x3,
      serialization: 0x0,
      compression: 0x1,
      sequence: -_sequence.abs(),
      payload: Uint8List(0),
    ));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    await _updates.close();
  }

  Map<String, dynamic> _initialDoubaoRequest(String requestId) {
    return {
      'user': {'uid': 'mag'},
      'audio': {
        'format': 'pcm',
        'sample_rate': config.sampleRate,
        'bits': 16,
        'channel': 1,
        'language': config.language,
      },
      'request': {
        'model_name': config.doubao.model,
        'enable_itn': true,
        'enable_punc': true,
        'enable_ddc': true,
        'show_utterances': true,
        'result_type': 'single',
        'enable_accelerate_text': true,
        'sequence': 1,
        'reqid': requestId,
      },
    };
  }

  void _handleMessage(dynamic message) {
    if (message is! List<int>) return;
    try {
      final parsed = _parseDoubaoFrame(Uint8List.fromList(message));
      if (parsed.errorMessage != null) {
        _updates.add(VoiceRealtimeUpdate(
          type: VoiceRealtimeUpdateType.error,
          message: parsed.errorMessage!,
        ));
        return;
      }
      final decoded = jsonDecode(utf8.decode(parsed.payload));
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);
      final text = _extractText(data, preferDelta: false);
      if (text.isEmpty) return;
      _lastText = text;
      _updates.add(VoiceRealtimeUpdate(
        type: parsed.isFinal
            ? VoiceRealtimeUpdateType.finalText
            : VoiceRealtimeUpdateType.partial,
        text: _lastText,
      ));
    } catch (error) {
      _updates.add(VoiceRealtimeUpdate(
        type: VoiceRealtimeUpdateType.error,
        message: error.toString(),
      ));
    }
  }
}

class _DoubaoFrame {
  const _DoubaoFrame({
    required this.payload,
    required this.isFinal,
    this.errorMessage,
  });

  final Uint8List payload;
  final bool isFinal;
  final String? errorMessage;
}

Uint8List _buildFrame({
  required int messageType,
  required int flags,
  required int serialization,
  required int compression,
  int? sequence,
  required List<int> payload,
}) {
  final compressed =
      compression == 0x1 ? gzip.encode(payload) : Uint8List.fromList(payload);
  final hasSequence = sequence != null;
  final header = <int>[
    0x11,
    ((messageType & 0x0f) << 4) | (flags & 0x0f),
    ((serialization & 0x0f) << 4) | (compression & 0x0f),
    0x00,
  ];
  final bytes = BytesBuilder();
  bytes.add(header);
  if (hasSequence) {
    bytes.add(_int32Bytes(sequence));
  }
  bytes.add(_uint32Bytes(compressed.length));
  bytes.add(compressed);
  return bytes.takeBytes();
}

_DoubaoFrame _parseDoubaoFrame(Uint8List frame) {
  if (frame.length < 8) {
    throw const FormatException('Doubao frame is too short.');
  }
  final headerSize = (frame[0] & 0x0f) * 4;
  final messageType = (frame[1] >> 4) & 0x0f;
  final flags = frame[1] & 0x0f;
  final compression = frame[2] & 0x0f;
  var offset = headerSize;
  if (messageType == 0x0f) {
    final code = _readInt32(frame, offset);
    offset += 4;
    final size = _readInt32(frame, offset);
    offset += 4;
    final end = min(offset + size, frame.length);
    final message = utf8.decode(frame.sublist(offset, end));
    return _DoubaoFrame(
      payload: Uint8List(0),
      isFinal: true,
      errorMessage: 'Doubao error $code: $message',
    );
  }
  if (flags == 0x1 || flags == 0x3) {
    offset += 4;
  }
  final size = _readInt32(frame, offset);
  offset += 4;
  final end = min(offset + size, frame.length);
  final payload = frame.sublist(offset, end);
  final decoded = compression == 0x1 ? gzip.decode(payload) : payload;
  return _DoubaoFrame(
    payload: Uint8List.fromList(decoded),
    isFinal: flags == 0x2 || flags == 0x3,
  );
}

List<int> _uint32Bytes(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

List<int> _int32Bytes(int value) {
  final data = ByteData(4)..setInt32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int _readInt32(Uint8List bytes, int offset) {
  return ByteData.sublistView(bytes, offset, offset + 4)
      .getInt32(0, Endian.big);
}

String _eventId() => 'event_${DateTime.now().microsecondsSinceEpoch}';

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final s = bytes.map(hex).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
      '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

String _extractError(Map<String, dynamic> data) {
  final error = data['error'];
  if (error is String) return error;
  if (error is Map) {
    final message = error['message'];
    if (message is String) return message;
  }
  final message = data['message'];
  if (message is String) return message;
  return jsonEncode(data);
}

String _extractText(dynamic value, {required bool preferDelta}) {
  if (value is Map) {
    final directKeys = preferDelta
        ? const ['delta', 'text', 'transcript', 'utterance', 'result']
        : const ['text', 'transcript', 'utterance', 'result'];
    for (final key in directKeys) {
      final found = value[key];
      if (found is String && found.trim().isNotEmpty) return found;
    }
    for (final key in const [
      'payload',
      'data',
      'result',
      'results',
      'utterances',
      'additions'
    ]) {
      final nested = value[key];
      final found = _extractText(nested, preferDelta: preferDelta);
      if (found.isNotEmpty) return found;
    }
    for (final nested in value.values) {
      final found = _extractText(nested, preferDelta: preferDelta);
      if (found.isNotEmpty) return found;
    }
  }
  if (value is List) {
    for (final item in value.reversed) {
      final found = _extractText(item, preferDelta: preferDelta);
      if (found.isNotEmpty) return found;
    }
  }
  return '';
}
