import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../ports/stt_port.dart';
import '../models/model_not_available.dart';
import 'stt_mapping.dart';

/// STT réel : `sherpa_onnx` OnlineRecognizer zipformer FR streaming.
/// Porté de Tachikoma `stt_service.dart`. Le dossier modèle est résolu par le
/// `ModelManager` et passé au constructeur.
class SherpaStt implements SttPort {
  SherpaStt(this.modelDir);

  final String modelDir;

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    for (final name in const [
      'encoder.onnx',
      'decoder.onnx',
      'joiner.onnx',
      'tokens.txt',
    ]) {
      if (!File('$modelDir/$name').existsSync()) {
        throw ModelNotAvailable('Fichier STT manquant: $modelDir/$name');
      }
    }
    final config = sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: '$modelDir/encoder.onnx',
          decoder: '$modelDir/decoder.onnx',
          joiner: '$modelDir/joiner.onnx',
        ),
        tokens: '$modelDir/tokens.txt',
        modelType: 'zipformer2',
        numThreads: 2,
      ),
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.2,
      rule3MinUtteranceLength: 20,
    );
    final recognizer = sherpa.OnlineRecognizer(config);
    _recognizer = recognizer;
    _stream = recognizer.createStream();
    _initialized = true;
  }

  @override
  void acceptWaveform(List<double> samples, int sampleRate) {
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return;
    stream.acceptWaveform(
      samples: Float32List.fromList(samples),
      sampleRate: sampleRate,
    );
    recognizer.decode(stream);
  }

  @override
  SttResult getResult() {
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) {
      return mapSttResult('', isFinal: false);
    }
    return mapSttResult(
      recognizer.getResult(stream).text,
      isFinal: recognizer.isEndpoint(stream),
    );
  }

  @override
  bool isEndpoint() {
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return false;
    return recognizer.isEndpoint(stream);
  }

  @override
  void reset() {
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return;
    recognizer.reset(stream);
  }

  @override
  Future<void> dispose() async {
    _stream?.free();
    _recognizer?.free();
    _stream = null;
    _recognizer = null;
    _initialized = false;
  }
}
