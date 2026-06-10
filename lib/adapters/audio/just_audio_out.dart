import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import '../../ports/audio_out_port.dart';
import 'wav_encoder.dart';

/// Sortie audio réelle : `just_audio` jouant le PCM enveloppé en WAV mémoire.
/// Porté de Tachikoma `audio_player_service.dart`. Le routage Bluetooth/ducking
/// (`audio_session`) est hors périmètre (KITT-neuf).
class JustAudioOut implements AudioOutPort {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> playPcm(Float32List samples, int sampleRate) async {
    if (samples.isEmpty) return;
    final wav = pcmFloat32ToWav(samples, sampleRate);
    await _player.setAudioSource(_WavSource(wav));
    await _player.play();
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  bool get isPlaying => _player.playing;
}

/// Source `just_audio` servant des octets WAV depuis la mémoire.
// ignore: experimental_member_use
class _WavSource extends StreamAudioSource {
  _WavSource(this._bytes);

  final Uint8List _bytes;

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? _bytes.length;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream<List<int>>.value(_bytes.sublist(s, e)),
      contentType: 'audio/wav',
    );
  }
}
