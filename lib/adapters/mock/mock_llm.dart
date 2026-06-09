import 'dart:async';

import '../../ports/llm_port.dart';

/// LLM factice : « streame » une réponse déterministe mot à mot. Permet de
/// tester `thinking → responding` (premier token) et le streaming UI.
class MockLlm implements LlmPort {
  MockLlm({this.reply = 'Tout est sous contrôle. Je vous écoute.'});

  String reply;
  String _systemPrompt = '';

  @override
  set systemPrompt(String prompt) => _systemPrompt = prompt;

  String get systemPrompt => _systemPrompt;

  @override
  Future<String> generateChat(String prompt, {String? toolContext}) async =>
      reply;

  @override
  Stream<String> generateChatStream(
    String prompt, {
    String? toolContext,
  }) async* {
    for (final String word in reply.split(' ')) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      yield '$word ';
    }
  }
}
