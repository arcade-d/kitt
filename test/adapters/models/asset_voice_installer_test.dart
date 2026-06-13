import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/models/asset_voice_installer.dart';
import 'package:kitt/adapters/models/model_manager.dart';

void main() {
  group('AssetVoiceInstaller', () {
    late Directory tmp;
    late Uint8List voiceTar;

    // Fichiers sentinelles attendus par ModelManager (STT + TTS).
    const entries = <String>[
      'stt/encoder.onnx',
      'stt/decoder.onnx',
      'stt/joiner.onnx',
      'stt/tokens.txt',
      'tts/model.onnx',
      'tts/tokens.txt',
      'tts/espeak-ng-data/fr_dict',
      'tts/espeak-ng-data/phontab',
    ];

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('kitt_avi_');
      // Construit une archive tar de test avec le `tar` système (indépendant
      // de l'API d'encodage du package archive).
      final stage = Directory('${tmp.path}/stage');
      for (final e in entries) {
        final f = File('${stage.path}/$e')..createSync(recursive: true);
        f.writeAsStringSync('data:$e');
      }
      final res = await Process.run(
        'tar',
        <String>[
          '-cf',
          '${tmp.path}/voice.tar',
          '-C',
          stage.path,
          'stt',
          'tts'
        ],
      );
      expect(res.exitCode, 0, reason: res.stderr.toString());
      voiceTar = File('${tmp.path}/voice.tar').readAsBytesSync();
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    Future<ModelManager> makeManager() async {
      final mm = ModelManager(baseDirProvider: () async => '${tmp.path}/app');
      await mm.initialize();
      return mm;
    }

    test('extrait STT+TTS aux chemins du ModelManager', () async {
      final mm = await makeManager();
      final installer = AssetVoiceInstaller(
        manager: mm,
        loader: (_) async => voiceTar,
      );
      expect(installer.isInstalled, isFalse);

      await installer.ensureInstalled();

      expect(installer.isInstalled, isTrue);
      expect(mm.isSttModelAvailable, isTrue);
      expect(mm.isTtsModelAvailable, isTrue);
      expect(
        File('${mm.ttsModelDir}/espeak-ng-data/fr_dict').existsSync(),
        isTrue,
      );
    });

    test('idempotent : ne recharge pas si déjà installé', () async {
      final mm = await makeManager();
      var calls = 0;
      final installer = AssetVoiceInstaller(
        manager: mm,
        loader: (_) async {
          calls++;
          return voiceTar;
        },
      );
      await installer.ensureInstalled();
      await installer.ensureInstalled();
      expect(calls, 1);
    });

    test('archive corrompue : lève une erreur', () async {
      final mm = await makeManager();
      final installer = AssetVoiceInstaller(
        manager: mm,
        loader: (_) async => Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      await expectLater(installer.ensureInstalled(), throwsA(anything));
    });
  });
}
