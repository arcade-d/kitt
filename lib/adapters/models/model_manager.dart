import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'model_catalog.dart';

/// Fournit le dossier de base où stocker les modèles. Par défaut, le dossier
/// documents de l'app ; injectable pour les tests.
typedef BaseDirProvider = Future<String> Function();

/// Gère le catalogue, les chemins locaux et le téléchargement (avec reprise)
/// des modèles. Porté de Tachikoma `model_manager.dart`, épuré et rendu
/// injectable (baseDir + http.Client) pour la testabilité.
class ModelManager {
  ModelManager({BaseDirProvider? baseDirProvider, http.Client? client})
      : _baseDirProvider = baseDirProvider ?? _defaultBaseDir,
        _client = client ?? http.Client();

  final BaseDirProvider _baseDirProvider;
  final http.Client _client;

  static Future<String> _defaultBaseDir() async =>
      (await getApplicationDocumentsDirectory()).path;

  late final String _modelsDir;

  Future<void> initialize() async {
    final base = await _baseDirProvider();
    _modelsDir = '$base/models';
    await Directory(_modelsDir).create(recursive: true);
    await _cleanPartialDownloads();
  }

  String get modelsDir => _modelsDir;
  String get sttModelDir => '$_modelsDir/$sttDirName';
  String get ttsModelDir => '$_modelsDir/$ttsDirName';

  bool get isSttModelAvailable =>
      File('$sttModelDir/encoder.onnx').existsSync() &&
      File('$sttModelDir/tokens.txt').existsSync();

  bool get isTtsModelAvailable =>
      File('$ttsModelDir/model.onnx').existsSync() &&
      File('$ttsModelDir/tokens.txt').existsSync() &&
      File('$ttsModelDir/espeak-ng-data/fr_dict').existsSync() &&
      File('$ttsModelDir/espeak-ng-data/phontab').existsSync();

  ModelStatus getStatus() => ModelStatus(
        sttReady: isSttModelAvailable,
        ttsReady: isTtsModelAvailable,
      );

  /// Supprime les `.tmp` laissés par un téléchargement interrompu.
  Future<void> _cleanPartialDownloads() async {
    final dir = Directory(_modelsDir);
    if (!dir.existsSync()) return;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.tmp')) {
        await entity.delete();
      }
    }
  }

  /// Télécharge les fichiers d'un modèle. Progression 0.0–1.0 via [onProgress].
  /// Saute les fichiers déjà présents et non vides.
  Future<void> downloadModel(
    ModelInfo model, {
    required void Function(double progress) onProgress,
  }) async {
    final totalSteps = model.files.length;
    var completed = 0;

    for (final file in model.files) {
      final targetPath = '$_modelsDir/${file.localPath}';
      final targetFile = File(targetPath);
      if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
        completed++;
        onProgress(completed / (totalSteps + 1));
        continue;
      }
      await targetFile.parent.create(recursive: true);
      await _downloadFileWithRetry(file.url, targetPath);
      completed++;
      onProgress(completed / (totalSteps + 1));
    }

    if (model.hfRepoForRecursiveDownload != null && model.hfSubdir != null) {
      await _downloadHfDirectory(
        model.hfRepoForRecursiveDownload!,
        model.hfSubdir!,
        '$_modelsDir/${model.name}',
      );
    }

    onProgress(1.0);
  }

  Future<void> _downloadHfDirectory(
    String repo,
    String path,
    String localBase,
  ) async {
    final apiUrl = 'https://huggingface.co/api/models/$repo/tree/main/$path';
    final response = await _httpGetWithRetry(apiUrl);
    if (response.statusCode != 200) {
      throw Exception(
        'Échec listage dossier HF: $path (${response.statusCode})',
      );
    }
    for (final entry in parseHfTree(response.body)) {
      final localPath = '$localBase/${entry.path}';
      if (entry.isDirectory) {
        await Directory(localPath).create(recursive: true);
        await _downloadHfDirectory(repo, entry.path, localBase);
      } else {
        final file = File(localPath);
        if (file.existsSync() && file.lengthSync() > 0) continue;
        await file.parent.create(recursive: true);
        await _downloadFileWithRetry(
          'https://huggingface.co/$repo/resolve/main/${entry.path}',
          localPath,
        );
      }
    }
  }

  Future<http.Response> _httpGetWithRetry(
    String url, {
    int maxRetries = 3,
  }) async {
    for (var i = 0; i < maxRetries; i++) {
      try {
        return await _client.get(Uri.parse(url));
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
      }
    }
    throw Exception('Inatteignable');
  }

  Future<void> _downloadFileWithRetry(
    String url,
    String targetPath, {
    int maxRetries = 3,
  }) async {
    for (var i = 0; i < maxRetries; i++) {
      try {
        await _downloadFile(url, targetPath);
        return;
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
      }
    }
  }

  Future<void> _downloadFile(String url, String targetPath) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw Exception(
        'Téléchargement échoué: HTTP ${response.statusCode} ($url)',
      );
    }
    final tmpPath = '$targetPath.tmp';
    final tmpFile = File(tmpPath);
    final sink = tmpFile.openWrite();
    await response.stream.pipe(sink);
    await sink.close();
    await tmpFile.rename(targetPath);
  }

  void dispose() => _client.close();
}
