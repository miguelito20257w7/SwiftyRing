import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/pages/login_page.dart';

void main() {
  runApp(const ProviderScope(child: SwiftyRingApp()));
}

class SwiftyRingApp extends StatelessWidget {
  const SwiftyRingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwiftyRing',
      theme: AppTheme.light,
      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
