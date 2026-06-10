import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pipeline_state.dart';
import '../application/providers.dart';
import 'companion_game.dart';

/// Écran companion : scanner + modulateur (Flame), libellé d'état, bouton
/// « maintenir pour parler » (repli du wake-word, cf. débrief D6/§4.1).
class CompanionScreen extends ConsumerStatefulWidget {
  const CompanionScreen({super.key});

  @override
  ConsumerState<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends ConsumerState<CompanionScreen> {
  final ValueNotifier<PipelineState> _state = ValueNotifier<PipelineState>(
    PipelineState.idle,
  );
  final ValueNotifier<double> _level = ValueNotifier<double>(0);
  late final KittGame _game = KittGame(
    stateListenable: _state,
    levelListenable: _level,
  );

  @override
  void dispose() {
    _state.dispose();
    _level.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pont providers → ValueNotifier consommés par le jeu Flame.
    ref.listen<AsyncValue<PipelineState>>(pipelineStateProvider, (_, next) {
      next.whenData((s) => _state.value = s);
    });
    ref.listen<AsyncValue<double>>(audioLevelProvider, (_, next) {
      next.whenData((l) => _level.value = l);
    });

    final AsyncValue<PipelineState> state = ref.watch(pipelineStateProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(child: GameWidget<KittGame>(game: _game)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _label(state.valueOrNull ?? PipelineState.idle),
                style: const TextStyle(
                  color: Color(0xFFFFB000),
                  fontSize: 16,
                  letterSpacing: 2,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _TalkButton(onPressed: _onTalk),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onTalk() async {
    final pipeline = await ref.read(pipelineProvider.future);
    // Repli bouton : on simule un buffer capté puis on lance un tour.
    await pipeline.runTurn(List<double>.filled(1600, 0), 16000);
  }

  String _label(PipelineState s) {
    switch (s) {
      case PipelineState.idle:
        return 'EN VEILLE — dites « KITT »';
      case PipelineState.listening:
        return 'À L\'ÉCOUTE…';
      case PipelineState.thinking:
        return 'RÉFLEXION…';
      case PipelineState.responding:
        return 'KITT RÉPOND…';
      case PipelineState.clarifying:
        return 'PARDON ? POUVEZ-VOUS RÉPÉTER ?';
    }
  }
}

class _TalkButton extends StatelessWidget {
  const _TalkButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A0000),
          border: Border.all(color: const Color(0xFFFF1A1A), width: 2),
        ),
        child: const Icon(Icons.mic, color: Color(0xFFFF1A1A), size: 32),
      ),
    );
  }
}
