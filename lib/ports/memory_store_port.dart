/// Mémoire persistante au-delà de la session (cf. débrief §5.4).
///
/// Tachikoma fournit `UserMemory` : un KV `Map<String,String>` en
/// SharedPreferences, injecté au prompt. KITT vise SQLite (+ dédup/TTL) ; ce
/// port abstrait permet de démarrer avec un KV puis de swapper l'implémentation.
abstract class MemoryStorePort {
  Future<void> save(String key, String value);
  Future<String?> get(String key);
  Future<void> remove(String key);
  Future<Map<String, String>> all();

  /// Snapshot formaté pour injection dans le prompt (cf. `toPromptContext`).
  Future<String> toPromptContext();
}
