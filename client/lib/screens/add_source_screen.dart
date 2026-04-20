import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api_client.dart';
import '../core/api/auth_api.dart';
import '../core/models/server_source.dart';
import '../providers/auth_provider.dart';
import '../providers/sources_provider.dart';

/// Two-step screen: (1) enter server URL + display name, (2) log in.
/// On success the source (with token) is added to sourcesProvider.
class AddSourceScreen extends ConsumerStatefulWidget {
  const AddSourceScreen({super.key});

  @override
  ConsumerState<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends ConsumerState<AddSourceScreen> {
  // Step 1 controllers
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  // Step 2 controllers
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _setupTokenCtrl = TextEditingController();

  int _step = 1;
  bool _obscure = true;
  bool _isSetupMode = false;
  bool _busy = false;
  String? _error;

  // Validated source from step 1, filled in before step 2
  ServerSource? _pendingSource;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _setupTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final rawUrl = _urlCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (rawUrl.isEmpty) {
      setState(() => _error = 'Please enter a server URL.');
      return;
    }
    final url = rawUrl.endsWith('/') ? rawUrl : '$rawUrl/';
    setState(() { _busy = true; _error = null; });

    bool setupNeeded = false;
    try {
      final client = ApiClient(baseUrl: url);
      final authApi = AuthApi(client);
      await authApi.me();
      setupNeeded = await authApi.needsSetup();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != 401 && status != 409) {
        setState(() {
          _busy = false;
          _error = 'Could not reach server. Check the URL and try again.';
        });
        return;
      }
    } catch (_) {
      setState(() {
        _busy = false;
        _error = 'Could not reach server. Check the URL and try again.';
      });
      return;
    }

    _pendingSource = ServerSource.create(
      name: name.isEmpty ? _hostFromUrl(rawUrl) : name,
      baseUrl: url,
    );
    setState(() { _busy = false; _step = 2; _isSetupMode = setupNeeded; });
  }

  Future<void> _login() async {
    final source = _pendingSource;
    if (source == null) return;

    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    if (username.isEmpty || password.isEmpty) return;
    if (_isSetupMode && _setupTokenCtrl.text.trim().isEmpty) return;

    setState(() { _busy = true; _error = null; });

    try {
      final client = ApiClient(baseUrl: source.baseUrl);
      final AuthResult result;
      if (_isSetupMode) {
        result = await AuthApi(client)
            .setup(username, password, _setupTokenCtrl.text.trim());
      } else {
        result = await AuthApi(client).login(username, password);
      }

      final withToken = source.copyWith(token: result.token);
      await ref.read(sourcesProvider.notifier).add(withToken);
      ref.read(activeSourceIdProvider.notifier).state = withToken.id;

      if (mounted) context.go('/libraries');
    } on DioException catch (e) {
      setState(() {
        _busy = false;
        _error = AuthNotifier.errorMessage(e);
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  String _hostFromUrl(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return 'Rekindle Server';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 1 ? 'Add Server' : 'Sign In'),
        leading: _step == 2
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() { _step = 1; _error = null; }),
              )
            : (ref.read(sourcesProvider).isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.go('/libraries'),
                  )
                : null),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _step == 1 ? _buildStep1(context) : _buildStep2(context),
          ),
        ),
      ),
    );
  }

  Widget _buildStep1(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.dns_outlined,
            size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text('Connect to a Rekindle Server',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Enter the server URL and an optional display name.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center),
        const SizedBox(height: 32),
        if (_error != null) ...[
          _ErrorBanner(_error!),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _urlCtrl,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            hintText: 'http://192.168.1.100:8080',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {},
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Display name (optional)',
            hintText: 'Home Server',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.label_outline),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _connect(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: _busy
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Connect'),
        ),
      ],
    );
  }

  Widget _buildStep2(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.login,
            size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        Text(_isSetupMode ? 'Create Admin Account' : 'Sign In',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(_pendingSource?.baseUrl ?? '',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        if (_error != null) ...[
          _ErrorBanner(_error!),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _userCtrl,
          decoration: const InputDecoration(
            labelText: 'Username',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person_outline),
          ),
          autofocus: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passCtrl,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          obscureText: _obscure,
          textInputAction:
              _isSetupMode ? TextInputAction.next : TextInputAction.done,
          onSubmitted: (_) => _isSetupMode ? null : _login(),
        ),
        if (_isSetupMode) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _setupTokenCtrl,
            decoration: const InputDecoration(
              labelText: 'Setup token',
              hintText: 'Printed to server log on first boot',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _login,
          child: _busy
              ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isSetupMode ? 'Create Account' : 'Sign In'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () =>
              setState(() { _isSetupMode = !_isSetupMode; _error = null; }),
          child: Text(_isSetupMode
              ? 'Already have an account?'
              : 'First time setup'),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
