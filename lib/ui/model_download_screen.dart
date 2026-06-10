import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/models/model_catalog.dart';
import '../application/providers.dart';

/// Écran de téléchargement des modèles (première utilisation en mode réel).
/// Télécharge STT → TTS → LLM séquentiellement avec barres de progression.
/// Une fois terminé, invalide [modelsReadyProvider] pour que [BootstrapGate]
/// bascule vers [CompanionScreen].
class ModelDownloadScreen extends ConsumerStatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  ConsumerState<ModelDownloadScreen> createState() =>
      _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends ConsumerState<ModelDownloadScreen> {
  double _sttProgress = 0;
  double _ttsProgress = 0;
  double _llmProgress = 0;

  String _currentPhase = 'Initialisation…';
  bool _hasStarted = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startDownloads());
  }

  Future<void> _startDownloads() async {
    if (_hasStarted) return;
    _hasStarted = true;
    if (mounted) {
      setState(() {
        _hasError = false;
        _errorMessage = '';
        _sttProgress = 0;
        _ttsProgress = 0;
        _llmProgress = 0;
      });
    }

    try {
      final mm = await ref.read(modelManagerProvider.future);

      if (!mounted) return;
      setState(() => _currentPhase = 'Reconnaissance vocale');

      await mm.downloadModel(
        sttModel,
        onProgress: (final double p) {
          if (mounted) setState(() => _sttProgress = p);
        },
      );

      if (!mounted) return;
      setState(() => _ttsProgress = 0);
      setState(() => _currentPhase = 'Synthèse vocale');

      await mm.downloadModel(
        ttsModel,
        onProgress: (final double p) {
          if (mounted) setState(() => _ttsProgress = p);
        },
      );

      if (!mounted) return;
      setState(() => _llmProgress = 0);
      setState(() => _currentPhase = 'Cerveau (CroissantLLM)');

      await mm.downloadLlmModel(
        onProgress: (final double p) {
          if (mounted) setState(() => _llmProgress = p);
        },
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 24),
              const Text(
                'KITT',
                style: TextStyle(
                  color: Color(0xFFFFB000),
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Téléchargement des modèles — première utilisation',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Environ 2–3 Go au total. Restez connecté en Wi‑Fi.',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 40),
              _ProgressRow(
                label: 'Reconnaissance vocale',
                progress: _sttProgress,
                done: _sttProgress >= 1.0,
              ),
              const SizedBox(height: 24),
              _ProgressRow(
                label: 'Synthèse vocale',
                progress: _ttsProgress,
                done: _ttsProgress >= 1.0,
              ),
              const SizedBox(height: 24),
              _ProgressRow(
                label: 'Cerveau (CroissantLLM)',
                progress: _llmProgress,
                done: _llmProgress >= 1.0,
              ),
              const SizedBox(height: 40),
              if (_hasError) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0000),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF1A1A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Erreur de téléchargement',
                        style: TextStyle(
                          color: Color(0xFFFF1A1A),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A0000),
                    foregroundColor: const Color(0xFFFF1A1A),
                    side: const BorderSide(color: Color(0xFFFF1A1A)),
                  ),
                  onPressed: _startDownloads,
                  child: const Text('Réessayer'),
                ),
              ] else if (!_hasStarted) ...<Widget>[
                const Text(
                  'Prêt à télécharger.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ] else ...<Widget>[
                Text(
                  _currentPhase,
                  style: const TextStyle(
                    color: Color(0xFFFFB000),
                    fontSize: 13,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.progress,
    required this.done,
  });

  final String label;
  final double progress;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: done ? const Color(0xFFFFB000) : Colors.white70,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
            if (done)
              const Icon(Icons.check_circle, color: Color(0xFFFFB000), size: 16)
            else
              Text(
                '${(progress * 100).toStringAsFixed(0)} %',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFF1A1A1A),
            valueColor: AlwaysStoppedAnimation<Color>(
              done ? const Color(0xFFFFB000) : const Color(0xFFCC8800),
            ),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
