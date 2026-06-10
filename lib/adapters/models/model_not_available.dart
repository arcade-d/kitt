/// Levée quand un fichier de modèle requis est absent du dossier résolu.
class ModelNotAvailable implements Exception {
  const ModelNotAvailable(this.message);

  final String message;

  @override
  String toString() => 'ModelNotAvailable: $message';
}
