import 'dart:typed_data';

/// Convertit des octets PCM int16 (little-endian) en échantillons float
/// normalisés [-1.0, 1.0]. Tolère une longueur impaire (dernier octet ignoré).
/// Porté de Tachikoma `audio_recorder_service.dart`.
List<double> int16BytesToFloat32(Uint8List bytes) {
  final usableLength = bytes.lengthInBytes & ~1;
  if (usableLength == 0) return <double>[];
  final aligned = Uint8List(usableLength);
  aligned.setRange(0, usableLength, bytes);
  final int16Data = aligned.buffer.asInt16List(0, usableLength ~/ 2);
  return List<double>.generate(
    int16Data.length,
    (i) => int16Data[i] / 32768.0,
  );
}

/// Niveau audio (RMS approché) borné [0.0, 1.0] pour le modulateur visuel.
double calculateAudioLevel(List<double> samples) {
  if (samples.isEmpty) return 0.0;
  var sum = 0.0;
  for (final s in samples) {
    sum += s * s;
  }
  final rms = sum / samples.length;
  return (rms * 50).clamp(0.0, 1.0);
}
