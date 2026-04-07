part of '../session_engine.dart';

class LocalEventBus {
  final StreamController<ServerEvent> _events = StreamController.broadcast();

  Stream<ServerEvent> get stream => _events.stream;

  void emit(ServerEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  Future<void> close() => _events.close();
}
