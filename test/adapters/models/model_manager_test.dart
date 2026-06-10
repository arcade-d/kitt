import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/models/model_catalog.dart';

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
      expect(ttsModel.files.any((f) => f.localPath == '$ttsDirName/model.onnx'),
          isTrue,);
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
      expect(const ModelStatus(sttReady: true, ttsReady: true).allReady, isTrue);
      expect(
        const ModelStatus(sttReady: true, ttsReady: false).allReady,
        isFalse,
      );
    });
  });
}
