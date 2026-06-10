import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../ports/audio_in_port.dart';
import '../../ports/wake_word_port.dart';
import '../models/model_not_available.dart';

/// Détection du wake-word « KITT » via [sherpa.KeywordSpotter] — 100 % local,
/// aucun appel cloud, sans Porcupine.
///
/// **FONDATION EXPÉRIMENTALE — NON CÂBLÉE** : le pipeline actif reste le
/// push-to-talk ([MockWakeWord]). Cet adapter ne sera activé que lorsqu'un
/// modèle transducteur KWS sera disponible (encoder/decoder/joiner.onnx +
/// tokens.txt dans [modelDir]) et que le mot-clé sera tokenisé pour ce modèle
/// (paramètre [keywords]).
///
/// **Avertissement de concurrence** : la capture micro est continue ; ne pas
/// activer cet adapter en même temps que le push-to-talk ([RecordAudioIn] /
/// [AudioInPort.startStream]) — les deux chemins se disputent le micro et l'un
/// des deux échouera.
///
/// Usage (une fois câblé) :
/// ```dart
/// final wakeWord = SherpaWakeWord(
///   modelDir: mm.kwsModelDir,
///   audioIn: RecordAudioIn(),
///   keywords: 'k i t t',   // séquence de tokens pour le modèle
/// );
/// await wakeWord.start();
/// wakeWord.detections.listen((e) => print('Detected: ${e.keyword}'));
/// ```
class SherpaWakeWord implements WakeWordPort {
  SherpaWakeWord({
    required this.modelDir,
    required AudioInPort audioIn,
    this.keywords = '',
    this.sampleRate = 16000,
  }) : _audioIn = audioIn;

  /// Répertoire contenant encoder.onnx, decoder.onnx, joiner.onnx, tokens.txt.
  final String modelDir;

  /// Séquence de tokens représentant le mot-clé pour ce modèle.
  /// Laisser vide si les mots-clés sont fournis via [KeywordSpotterConfig.keywordsFile].
  final String keywords;

  /// Fréquence d'échantillonnage attendue par le modèle (défaut : 16 000 Hz).
  final int sampleRate;

  final AudioInPort _audioIn;

  final StreamController<WakeWordEvent> _controller =
      StreamController<WakeWordEvent>.broadcast();

  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _kwStream;
  StreamSubscription<List<double>>? _micSub;
  bool _running = false;

  @override
  Stream<WakeWordEvent> get detections => _controller.stream;

  @override
  Future<void> start() async {
    if (_running) return;

    // Vérifie la présence des fichiers modèle requis.
    for (final name in const [
      'encoder.onnx',
      'decoder.onnx',
      'joiner.onnx',
      'tokens.txt',
    ]) {
      if (!File('$modelDir/$name').existsSync()) {
        throw ModelNotAvailable('Fichier KWS manquant : $modelDir/$name');
      }
    }

    final config = sherpa.KeywordSpotterConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: '$modelDir/encoder.onnx',
          decoder: '$modelDir/decoder.onnx',
          joiner: '$modelDir/joiner.onnx',
        ),
        tokens: '$modelDir/tokens.txt',
        numThreads: 1,
      ),
    );

    final spotter = sherpa.KeywordSpotter(config);
    _spotter = spotter;

    final kwStream = keywords.isEmpty
        ? spotter.createStream()
        : spotter.createStream(keywords: keywords);
    _kwStream = kwStream;

    _running = true;

    final micStream = await _audioIn.startStream(sampleRate: sampleRate);
    _micSub = micStream.listen(
      (final List<double> chunk) {
        final currentStream = _kwStream;
        final currentSpotter = _spotter;
        if (currentStream == null || currentSpotter == null) return;

        currentStream.acceptWaveform(
          samples: Float32List.fromList(chunk),
          sampleRate: sampleRate,
        );

        while (currentSpotter.isReady(currentStream)) {
          currentSpotter.decode(currentStream);
        }

        final kw = currentSpotter.getResult(currentStream).keyword;
        if (kw.isNotEmpty) {
          _controller.add(WakeWordEvent(keyword: kw));
          // reset() existe dans sherpa_onnx 1.13.2 (resetKeywordStream) ;
          // on réinitialise le stream en place plutôt que de le recréer.
          currentSpotter.reset(currentStream);
        }
      },
      onError: (final Object e, final StackTrace st) {
        _controller.addError(e, st);
      },
    );
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    await _micSub?.cancel();
    _micSub = null;

    await _audioIn.stop();

    _kwStream?.free();
    _kwStream = null;

    _spotter?.free();
    _spotter = null;
  }
}
