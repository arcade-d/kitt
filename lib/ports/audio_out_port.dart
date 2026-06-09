import 'dart:typed_data';

/// Sortie audio (cf. débrief §4.5).
///
/// Aligné sur `AudioPlayerService` de Tachikoma (`just_audio`). Le routage
/// Bluetooth vers l'autoradio, le ducking de la musique et la gestion du focus
/// audio (`audio_session`) sont ABSENTS de Tachikoma et à écrire côté KITT.
abstract class AudioOutPort {
  /// Joue un buffer PCM float au [sampleRate] donné. Complète à la fin de lecture.
  Future<void> playPcm(Float32List samples, int sampleRate);

  Future<void> stop();

  bool get isPlaying;
}
