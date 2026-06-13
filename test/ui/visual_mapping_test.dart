import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/application/pipeline_state.dart';
import 'package:kitt/ui/visual_mapping.dart';

void main() {
  group('scannerSpeed', () {
    test('veille lente, réflexion la plus rapide', () {
      expect(scannerSpeed(PipelineState.idle), lessThan(1.0));
      expect(
        scannerSpeed(PipelineState.thinking),
        greaterThan(scannerSpeed(PipelineState.listening)),
      );
      expect(
        scannerSpeed(PipelineState.listening),
        greaterThan(scannerSpeed(PipelineState.idle)),
      );
    });
  });

  group('voiceboxMode', () {
    test('mappe chaque état vers un mode', () {
      expect(voiceboxMode(PipelineState.idle), VoiceboxMode.flat);
      expect(voiceboxMode(PipelineState.listening), VoiceboxMode.mic);
      expect(voiceboxMode(PipelineState.thinking), VoiceboxMode.noise);
      expect(voiceboxMode(PipelineState.responding), VoiceboxMode.speaking);
      expect(voiceboxMode(PipelineState.clarifying), VoiceboxMode.pulse);
    });
  });
}
