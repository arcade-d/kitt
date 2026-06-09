/// Capture micro (cf. débrief §4.5).
///
/// Aligné sur `AudioRecorderService` de Tachikoma (`record`, PCM16 16 kHz mono,
/// autoGain/echoCancel/noiseSuppress). [audioLevel] expose le RMS qui pilote le
/// modulateur vocal de l'UI.
abstract class AudioInPort {
  /// Démarre la capture et renvoie le flux d'échantillons normalisés.
  Future<Stream<List<double>>> startStream({int sampleRate = 16000});

  Future<void> stop();

  /// Niveau RMS courant dans [0, 1] (pour le modulateur visuel).
  Stream<double> get audioLevel;
}
