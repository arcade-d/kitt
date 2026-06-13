import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import 'boot_gate_logic.dart';
import 'boot_screen.dart';
import 'companion_screen.dart';
import 'model_download_screen.dart';
import 'theme/kitt_theme.dart';

/// Portail de démarrage : joue le boot K2000 (≥2,5 s, couvre l'init) puis
/// aiguille vers l'écran companion (prêt) ou l'écran de téléchargement du LLM.
class BootstrapGate extends ConsumerStatefulWidget {
  const BootstrapGate({super.key});

  @override
  ConsumerState<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends ConsumerState<BootstrapGate> {
  bool _minElapsed = false;
  bool _skipRequested = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _minElapsed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<bool> modelsReady = ref.watch(modelsReadyProvider);
    final bool initResolved = !modelsReady.isLoading;

    if (shouldShowBoot(
      minElapsed: _minElapsed,
      skipRequested: _skipRequested,
      initResolved: initResolved,
    )) {
      return BootScreen(
        onSkip: () => setState(() => _skipRequested = true),
      );
    }

    return modelsReady.when(
      loading: () => const Scaffold(
        backgroundColor: KittColors.black,
        body: Center(
          child: CircularProgressIndicator(color: KittColors.scarlet),
        ),
      ),
      error: (error, _) => Scaffold(
        backgroundColor: KittColors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.error_outline,
                  color: KittColors.scarlet,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text("Erreur d'initialisation", style: KittText.label),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: KittText.mono,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A0000),
                    foregroundColor: KittColors.scarlet,
                    side: const BorderSide(color: KittColors.scarlet),
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
