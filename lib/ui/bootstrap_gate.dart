import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import 'companion_screen.dart';
import 'model_download_screen.dart';

/// Portail de démarrage : attend que les modèles soient prêts avant d'afficher
/// l'écran companion. En mode mock, laisse passer directement.
class BootstrapGate extends ConsumerWidget {
  const BootstrapGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsReady = ref.watch(modelsReadyProvider);

    return modelsReady.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFFFB000),
          ),
        ),
      ),
      error: (error, _) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFFF1A1A),
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Erreur d\'initialisation',
                  style: TextStyle(
                    color: Color(0xFFFFB000),
                    fontSize: 18,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A0000),
                    foregroundColor: const Color(0xFFFF1A1A),
                    side: const BorderSide(color: Color(0xFFFF1A1A)),
                  ),
                  onPressed: () => ref.invalidate(modelsReadyProvider),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (final bool ready) =>
          ready ? const CompanionScreen() : const ModelDownloadScreen(),
    );
  }
}
