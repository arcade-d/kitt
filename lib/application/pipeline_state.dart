/// États canoniques du pipeline companion (cf. débrief §5.7).
///
/// Tachikoma expose `{ idle, listening, processing, speaking }` — proche mais
/// sans `clarifying` ni transition `barge-in`. Voici la version complète.
enum PipelineState {
  idle,
  listening,
  thinking,
  responding,
  clarifying,
}

/// Déclencheurs des transitions.
enum PipelineEvent {
  wake, // wake-word OU bouton maintenir
  speechEnd, // silence / endpointing STT
  firstToken, // premier token LLM
  responseEnd, // fin de lecture TTS
  bargeIn, // l'utilisateur coupe la parole pendant la réponse
  lowConfidence, // STT trop incertain
  clarified, // la clarification est traitée
  reset, // retour forcé à idle (annulation/erreur)
}

/// Machine d'états à transitions gardées (cf. débrief §5.7).
///
/// ```
/// idle ──(wake)──► listening
/// listening ──(speechEnd)──► thinking
/// listening ──(lowConfidence)──► clarifying ──(clarified)──► listening
/// thinking ──(firstToken)──► responding
/// responding ──(responseEnd)──► idle
/// responding ──(bargeIn)──► listening
/// * ──(reset)──► idle
/// ```
class ConversationStateMachine {
  ConversationStateMachine([this._state = PipelineState.idle]);

  PipelineState _state;
  PipelineState get state => _state;

  static const Map<PipelineState, Map<PipelineEvent, PipelineState>> _table = {
    PipelineState.idle: {
      PipelineEvent.wake: PipelineState.listening,
    },
    PipelineState.listening: {
      PipelineEvent.speechEnd: PipelineState.thinking,
      PipelineEvent.lowConfidence: PipelineState.clarifying,
    },
    PipelineState.clarifying: {
      PipelineEvent.clarified: PipelineState.listening,
    },
    PipelineState.thinking: {
      PipelineEvent.firstToken: PipelineState.responding,
    },
    PipelineState.responding: {
      PipelineEvent.responseEnd: PipelineState.idle,
      PipelineEvent.bargeIn: PipelineState.listening,
    },
  };

  bool canFire(PipelineEvent event) =>
      event == PipelineEvent.reset ||
      (_table[_state]?.containsKey(event) ?? false);

  /// Applique [event]. Lève [StateError] si la transition est invalide.
  PipelineState fire(PipelineEvent event) {
    if (event == PipelineEvent.reset) {
      return _state = PipelineState.idle;
    }
    final PipelineState? next = _table[_state]?[event];
    if (next == null) {
      throw StateError('Transition invalide : ${_state.name} ──$event──► ?');
    }
    return _state = next;
  }
}
