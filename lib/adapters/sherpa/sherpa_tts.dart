import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../ports/tts_port.dart';
import '../models/model_not_available.dart';
import 'espeak_text.dart';

/// TTS réel : `sherpa_onnx` OfflineTts VITS/Piper FR.
/// Porté de Tachikoma `tts_service.dart`. Non streaming (synthèse en bloc).
class SherpaTts implements TtsPort {
  SherpaTts(this.modelDir);

  final String modelDir;

  sherpa.OfflineTts? _tts;

  @override
  Future<void> initialize() async {
    if (_tts != null) return;
    if (!File('$modelDir/model.onnx').existsSync() ||
        !File('$modelDir/tokens.txt').existsSync()) {
      throw ModelNotAvailable('Modèle TTS manquant dans $modelDir');
    }
    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: '$modelDir/model.onnx',
          tokens: '$modelDir/tokens.txt',
          dataDir: '$modelDir/espeak-ng-data',
        ),
        numThreads: 2,
      ),
    );
    _tts = sherpa.OfflineTts(config);
  }

  @override
  Future<Float32List?> synthesize(
    String text, {
    int speakerId = 0,
    double speed = 1.0,
  }) async {
    final tts = _tts;
    if (tts == null) return null;
    final clean = sanitizeForEspeak(text);
    if (clean.trim().isEmpty) return null;
    final audio = tts.generate(text: clean, sid: speakerId, speed: speed);
    return audio.samples;
  }

  @override
  int get sampleRate => _tts?.sampleRate ?? 22050;

  @override
  Future<void> dispose() async {
    _tts?.free();
    _tts = null;
  }
}
