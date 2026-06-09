import 'dart:async';

import '../../ports/audio_in_port.dart';

/// Capture factice : émet quelques buffers puis un niveau RMS oscillant pour
/// animer le modulateur visuel.
class MockAudioIn implements AudioInPort {
  final StreamController<double> _level = StreamController<double>.broadcast();
  Timer? _timer;

  @override
  Stream<double> get audioLevel => _level.stream;

  @override
  Future<Stream<List<double>>> startStream({int sampleRate = 16000}) async {
    int tick = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      tick++;
      // Niveau pseudo-aléatoire borné [0.1, 0.9].
      _level.add(0.1 + 0.8 * (0.5 + 0.5 * ((tick * 7) % 11) / 11));
    });
    // Un buffer symbolique d'audio (zéros).
    return Stream<List<double>>.value(List<double>.filled(1600, 0));
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _level.add(0);
  }

  void dispose() => _level.close();
}
