import 'dart:async';

import '../../ports/wake_word_port.dart';

/// Wake-word factice : on déclenche manuellement [trigger] (sert au repli
/// « bouton maintenir » et aux tests). Aucun vrai KWS.
class MockWakeWord implements WakeWordPort {
  final StreamController<WakeWordEvent> _controller =
      StreamController<WakeWordEvent>.broadcast();
  bool _running = false;

  @override
  Stream<WakeWordEvent> get detections => _controller.stream;

  @override
  Future<void> start() async => _running = true;

  @override
  Future<void> stop() async => _running = false;

  /// Simule une détection (« KITT »).
  void trigger({String keyword = 'KITT', double score = 1.0}) {
    if (_running) {
      _controller.add(WakeWordEvent(keyword: keyword, score: score));
    }
  }

  void dispose() => _controller.close();
}
