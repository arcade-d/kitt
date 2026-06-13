import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'model_manager.dart';

/// Charge les octets d'un asset (injectable pour les tests).
typedef AssetBytesLoader = Future<Uint8List> Function(String assetKey);

/// Extrait les modèles voix (STT + TTS) embarqués dans l'APK
/// (`assets/models/voice.tar`) vers le dossier `models/` du `ModelManager`,
/// aux mêmes chemins que ceux attendus par `SherpaStt`/`SherpaTts`.
///
/// L'archive est un tar **non compressé** (l'APK zippe déjà les assets) :
/// le décodage se résume à du parsing d'en-têtes + découpage d'octets.
class AssetVoiceInstaller {
  AssetVoiceInstaller({required this.manager, AssetBytesLoader? loader})
      : _load = loader ?? _defaultLoad;

  final ModelManager manager;
  final AssetBytesLoader _load;

  static const String assetKey = 'assets/models/voice.tar';

  static Future<Uint8List> _defaultLoad(String key) async =>
      (await rootBundle.load(key)).buffer.asUint8List();

  /// Vrai si STT et TTS sont déjà présents sur disque (sentinelles du manager).
  bool get isInstalled =>
      manager.isSttModelAvailable && manager.isTtsModelAvailable;

  /// Extrait l'archive si nécessaire. No-op si déjà installé. Lève si
  /// l'extraction ne produit pas les fichiers attendus.
  Future<void> ensureInstalled() async {
    if (isInstalled) return;

    final Uint8List bytes = await _load(assetKey);
    final Archive archive = TarDecoder().decodeBytes(bytes);

    for (final ArchiveFile file in archive.files) {
      if (!file.isFile) continue;
      final Uint8List? data = file.readBytes();
      if (data == null) continue;
      final out = File('${manager.modelsDir}/${file.name}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(data);
    }

    if (!isInstalled) {
      throw StateError(
        'Extraction des voix incomplète depuis $assetKey '
        '(STT=${manager.isSttModelAvailable}, TTS=${manager.isTtsModelAvailable})',
      );
    }
  }
}
