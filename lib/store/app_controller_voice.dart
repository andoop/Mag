// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'app_controller.dart';

extension AppControllerVoice on AppController {
  Future<void> saveVoiceConfig(VoiceRealtimeConfig config) async {
    final saved = await _client!.saveVoiceConfig(config);
    state = state.copyWith(voiceConfig: saved, error: null);
    notifyListeners();
  }

  Future<void> startVoiceInput({
    required ValueChanged<String> onText,
  }) async {
    if (state.voiceConnecting || state.voiceRecording) return;
    final config = state.voiceConfig;
    if (!config.enabled) {
      throw StateError('Voice input is disabled. 请先在设置里启用语音输入。');
    }
    if (!config.selectedProviderConfigured) {
      throw StateError(
          'Voice provider credentials are missing. 请先配置语音 Provider 凭证。');
    }
    state = state.copyWith(
      voiceConnecting: true,
      voiceRecording: false,
      voiceError: null,
    );
    notifyListeners();
    try {
      final audio = VoiceAudioBridge.instance;
      final allowed =
          await audio.hasPermission() || await audio.requestPermission();
      if (!allowed) {
        throw StateError('Microphone permission denied. 麦克风权限未开启。');
      }
      final client = createVoiceRealtimeClient(config);
      _voiceClient = client;
      _voiceUpdateSubscription = client.updates.listen((update) {
        switch (update.type) {
          case VoiceRealtimeUpdateType.connected:
            state = state.copyWith(
              voiceConnecting: false,
              voiceRecording: true,
              voiceError: null,
            );
            notifyListeners();
            return;
          case VoiceRealtimeUpdateType.partial:
          case VoiceRealtimeUpdateType.finalText:
            if (update.text.trim().isNotEmpty) {
              onText(update.text);
            }
            return;
          case VoiceRealtimeUpdateType.error:
            state = state.copyWith(
              voiceConnecting: false,
              voiceRecording: false,
              voiceError: update.message,
            );
            notifyListeners();
            return;
          case VoiceRealtimeUpdateType.closed:
            state = state.copyWith(
              voiceConnecting: false,
              voiceRecording: false,
            );
            notifyListeners();
            return;
        }
      });
      await client.connect();
      _voiceAudioSubscription = audio.audioStream.listen(client.sendAudio);
      await audio.start(sampleRate: config.sampleRate);
    } catch (error) {
      await stopVoiceInput();
      state = state.copyWith(
        voiceConnecting: false,
        voiceRecording: false,
        voiceError: error.toString(),
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopVoiceInput() async {
    await VoiceAudioBridge.instance.stop();
    await _voiceAudioSubscription?.cancel();
    _voiceAudioSubscription = null;
    final client = _voiceClient;
    _voiceClient = null;
    if (client != null) {
      try {
        await client.finish();
        await Future<void>.delayed(const Duration(milliseconds: 800));
      } catch (_) {}
      await _voiceUpdateSubscription?.cancel();
      _voiceUpdateSubscription = null;
      await client.close();
    } else {
      await _voiceUpdateSubscription?.cancel();
      _voiceUpdateSubscription = null;
    }
    if (state.voiceConnecting || state.voiceRecording) {
      state = state.copyWith(
        voiceConnecting: false,
        voiceRecording: false,
      );
      notifyListeners();
    }
  }
}
