import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
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
  final ValueNotifier<String> _userText = ValueNotifier<String>('');
  final ValueNotifier<String> _responseText = ValueNotifier<String>('');
  late final KittGame _game = KittGame(
    stateListenable: _state,
    levelListenable: _level,
    userTextListenable: _userText,
    responseTextListenable: _responseText,
  );

  // --- Capture state ---
  StreamSubscription<List<double>>? _capSub;
  final List<double> _captured = <double>[];
  bool _recording = false;
  bool _busy = false;

  @override
  void dispose() {
    _capSub?.cancel();
    _state.dispose();
    _level.dispose();
    _userText.dispose();
    _responseText.dispose();
    super.dispose();
  }

  Future<void> _startCapture() async {
    if (_busy || _recording) return;
    setState(() {
      _recording = true;
      _captured.clear();
    });

    try {
      final adapters = await ref.read(adaptersProvider.future);
      final stream = await adapters.audioIn.startStream(sampleRate: 16000);
      if (!mounted || !_recording) {
        try {
          await adapters.audioIn.stop();
        } catch (_) {
          // Best-effort stop on cold-start race — ignore errors.
        }
        return;
      }
      _capSub = stream.listen(
        (final List<double> chunk) => _captured.addAll(chunk),
        onError: (Object e) {
          _handleError(e);
        },
        cancelOnError: true,
      );
    } catch (e) {
      setState(() => _recording = false);
      _showError(e);
    }
  }

  Future<void> _stopCapture() async {
    if (!_recording) return;
    setState(() {
      _recording = false;
      _busy = true;
    });

    await _capSub?.cancel();
    _capSub = null;

    try {
      final adapters = await ref.read(adaptersProvider.future);
      await adapters.audioIn.stop();

      if (_captured.isNotEmpty) {
        final pipeline = await ref.read(pipelineProvider.future);
        await pipeline.runTurn(List<double>.of(_captured), 16000);
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cancelCapture() async {
    if (!_recording) return;
    setState(() {
      _recording = false;
      _captured.clear();
    });

    await _capSub?.cancel();
    _capSub = null;

    try {
      final adapters = await ref.read(adaptersProvider.future);
      await adapters.audioIn.stop();
    } catch (_) {
      // Best-effort stop on cancel — ignore errors.
    }
  }

  Future<void> _handleError(Object e) async {
    await _capSub?.cancel();
    _capSub = null;
    try {
      final adapters = await ref.read(adaptersProvider.future);
      await adapters.audioIn.stop();
    } catch (_) {
      // Best-effort stop on stream error — ignore errors.
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _busy = false;
      });
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    final String message =
        e is StateError ? 'Micro indisponible' : 'Modèles non prêts';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF3A0000),
      ),
    );
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
    ref.listen<AsyncValue<String>>(userHeardProvider, (_, next) {
      next.whenData((t) {
        _userText.value = t;
        _responseText.value = '';
      });
    });
    ref.listen<AsyncValue<String>>(responseTokenProvider, (_, next) {
      next.whenData((tok) => _responseText.value += tok);
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
                _recording
                    ? 'À L\'ÉCOUTE… (relâchez pour parler)'
                    : _label(state.valueOrNull ?? PipelineState.idle),
                style: const TextStyle(
                  color: Color(0xFFFFB000),
                  fontSize: 16,
                  letterSpacing: 2,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _TalkButton(
                onStart: _startCapture,
                onStop: _stopCapture,
                onCancel: _cancelCapture,
                recording: _recording,
              ),
            ),
          ],
        ),
      ),
    );
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
  const _TalkButton({
    required this.onStart,
    required this.onStop,
    required this.onCancel,
    required this.recording,
  });

  final AsyncCallback onStart;
  final AsyncCallback onStop;
  final AsyncCallback onCancel;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onStart(),
      onTapUp: (_) => onStop(),
      onTapCancel: onCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: recording ? const Color(0xFF3A0000) : const Color(0xFF1A0000),
          border: Border.all(
            color:
                recording ? const Color(0xFFFF4444) : const Color(0xFFFF1A1A),
            width: recording ? 3 : 2,
          ),
        ),
        child: Icon(
          Icons.mic,
          color: recording ? const Color(0xFFFF4444) : const Color(0xFFFF1A1A),
          size: 32,
        ),
      ),
    );
  }
}
