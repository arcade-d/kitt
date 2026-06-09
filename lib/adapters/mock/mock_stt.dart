import '../../ports/stt_port.dart';

/// STT factice : renvoie une transcription pré-câblée. Sert à exercer le
/// pipeline et la machine d'états sans audio réel.
class MockStt implements SttPort {
  MockStt({this.cannedText = 'Bonjour KITT', this.confidence});

  String cannedText;
  double? confidence;
  bool _endpoint = false;

  @override
  Future<void> initialize() async {}

  @override
  void acceptWaveform(List<double> samples, int sampleRate) {
    // Dès qu'on reçoit de l'audio, on considère un endpoint au buffer suivant.
    _endpoint = true;
  }

  @override
  SttResult getResult() =>
      SttResult(text: cannedText, confidence: confidence, isFinal: _endpoint);

  @override
  bool isEndpoint() => _endpoint;

  @override
  void reset() => _endpoint = false;

  @override
  Future<void> dispose() async {}
}
