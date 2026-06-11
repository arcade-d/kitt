import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'model_catalog.dart';

/// Fournit le dossier de base où stocker les modèles. Par défaut, le dossier
/// documents de l'app ; injectable pour les tests.
typedef BaseDirProvider = Future<String> Function();

/// Plage d'octets inclusive `[start, end]` (sémantique d'un en-tête HTTP
/// `Range: bytes=start-end`).
class ByteRange {
  const ByteRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start + 1;
}

/// Découpe [total] octets en au plus [parts] plages contiguës (téléchargement
/// par chunks parallèles). Les plages couvrent exactement `[0, total-1]`, le
/// dernier chunk absorbant le reste de la division.
List<ByteRange> planChunks(int total, int parts) {
  if (total <= 0 || parts <= 0) {
    return const <ByteRange>[];
  }
  final int chunk = (total / parts).ceil();
  final ranges = <ByteRange>[];
  var start = 0;
  while (start < total) {
    var end = start + chunk - 1;
    if (end >= total) {
      end = total - 1;
    }
    ranges.add(ByteRange(start, end));
    start = end + 1;
  }
  return ranges;
}

/// Métadonnées sondées d'un fichier distant.
class _RemoteInfo {
  const _RemoteInfo({required this.total, required this.acceptsRange});

  final int? total;
  final bool acceptsRange;
}

/// Plan de téléchargement d'un modèle : taille totale + taille par fichier.
class _ModelPlan {
  const _ModelPlan({required this.total, required this.sizes});

  final int total;
  final Map<String, int> sizes;
}

/// Gère le catalogue, les chemins locaux et le téléchargement des modèles.
///
/// Tous les fichiers (STT, TTS, LLM) sont récupérés **par chunks parallèles**
/// avec reprise quand le serveur supporte les requêtes `Range` ; repli
/// mono-flux sinon. La progression est rapportée en **octets** (reçus / total)
/// via [DownloadProgress], ce qui permet à l'UI d'afficher « 123,4 / 872,0 Mo ».
class ModelManager {
  ModelManager({
    BaseDirProvider? baseDirProvider,
    http.Client? client,
    int parallelChunks = 4,
    int minChunkBytes = 8 * 1024 * 1024,
  })  : _baseDirProvider = baseDirProvider ?? _defaultBaseDir,
        _client = client ?? http.Client(),
        _parallelChunks = parallelChunks,
        _minChunkBytes = minChunkBytes;

  final BaseDirProvider _baseDirProvider;
  final http.Client _client;
  final int _parallelChunks;
  final int _minChunkBytes;

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
  String get llmModelPath => '$_modelsDir/$llmFileName';

  bool get isSttModelAvailable =>
      File('$sttModelDir/encoder.onnx').existsSync() &&
      File('$sttModelDir/tokens.txt').existsSync();

  bool get isTtsModelAvailable =>
      File('$ttsModelDir/model.onnx').existsSync() &&
      File('$ttsModelDir/tokens.txt').existsSync() &&
      File('$ttsModelDir/espeak-ng-data/fr_dict').existsSync() &&
      File('$ttsModelDir/espeak-ng-data/phontab').existsSync();

  bool get isLlmModelAvailable => File(llmModelPath).existsSync();

  ModelStatus getStatus() => ModelStatus(
        sttReady: isSttModelAvailable,
        ttsReady: isTtsModelAvailable,
        llmReady: isLlmModelAvailable,
      );

