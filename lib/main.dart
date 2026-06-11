import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/bootstrap_gate.dart';
import 'ui/theme/kitt_theme.dart';

void main() {
  runApp(const ProviderScope(child: KittApp()));
}

class KittApp extends StatelessWidget {
  const KittApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KITT',
      debugShowCheckedModeBanner: false,
      theme: KittTheme.build(),
      home: const BootstrapGate(),
    );
  }
}
