import 'dart:convert';

/// Dossiers locaux (sous `<models>/`) par modèle.
const String sttDirName = 'stt';
const String ttsDirName = 'tts';
const String llmFileName = 'croissantllmchat-v0.1.Q4_K_M.gguf';
const String llmUrl =
    'https://huggingface.co/croissantllm/CroissantLLMChat-v0.1-GGUF/resolve/main/croissantllmchat-v0.1.Q4_K_M.gguf';

const String _hfSttBase =
    'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06/resolve/main';
// Voix FR masculine (gilles, mono-speaker sid 0) — cf. décision voix KITT.
const String _ttsHfRepo = 'csukuangfj/vits-piper-fr_FR-gilles-low';
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
  const ModelStatus({
    required this.sttReady,
    required this.ttsReady,
    required this.llmReady,
  });

  final bool sttReady;
  final bool ttsReady;
  final bool llmReady;

  bool get allReady => sttReady && ttsReady && llmReady;
}

class HfEntry {
  const HfEntry({required this.type, required this.path, this.size = 0});

  final String type;
  final String path;

  /// Taille en octets (champ `size` de l'API HF), 0 pour un dossier.
  final int size;

  bool get isDirectory => type == 'directory';
}

/// Parse une réponse HuggingFace `tree/main` (JSON) en entrées typées.
List<HfEntry> parseHfTree(String jsonBody) {
  final decoded = jsonDecode(jsonBody) as List<dynamic>;
  return decoded
      .cast<Map<String, dynamic>>()
      .map(
        (e) => HfEntry(
          type: e['type'] as String,
          path: e['path'] as String,
          size: (e['size'] as num?)?.toInt() ?? 0,
        ),
      )
      .toList();
}

/// Avancement d'un téléchargement, en octets. Permet d'afficher « reçu / total »
/// et d'agréger plusieurs fichiers/modules.
class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});

  /// Octets déjà écrits sur le disque.
  final int received;

  /// Total attendu en octets ; `0` si encore inconnu.
  final int total;

  /// Fraction 0–1 ; 0 si le total est inconnu.
  double get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;

  /// Téléchargement complet (total connu et atteint).
  bool get isComplete => total > 0 && received >= total;
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
      url: '$_ttsHfBase/fr_FR-gilles-low.onnx',
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
