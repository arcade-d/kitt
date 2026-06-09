/// Le cerveau + la persona (cf. débrief §4.3).
///
/// API alignée sur `DualLlmService` de Tachikoma (`llamadart`). On expose le
/// minimum conversationnel ; le routage TOOL/CHAT et la mémoire restent côté
/// adapter/orchestration.
abstract class LlmPort {
  /// Le system prompt (persona) injecté de façon stable.
  set systemPrompt(String prompt);

  /// Réponse complète (bloquant jusqu'à la fin de génération).
  Future<String> generateChat(String prompt, {String? toolContext});

  /// Réponse en streaming, token par token (premier levier de latence perçue).
  Stream<String> generateChatStream(String prompt, {String? toolContext});
}
