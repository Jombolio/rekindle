import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Legacy login screen — now replaced by AddSourceScreen.
/// Kept as a named route stub to avoid broken deep links.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/source/add');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
