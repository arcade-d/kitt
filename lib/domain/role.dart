/// Rôle d'un tour de conversation.
///
/// Aligné sur le modèle classique d'un échange LLM. Tachikoma modélise un tour
/// autrement (`ConversationTurn`), l'adapter LLM fera la conversion (cf. débrief §5.1).
enum Role { system, user, assistant }
