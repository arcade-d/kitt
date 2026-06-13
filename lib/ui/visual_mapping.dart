import '../application/pipeline_state.dart';

/// Mode d'animation de la voicebox (oscilloscope) selon l'état.
enum VoiceboxMode { flat, mic, noise, speaking, pulse }

/// Vitesse du balayage Larson selon l'état (unités arbitraires, cohérentes
/// avec l'ancien comportement : veille lente, réflexion rapide).
double scannerSpeed(PipelineState state) {
  switch (state) {
    case PipelineState.idle:
      return 0.6;
    case PipelineState.listening:
    case PipelineState.clarifying:
      return 2.4;
    case PipelineState.thinking:
      return 3.6;
    case PipelineState.responding:
      return 1.8;
  }
}

/// Mode de la voicebox selon l'état.
VoiceboxMode voiceboxMode(PipelineState state) {
  switch (state) {
    case PipelineState.idle:
      return VoiceboxMode.flat;
    case PipelineState.listening:
      return VoiceboxMode.mic;
    case PipelineState.thinking:
      return VoiceboxMode.noise;
    case PipelineState.responding:
      return VoiceboxMode.speaking;
    case PipelineState.clarifying:
      return VoiceboxMode.pulse;
  }
}
