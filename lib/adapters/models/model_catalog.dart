import 'dart:convert';

/// Dossiers locaux (sous `<models>/`) par modèle.
const String sttDirName = 'stt';
const String ttsDirName = 'tts';

const String _hfSttBase =
    'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06/resolve/main';
const String _ttsHfRepo = 'csukuangfj/vits-piper-fr_FR-siwis-medium';
const String _ttsHfBase = 'https://huggingface.co/$_ttsHfRepo/resolve/main';

class ModelFile {
  const ModelFile({required this.url, required this.localPath});

  final String url;
  final String localPath;
}

class ModelInfo {
  const ModelInfo({
    required this.name,
    required this.label,
    required this.files,
    this.hfRepoForRecursiveDownload,
    this.hfSubdir,
  });

  final String name;
  final String label;
  final List<ModelFile> files;

  /// Si défini, télécharger récursivement ce sous-dossier du repo HF.
  final String? hfRepoForRecursiveDownload;
  final String? hfSubdir;
}

class ModelStatus {
  const ModelStatus({required this.sttReady, required this.ttsReady});

  final bool sttReady;
  final bool ttsReady;

  bool get allReady => sttReady && ttsReady;
}

class HfEntry {
  const HfEntry({required this.type, required this.path});

  final String type;
  final String path;

  bool get isDirectory => type == 'directory';
}

/// Parse une réponse HuggingFace `tree/main` (JSON) en entrées typées.
List<HfEntry> parseHfTree(String jsonBody) {
  final decoded = jsonDecode(jsonBody) as List<dynamic>;
  return decoded
      .cast<Map<String, dynamic>>()
      .map(
        (e) => HfEntry(type: e['type'] as String, path: e['path'] as String),
      )
      .toList();
}

const ModelInfo sttModel = ModelInfo(
  name: sttDirName,
  label: 'Speech-to-Text',
  files: [
    ModelFile(
      url: '$_hfSttBase/encoder.onnx',
      localPath: '$sttDirName/encoder.onnx',
    ),
    ModelFile(
      url: '$_hfSttBase/decoder.onnx',
      localPath: '$sttDirName/decoder.onnx',
    ),
    ModelFile(
      url: '$_hfSttBase/joiner.onnx',
      localPath: '$sttDirName/joiner.onnx',
    ),
    ModelFile(
      url: '$_hfSttBase/tokens.txt',
      localPath: '$sttDirName/tokens.txt',
    ),
  ],
);

const ModelInfo ttsModel = ModelInfo(
  name: ttsDirName,
  label: 'Text-to-Speech',
  files: [
    ModelFile(
      url: '$_ttsHfBase/fr_FR-siwis-medium.onnx',
      localPath: '$ttsDirName/model.onnx',
    ),
    ModelFile(
      url: '$_ttsHfBase/tokens.txt',
      localPath: '$ttsDirName/tokens.txt',
    ),
  ],
  hfRepoForRecursiveDownload: _ttsHfRepo,
  hfSubdir: 'espeak-ng-data',
);
