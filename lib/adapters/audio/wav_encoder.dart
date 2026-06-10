import 'dart:typed_data';

/// Encapsule des échantillons PCM Float32 mono dans un conteneur WAV
/// (PCM int16 little-endian, en-tête RIFF 44 octets). Pur, testable.
/// Porté de Tachikoma `audio_player_service.dart` (`_createWav`).
Uint8List pcmFloat32ToWav(Float32List samples, int sampleRate) {
  final numSamples = samples.length;
  const numChannels = 1;
  const bitsPerSample = 16;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  const blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataSize = numSamples * blockAlign;
  final fileSize = 36 + dataSize;

  final buffer = ByteData(44 + dataSize);
  var offset = 0;

  // RIFF
  buffer.setUint8(offset++, 0x52); // R
  buffer.setUint8(offset++, 0x49); // I
  buffer.setUint8(offset++, 0x46); // F
  buffer.setUint8(offset++, 0x46); // F
  buffer.setUint32(offset, fileSize, Endian.little);
  offset += 4;
  buffer.setUint8(offset++, 0x57); // W
  buffer.setUint8(offset++, 0x41); // A
  buffer.setUint8(offset++, 0x56); // V
  buffer.setUint8(offset++, 0x45); // E

  // fmt
  buffer.setUint8(offset++, 0x66); // f
  buffer.setUint8(offset++, 0x6D); // m
  buffer.setUint8(offset++, 0x74); // t
  buffer.setUint8(offset++, 0x20); // (espace)
  buffer.setUint32(offset, 16, Endian.little);
  offset += 4;
  buffer.setUint16(offset, 1, Endian.little); // PCM
  offset += 2;
  buffer.setUint16(offset, numChannels, Endian.little);
  offset += 2;
  buffer.setUint32(offset, sampleRate, Endian.little);
  offset += 4;
  buffer.setUint32(offset, byteRate, Endian.little);
  offset += 4;
  buffer.setUint16(offset, blockAlign, Endian.little);
  offset += 2;
  buffer.setUint16(offset, bitsPerSample, Endian.little);
  offset += 2;

  // data
  buffer.setUint8(offset++, 0x64); // d
  buffer.setUint8(offset++, 0x61); // a
  buffer.setUint8(offset++, 0x74); // t
  buffer.setUint8(offset++, 0x61); // a
  buffer.setUint32(offset, dataSize, Endian.little);
  offset += 4;

  for (var i = 0; i < numSamples; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    final int16 = (clamped * 32767).toInt();
    buffer.setInt16(offset, int16, Endian.little);
    offset += 2;
  }

  return buffer.buffer.asUint8List();
}
