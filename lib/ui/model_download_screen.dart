import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/models/model_catalog.dart';
import '../application/providers.dart';
import '../util/byte_format.dart';
import 'theme/kitt_theme.dart';

/// Écran de téléchargement des modèles (première utilisation en mode réel).
/// Récupère STT → TTS → LLM par chunks parallèles, en affichant pour chaque
/// module les octets reçus / total, un total agrégé et le débit. Une fois
/// terminé, invalide [modelsReadyProvider] pour que [BootstrapGate] bascule.
class ModelDownloadScreen extends ConsumerStatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  ConsumerState<ModelDownloadScreen> createState() =>
      _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends ConsumerState<ModelDownloadScreen> {
  DownloadProgress _stt = const DownloadProgress(received: 0, total: 0);
  DownloadProgress _tts = const DownloadProgress(received: 0, total: 0);
  DownloadProgress _llm = const DownloadProgress(received: 0, total: 0);

  String _currentPhase = 'Initialisation…';
  bool _hasStarted = false;
  bool _hasError = false;
  String _errorMessage = '';

  // Mesure de débit (octets/s) lissée.
  double _rate = 0;
  int _lastBytes = 0;
  DateTime _lastTick = DateTime.now();

  int get _received => _stt.received + _tts.received + _llm.received;
  int get _total => _stt.total + _tts.total + _llm.total;
  double get _fraction => _total > 0 ? (_received / _total).clamp(0.0, 1.0) : 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startDownloads());
  }

  void _onProgress(void Function() apply) {
    if (!mounted) return;
    setState(() {
      apply();
      _updateRate();
    });
  }

  void _updateRate() {
    final now = DateTime.now();
    final dtMs = now.difference(_lastTick).inMilliseconds;
    if (dtMs < 200) return; // throttle des recalculs
    final deltaBytes = _received - _lastBytes;
    if (deltaBytes > 0) {
      final instant = deltaBytes / (dtMs / 1000.0);
      // Lissage exponentiel pour un affichage stable.
      _rate = _rate == 0 ? instant : _rate * 0.7 + instant * 0.3;
    }
    _lastBytes = _received;
    _lastTick = now;
  }

  Future<void> _startDownloads() async {
    if (_hasStarted) return;
    _hasStarted = true;
    if (mounted) {
      setState(() {
        _hasError = false;
        _errorMessage = '';
        _stt = const DownloadProgress(received: 0, total: 0);
        _tts = const DownloadProgress(received: 0, total: 0);
        _llm = const DownloadProgress(received: 0, total: 0);
        _rate = 0;
        _lastBytes = 0;
        _lastTick = DateTime.now();
      });
    }

    try {
      final mm = await ref.read(modelManagerProvider.future);

      if (!mounted) return;
      setState(() => _currentPhase = 'Reconnaissance vocale');
      await mm.downloadModel(
        sttModel,
        onProgress: (p) => _onProgress(() => _stt = p),
      );

      if (!mounted) return;
      setState(() => _currentPhase = 'Synthèse vocale');
      await mm.downloadModel(
        ttsModel,
        onProgress: (p) => _onProgress(() => _tts = p),
      );

      if (!mounted) return;
      setState(() => _currentPhase = 'Cerveau (CroissantLLM)');
      await mm.downloadLlmModel(
        onProgress: (p) => _onProgress(() => _llm = p),
      );

      if (mounted) {
        ref.invalidate(modelsReadyProvider);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _hasStarted = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _hasStarted && !_hasError;
    return Scaffold(
      backgroundColor: KittColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'K I T T',
                textAlign: TextAlign.center,
                style: KittText.display,
              ),
              const SizedBox(height: 6),
              Text(
                _hasError
                    ? 'ANOMALIE DÉTECTÉE'
                    : (_fraction >= 1.0
                        ? 'SYSTÈMES OPÉRATIONNELS'
                        : 'INITIALISATION DES MODULES'),
                textAlign: TextAlign.center,
                style: KittText.label,
              ),
              const SizedBox(height: 18),
              _ScannerBar(active: active && _fraction < 1.0),
              const SizedBox(height: 22),
              Expanded(
                child: ListView(
                  children: <Widget>[
                    _ModuleTile(
                      label: 'OREILLE',
                      subtitle: 'Reconnaissance vocale · zipformer FR',
                      progress: _stt,
                    ),
                    const SizedBox(height: 14),
                    _ModuleTile(
                      label: 'VOIX',
                      subtitle: 'Synthèse vocale · VITS/Piper FR',
                      progress: _tts,
                    ),
                    const SizedBox(height: 14),
                    _ModuleTile(
                      label: 'CERVEAU',
                      subtitle: 'CroissantLLM · GGUF Q4_K_M',
                      progress: _llm,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _TotalPanel(
                received: _received,
                total: _total,
                fraction: _fraction,
                rate: _rate,
                phase: _currentPhase,
                active: active,
              ),
              if (_hasError) ...<Widget>[
                const SizedBox(height: 12),
                _ErrorPanel(message: _errorMessage, onRetry: _startDownloads),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Le balayage rouge horizontal signature K2000, en mode « barre d'activité ».
class _ScannerBar extends StatefulWidget {
  const _ScannerBar({required this.active});
  final bool active;

  @override
  State<_ScannerBar> createState() => _ScannerBarState();
}

class _ScannerBarState extends State<_ScannerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: _ScannerPainter(
            t: 0.5 + 0.5 * math.sin(_c.value * math.pi),
            active: widget.active,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ScannerPainter extends CustomPainter {
  _ScannerPainter({required this.t, required this.active});
  final double t;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = KittColors.scarletDim.withValues(alpha: 0.25)
        ..strokeWidth = 2,
    );
    if (!active) return;
    final x = t * size.width;
    final w = size.width * 0.16;
    final glow = Rect.fromCenter(
      center: Offset(x, y),
      width: w,
      height: size.height,
    );
    canvas.drawRect(
      glow,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            KittColors.scarlet,
            KittColors.scarlet.withValues(alpha: 0),
          ],
        ).createShader(glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(_ScannerPainter old) => old.t != t || old.active != active;
}

/// Une ligne module : libellé, sous-titre, ratio d'octets et barre glow animée.
class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.label,
    required this.subtitle,
    required this.progress,
  });

  final String label;
  final String subtitle;
  final DownloadProgress progress;

  @override
  Widget build(BuildContext context) {
    final done = progress.isComplete;
    final pct = (progress.fraction * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: KittColors.panel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: done
              ? KittColors.amber.withValues(alpha: 0.5)
              : KittColors.scarletDim.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _StatusDot(done: done),
              const SizedBox(width: 10),
              Text(label, style: KittText.label),
              const Spacer(),
              Text(
                done ? 'OK' : '$pct %',
                style: KittText.readout.copyWith(
                  color: done ? KittColors.amber : KittColors.scarlet,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: KittText.mono),
          const SizedBox(height: 10),
          _GlowBar(fraction: progress.fraction, done: done),
          const SizedBox(height: 8),
          Text(
            formatBytesRatio(progress.received, progress.total),
            style: KittText.mono,
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = done ? KittColors.amber : KittColors.scarlet;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: c.withValues(alpha: 0.7),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

/// Barre rouge à halo, animée en douceur entre deux valeurs pour rester fluide
/// même si les paliers d'octets arrivent par à-coups.
class _GlowBar extends StatelessWidget {
  const _GlowBar({required this.fraction, required this.done});
  final double fraction;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final fill = done ? KittColors.amber : KittColors.scarlet;
    return LayoutBuilder(
      builder: (_, constraints) {
        return Container(
          height: 10,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: KittColors.scarletDim.withValues(alpha: 0.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: fraction.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              builder: (_, v, __) => Container(
                width: constraints.maxWidth * v,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[fill.withValues(alpha: 0.6), fill],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: fill.withValues(alpha: 0.8),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Panneau de synthèse : total reçu / total, débit, phase et barre globale.
class _TotalPanel extends StatelessWidget {
  const _TotalPanel({
    required this.received,
    required this.total,
    required this.fraction,
    required this.rate,
    required this.phase,
    required this.active,
  });

  final int received;
  final int total;
  final double fraction;
  final double rate;
  final String phase;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KittColors.panel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KittColors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text('TOTAL', style: KittText.label),
              Text(
                '${(fraction * 100).toStringAsFixed(0)} %',
                style: KittText.readout,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _GlowBar(fraction: fraction, done: fraction >= 1.0),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(formatBytesRatio(received, total), style: KittText.readout),
              Text(
                active && fraction < 1.0 ? formatRate(rate) : '—',
                style: KittText.readout,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(fraction >= 1.0 ? 'Prêt.' : phase, style: KittText.mono),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0000),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KittColors.scarlet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Erreur de téléchargement',
            style: KittText.label.copyWith(color: KittColors.scarlet),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: KittText.mono,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: KittColors.scarlet, width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: KittColors.scarlet.withValues(alpha: 0.4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Text(
                'RÉESSAYER',
                style: KittText.label.copyWith(color: KittColors.scarlet),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