  /// Supprime les `.tmp` (concaténation interrompue) laissés par un
  /// téléchargement avorté. Les fragments `.partN` sont **conservés** : ils
  /// permettent de reprendre un chunk là où il s'était arrêté au prochain
  /// lancement.
  Future<void> _cleanPartialDownloads() async {
    final dir = Directory(_modelsDir);
    if (!dir.existsSync()) return;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.tmp')) {
        await entity.delete();
      }
    }
  }

  /// Télécharge les fichiers d'un [model]. Progression en octets via
  /// [onProgress] (agrégée sur tous les fichiers, dossier HF récursif inclus).
  /// Saute les fichiers déjà présents et non vides.
  Future<void> downloadModel(
    ModelInfo model, {
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    final plan = await _planModel(model);
    final total = plan.total;
    var received = 0;

    for (final file in model.files) {
      final targetPath = '$_modelsDir/${file.localPath}';
      final targetFile = File(targetPath);
      final size = plan.sizes[file.localPath] ?? 0;

      if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
        received += size;
        onProgress(DownloadProgress(received: received, total: total));
        continue;
      }

      await targetFile.parent.create(recursive: true);
      final start = received;
      await _downloadToFile(
        file.url,
        targetPath,
        onBytes: (got, _) => onProgress(
          DownloadProgress(received: start + got, total: total),
        ),
      );
      received += size;
      onProgress(DownloadProgress(received: received, total: total));
    }

    if (model.hfRepoForRecursiveDownload != null && model.hfSubdir != null) {
      received = await _downloadHfDirectory(
        model.hfRepoForRecursiveDownload!,
        model.hfSubdir!,
        '$_modelsDir/${model.name}',
        total: total,
        baseReceived: received,
        onProgress: onProgress,
      );
    }

    onProgress(DownloadProgress(received: total, total: total));
  }

  /// Télécharge le GGUF LLM (gros fichier) par chunks parallèles avec reprise.
  Future<void> downloadLlmModel({
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    final targetPath = llmModelPath;
    final targetFile = File(targetPath);
    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      final size = targetFile.lengthSync();
      onProgress(DownloadProgress(received: size, total: size));
      return;
    }

    await _downloadToFile(
      llmUrl,
      targetPath,
      onBytes: (received, total) =>
          onProgress(DownloadProgress(received: received, total: total)),
    );
  }

  // ── Planification des tailles ──────────────────────────────────────────────

  Future<_ModelPlan> _planModel(ModelInfo model) async {
    final sizes = <String, int>{};
    var total = 0;

    for (final file in model.files) {
      final targetFile = File('$_modelsDir/${file.localPath}');
      final int size;
      if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
        size = targetFile.lengthSync();
      } else {
        size = (await _probeRemote(file.url)).total ?? 0;
      }
      sizes[file.localPath] = size;
      total += size;
    }

    if (model.hfRepoForRecursiveDownload != null && model.hfSubdir != null) {
      total += await _hfDirectorySize(
        model.hfRepoForRecursiveDownload!,
        model.hfSubdir!,
      );
    }

    return _ModelPlan(total: total, sizes: sizes);
  }

  Future<int> _hfDirectorySize(String repo, String path) async {
    final apiUrl = 'https://huggingface.co/api/models/$repo/tree/main/$path';
    final response = await _httpGetWithRetry(apiUrl);
    if (response.statusCode != 200) return 0;
    var total = 0;
    for (final entry in parseHfTree(response.body)) {
      if (entry.isDirectory) {
        total += await _hfDirectorySize(repo, entry.path);
      } else {
        total += entry.size;
      }
    }
    return total;
  }

  // ── Téléchargement d'un fichier (chunks parallèles ou mono-flux) ────────────

  Future<void> _downloadToFile(
    String url,
    String targetPath, {
    required void Function(int received, int total) onBytes,
  }) async {
    final info = await _probeRemote(url);
    final total = info.total;
    if (!info.acceptsRange || total == null || total < _minChunkBytes) {
      await _downloadSingle(url, targetPath, total, onBytes);
      return;
    }
    await _downloadChunked(url, targetPath, total, onBytes);
  }

  Future<_RemoteInfo> _probeRemote(String url) async {
    try {
      final probe = http.Request('GET', Uri.parse(url));
      probe.headers['Range'] = 'bytes=0-0';
      final response = await _client.send(probe);
      await response.stream.drain<void>();
      if (response.statusCode == 206) {
        final contentRange = response.headers['content-range'] ?? '';
        final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
        final total = match != null ? int.tryParse(match.group(1)!) : null;
        return _RemoteInfo(total: total, acceptsRange: true);
      }
      final len = response.contentLength;
      return _RemoteInfo(total: len, acceptsRange: false);
    } catch (_) {
      return const _RemoteInfo(total: null, acceptsRange: false);
    }
  }

  Future<void> _downloadSingle(
    String url,
    String targetPath,
    int? knownTotal,
    void Function(int received, int total) onBytes,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final request = http.Request('GET', Uri.parse(url));
        final response = await _client.send(request);
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception(
            'Téléchargement échoué: HTTP ${response.statusCode} ($url)',
          );
        }
        final total = knownTotal ?? response.contentLength ?? -1;
        final tmpFile = File('$targetPath.tmp');
        final sink = tmpFile.openWrite();
        var received = 0;
        try {
          await for (final data in response.stream) {
            sink.add(data);
            received += data.length;
            onBytes(received, total);
          }
        } finally {
          await sink.close();
        }
        await tmpFile.rename(targetPath);
        onBytes(received, received);
        return;
      } catch (e) {
        if (attempt == 2) rethrow;
      }
    }
  }

  Future<void> _downloadChunked(
    String url,
    String targetPath,
    int total,
    void Function(int received, int total) onBytes,
  ) async {
    final ranges = planChunks(total, _parallelChunks);
    final parts = <File>[];
    final received = List<int>.filled(ranges.length, 0);

    void report() {
      final sum = received.fold<int>(0, (a, b) => a + b);
      onBytes(sum, total);
    }

    final futures = <Future<void>>[];
    for (var i = 0; i < ranges.length; i++) {
      final index = i;
      final part = File('$targetPath.part$i');
      parts.add(part);
      await part.parent.create(recursive: true);
      futures.add(
        _downloadRange(url, part, ranges[i], (got) {
          received[index] = got;
          report();
        }),
      );
    }
    await Future.wait(futures);

    final tmpFile = File('$targetPath.tmp');
    final sink = tmpFile.openWrite();
    for (final part in parts) {
      await sink.addStream(part.openRead());
    }
    await sink.close();

    final actual = tmpFile.lengthSync();
    if (actual != total) {
      await tmpFile.delete();
      for (final part in parts) {
        if (part.existsSync()) await part.delete();
      }
      throw Exception('Taille téléchargée incohérente: $actual != $total');
    }

    for (final part in parts) {
      if (part.existsSync()) await part.delete();
    }
    await tmpFile.rename(targetPath);
    onBytes(total, total);
  }

  Future<void> _downloadRange(
    String url,
    File part,
    ByteRange range,
    void Function(int received) onBytes,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final existing = part.existsSync() ? part.lengthSync() : 0;
        if (existing >= range.length) {
          onBytes(range.length);
          return;
        }
        final request = http.Request('GET', Uri.parse(url));
        request.headers['Range'] =
            'bytes=${range.start + existing}-${range.end}';
        final response = await _client.send(request);
        if (response.statusCode != 206 && response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        final sink = part.openWrite(mode: FileMode.append);
        var got = existing;
        try {
          await for (final data in response.stream) {
            sink.add(data);
            got += data.length;
            onBytes(got);
          }
        } finally {
          await sink.close();
        }
        return;
      } catch (e) {
        if (attempt == 2) rethrow;
      }
    }
  }

  // ── Dossier HuggingFace récursif (ex. espeak-ng-data) ──────────────────────

  Future<int> _downloadHfDirectory(
    String repo,
    String path,
    String localBase, {
    required int total,
    required int baseReceived,
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    final apiUrl = 'https://huggingface.co/api/models/$repo/tree/main/$path';
    final response = await _httpGetWithRetry(apiUrl);
    if (response.statusCode != 200) {
      throw Exception(
        'Échec listage dossier HF: $path (${response.statusCode})',
      );
    }

    var received = baseReceived;
    for (final entry in parseHfTree(response.body)) {
      final localPath = '$localBase/${entry.path}';
      if (entry.isDirectory) {
        await Directory(localPath).create(recursive: true);
        received = await _downloadHfDirectory(
          repo,
          entry.path,
          localBase,
          total: total,
          baseReceived: received,
          onProgress: onProgress,
        );
        continue;
      }

      final file = File(localPath);
      if (file.existsSync() && file.lengthSync() > 0) {
        received += entry.size;
        onProgress(DownloadProgress(received: received, total: total));
        continue;
      }

      await file.parent.create(recursive: true);
      final start = received;
      await _downloadToFile(
        'https://huggingface.co/$repo/resolve/main/${entry.path}',
        localPath,
        onBytes: (got, _) => onProgress(
          DownloadProgress(received: start + got, total: total),
        ),
      );
      received += entry.size;
      onProgress(DownloadProgress(received: received, total: total));
    }
    return received;
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

  void dispose() => _client.close();
}
