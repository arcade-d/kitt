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

    test('parseHfTree : JSON tree -> entrées typées avec taille', () {
      const json = '[{"type":"file","path":"fr_dict","size":1024},'
          '{"type":"directory","path":"sub"}]';
      final entries = parseHfTree(json);
      expect(entries.length, 2);
      expect(entries[0].isDirectory, isFalse);
      expect(entries[0].path, 'fr_dict');
      expect(entries[0].size, 1024);
      expect(entries[1].isDirectory, isTrue);
      expect(entries[1].size, 0);
    });

    test('ModelStatus.allReady', () {
      expect(
        const ModelStatus(
          sttReady: true,
          ttsReady: true,
          llmReady: true,
        ).allReady,
        isTrue,
      );
      expect(
        const ModelStatus(
          sttReady: true,
          ttsReady: true,
          llmReady: false,
        ).allReady,
        isFalse,
      );
    });

    test('DownloadProgress : fraction et complétion', () {
      const p = DownloadProgress(received: 50, total: 200);
      expect(p.fraction, 0.25);
      expect(p.isComplete, isFalse);
      const q = DownloadProgress(received: 200, total: 200);
      expect(q.isComplete, isTrue);
      const z = DownloadProgress(received: 10, total: 0);
      expect(z.fraction, 0.0);
    });
  });

  group('planChunks', () {
    test('couvre exactement [0, total-1] sans trou ni chevauchement', () {
      const total = 1000;
      final ranges = planChunks(total, 4);
      expect(ranges.first.start, 0);
      expect(ranges.last.end, total - 1);
      var expectedStart = 0;
      var covered = 0;
      for (final r in ranges) {
        expect(r.start, expectedStart);
        expect(r.end >= r.start, isTrue);
        covered += r.length;
        expectedStart = r.end + 1;
      }
      expect(covered, total);
    });

    test('ne dépasse pas le nombre de chunks demandé', () {
      expect(planChunks(1000, 4).length, lessThanOrEqualTo(4));
      expect(planChunks(3, 4).length, lessThanOrEqualTo(4));
    });

    test('taille nulle → aucune plage', () {
      expect(planChunks(0, 4), isEmpty);
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

    ModelManager make({http.Client? client, int? minChunkBytes}) =>
        ModelManager(
          baseDirProvider: () async => tmp.path,
          client: client ?? MockClient((_) async => http.Response('', 404)),
          minChunkBytes: minChunkBytes ?? 8 * 1024 * 1024,
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
      final progress = <DownloadProgress>[];
      await mm.downloadModel(sttModel, onProgress: progress.add);
      expect(progress.last.isComplete, isTrue);
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

    test('llmModelPath + isLlmModelAvailable + getStatus.llmReady', () async {
      final mm = make();
      await mm.initialize();
      expect(mm.llmModelPath, '${tmp.path}/models/$llmFileName');
      expect(mm.isLlmModelAvailable, isFalse);
      expect(mm.getStatus().llmReady, isFalse);
      File(mm.llmModelPath).writeAsStringSync('gguf');
      expect(mm.isLlmModelAvailable, isTrue);
      expect(mm.getStatus().llmReady, isTrue);
    });

    test('downloadLlmModel : saute si déjà présent (aucun réseau)', () async {
      final mm = make(
        client: MockClient(
          (_) async => throw StateError('ne doit pas télécharger'),
        ),
      );
      await mm.initialize();
      File(mm.llmModelPath).writeAsStringSync('present');
      final progress = <DownloadProgress>[];
      await mm.downloadLlmModel(onProgress: progress.add);
      expect(progress.last.isComplete, isTrue);
    });

    test('downloadLlmModel : fallback mono-flux écrit le GGUF', () async {
      // Le serveur répond 200 (pas 206) au probe Range → pas de chunks → mono-flux.
      final mm = make(
        client: MockClient((_) async => http.Response('GGUF', 200)),
      );
      await mm.initialize();
      await mm.downloadLlmModel(onProgress: (_) {});
      expect(File(mm.llmModelPath).readAsStringSync(), 'GGUF');
    });

    test('downloadLlmModel : chunks parallèles assemblent le fichier complet',
        () async {
      // Buffer déterministe servi par plages (206 + content-range).
      final data = List<int>.generate(40, (i) => i % 251);
      final mm = make(
        minChunkBytes: 4, // force le découpage en chunks
        client: MockClient((request) async {
          final raw = request.headers['range'] ?? request.headers['Range']!;
          final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(raw)!;
          final a = int.parse(m.group(1)!);
          final b = int.parse(m.group(2)!);
          final slice = data.sublist(a, b + 1);
          return http.Response.bytes(
            slice,
            206,
            headers: <String, String>{
              'content-range': 'bytes $a-$b/${data.length}',
            },
          );
        }),
      );
      await mm.initialize();

      final progress = <DownloadProgress>[];
      await mm.downloadLlmModel(onProgress: progress.add);

      final written = File(mm.llmModelPath).readAsBytesSync();
      expect(written.length, data.length);
      expect(written, data);
      expect(progress.last.isComplete, isTrue);
    });
  });
}
