import 'dart:math' as math;
import 'dart:typed_data';

/// Filtre vocal « KITT » : grave (low-pass + boost des graves), radio
/// (saturation douce) et synthétique (anneau/ring-mod léger). Pur et
/// déterministe : même entrée → même sortie. Sortie bornée dans (-1, 1).
Float32List applyKittFilter(Float32List samples, int sampleRate) {
  final n = samples.length;
  if (n == 0) return Float32List(0);

  double onePoleAlpha(double fc) {
    final dt = 1.0 / sampleRate;
    final rc = 1.0 / (2 * math.pi * fc);
    return dt / (rc + dt);
  }

  final aWarm = onePoleAlpha(3200); // adoucit les aigus (chaleur)
  final aBass = onePoleAlpha(180); // extrait les graves
  const ringMix = 0.12; // dosage du ring-mod synthétique
  const bassBoost = 0.6;
  const drive = 1.4; // saturation « radio »
  final ringStep = 2 * math.pi * 60.0 / sampleRate; // porteuse 60 Hz

  final out = Float32List(n);
  var warm = 0.0;
  var bass = 0.0;
  for (var i = 0; i < n; i++) {
    final x = samples[i];
    warm += aWarm * (x - warm);
    bass += aBass * (x - bass);
    var y = warm + bassBoost * bass; // grave + chaleur
    final carrier = math.sin(ringStep * i);
    y = y * (1 - ringMix) + (y * carrier) * ringMix; // anneau synthétique
    final driven = drive * y;
    out[i] = driven / (1 + driven.abs()); // saturation douce, bornée (-1, 1)
  }
  return out;
}
