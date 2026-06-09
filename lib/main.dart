import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/companion_screen.dart';

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
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const CompanionScreen(),
    );
  }
}
