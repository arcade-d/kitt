import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/memory/in_memory_store.dart';

void main() {
  group('InMemoryStore', () {
    test('save / get / remove', () async {
      final store = InMemoryStore();
      await store.save('prénom', 'Levi');
      expect(await store.get('prénom'), 'Levi');
      await store.remove('prénom');
      expect(await store.get('prénom'), isNull);
    });

    test('toPromptContext formate les faits, vide si aucun', () async {
      final store = InMemoryStore();
      expect(await store.toPromptContext(), isEmpty);
      await store.save('ville', 'Lyon');
      expect(await store.toPromptContext(), contains('- ville: Lyon'));
    });
  });
}
