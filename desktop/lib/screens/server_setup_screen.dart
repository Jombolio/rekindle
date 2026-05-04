import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Legacy server setup screen — now replaced by AddSourceScreen.
/// Kept as a named route stub to avoid broken deep links.
class ServerSetupScreen extends ConsumerWidget {
  const ServerSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/source/add');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
