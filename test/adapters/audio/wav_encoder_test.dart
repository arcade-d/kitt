import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/audio/wav_encoder.dart';

void main() {
  test('en-tête RIFF/WAVE/fmt + longueur', () {
    final wav = pcmFloat32ToWav(Float32List.fromList([0.0]), 16000);
    expect(wav.length, 46); // 44 + 1 échantillon * 2 octets
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
    final data = ByteData.sublistView(wav);
    expect(data.getUint32(24, Endian.little), 16000); // sampleRate
    expect(data.getUint32(40, Endian.little), 2); // dataSize
    expect(data.getInt16(44, Endian.little), 0); // échantillon 0.0
  });

  test('clamp des échantillons hors [-1, 1]', () {
    final hi = pcmFloat32ToWav(Float32List.fromList([2.0]), 16000);
    expect(ByteData.sublistView(hi).getInt16(44, Endian.little), 32767);
    final lo = pcmFloat32ToWav(Float32List.fromList([-2.0]), 16000);
    expect(ByteData.sublistView(lo).getInt16(44, Endian.little), -32767);
  });
}
