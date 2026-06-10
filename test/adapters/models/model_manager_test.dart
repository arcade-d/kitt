import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kitt/adapters/models/model_catalog.dart';
import 'package:kitt/adapters/models/model_manager.dart';

void main() {
  group('catalogue', () {
    test('sttModel : 4 fichiers, URLs HF zipformer FR', () {
      expect(sttModel.files.length, 4);
      expect(
        sttModel.files.first.url,
        contains('sherpa-onnx-streaming-zipformer-fr-kroko'),
      );
      expect(sttModel.files.first.localPath, '$sttDirName/encoder.onnx');
    });

    test('ttsModel : dossier HF récursif espeak-ng-data', () {
      expect(ttsModel.hfSubdir, 'espeak-ng-data');
      expect(
        ttsModel.files.any((f) => f.localPath == '$ttsDirName/model.onnx'),
        isTrue,
      );
    });

    test('parseHfTree : JSON tree -> entrées typées', () {
      const json =
          '[{"type":"file","path":"fr_dict"},{"type":"directory","path":"sub"}]';
      final entries = parseHfTree(json);
      expect(entries.length, 2);
      expect(entries[0].isDirectory, isFalse);
      expect(entries[0].path, 'fr_dict');
      expect(entries[1].isDirectory, isTrue);
    });

    test('ModelStatus.allReady', () {
      expect(
        const ModelStatus(sttReady: true, ttsReady: true).allReady,
        isTrue,
      );
      expect(
        const ModelStatus(sttReady: true, ttsReady: false).allReady,
        isFalse,
      );
    });
  });

  group('ModelManager', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('kitt_mm_');
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    ModelManager make({http.Client? client}) => ModelManager(
          baseDirProvider: () async => tmp.path,
          client: client ?? MockClient((_) async => http.Response('', 404)),
        );

    test('chemins dérivés du baseDir', () async {
      final mm = make();
      await mm.initialize();
      expect(mm.modelsDir, '${tmp.path}/models');
      expect(mm.sttModelDir, '${tmp.path}/models/stt');
      expect(mm.ttsModelDir, '${tmp.path}/models/tts');
    });

    test('isSttModelAvailable selon présence encoder + tokens', () async {
      final mm = make();
      await mm.initialize();
      expect(mm.isSttModelAvailable, isFalse);
      Directory(mm.sttModelDir).createSync(recursive: true);
      File('${mm.sttModelDir}/encoder.onnx').writeAsStringSync('x');
      File('${mm.sttModelDir}/tokens.txt').writeAsStringSync('x');
      expect(mm.isSttModelAvailable, isTrue);
    });

    test('downloadModel saute les fichiers déjà présents (aucun réseau)',
        () async {
      final mm = make(
        client: MockClient(
          (_) async => throw StateError('ne doit pas télécharger'),
        ),
      );
      await mm.initialize();
      Directory(mm.sttModelDir).createSync(recursive: true);
      for (final f in const [
        'encoder.onnx',
        'decoder.onnx',
        'joiner.onnx',
        'tokens.txt',
      ]) {
        File('${mm.sttModelDir}/$f').writeAsStringSync('present');
      }
      final progress = <double>[];
      await mm.downloadModel(sttModel, onProgress: progress.add);
      expect(progress.last, 1.0);
    });

    test('downloadModel écrit un fichier manquant depuis le réseau', () async {
      final mm = make(
        client: MockClient((_) async => http.Response('DATA', 200)),
      );
      await mm.initialize();
      const oneFile = ModelInfo(
        name: 'stt',
        label: 'x',
        files: [
          ModelFile(
            url: 'https://example.test/encoder.onnx',
            localPath: 'stt/encoder.onnx',
          ),
        ],
      );
      await mm.downloadModel(oneFile, onProgress: (_) {});
      expect(File('${mm.sttModelDir}/encoder.onnx').readAsStringSync(), 'DATA');
    });
  });
}
