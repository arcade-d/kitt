import '../../ports/memory_store_port.dart';

/// Implémentation KV en mémoire du [MemoryStorePort].
///
/// Premier jalon (cf. débrief §5.4) : équivalent de `UserMemory` (KV simple),
/// à remplacer par SQLite + dédup/TTL plus tard. Volatile : ne survit pas au
/// redémarrage (un adapter SharedPreferences/SQLite viendra ensuite).
class InMemoryStore implements MemoryStorePort {
  final Map<String, String> _facts = <String, String>{};

  @override
  Future<void> save(String key, String value) async => _facts[key] = value;

  @override
  Future<String?> get(String key) async => _facts[key];

  @override
  Future<void> remove(String key) async => _facts.remove(key);

  @override
  Future<Map<String, String>> all() async => Map<String, String>.of(_facts);

  @override
  Future<String> toPromptContext() async {
    if (_facts.isEmpty) return '';
    return _facts.entries.map((e) => '- ${e.key}: ${e.value}').join('\n');
  }
}
