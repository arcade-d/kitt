import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../ports/audio_in_port.dart';
import 'pcm.dart';

/// Capture micro réelle : `record` (PCM16 16 kHz mono). Convertit chaque chunk
/// en échantillons float et publie le niveau RMS. Porté de Tachikoma
/// `audio_recorder_service.dart`.
class RecordAudioIn implements AudioInPort {
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<double> _level = StreamController<double>.broadcast();
  StreamSubscription<Uint8List>? _sub;
  StreamController<List<double>>? _dataController;

  @override
  Future<Stream<List<double>>> startStream({int sampleRate = 16000}) async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Permission micro refusée');
    }
    // Ferme proprement une capture précédente éventuelle avant d'en ouvrir une.
    await _sub?.cancel();
    await _dataController?.close();
    final raw = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    final controller = StreamController<List<double>>();
    _dataController = controller;
    _sub = raw.listen(
      (bytes) {
        final samples = int16BytesToFloat32(bytes);
        _level.add(calculateAudioLevel(samples));
        controller.add(samples);
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _recorder.stop();
    await _dataController?.close();
    _dataController = null;
  }

  @override
  Stream<double> get audioLevel => _level.stream;
}
