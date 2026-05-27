import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/cloudflare_api.dart';
import '../theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthMode _mode = AuthMode.apiToken;
  final _tokenCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _emailCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Credentials creds;
      if (_mode == AuthMode.apiToken) {
        final token = _tokenCtrl.text.trim();
        if (token.isEmpty) throw ArgumentError('Enter an API token');
        creds = Credentials.apiToken(token);
      } else {
        final email = _emailCtrl.text.trim();
        final key = _keyCtrl.text.trim();
        if (email.isEmpty || key.isEmpty) {
          throw ArgumentError('Enter email and Global API Key');
        }
        creds = Credentials.globalKey(email: email, globalKey: key);
      }

      // Verify first; only save on success so a failed verify doesn't
      // flash the next screen and lose its error message on dispose.
      final err = await CloudflareApi.verifyWithCredentialsForError(creds);
      if (err != null) {
        throw Exception('Cloudflare rejected the credentials: $err');
      }

      final auth = context.read<AuthService>();
      if (_mode == AuthMode.apiToken) {
        await auth.saveApiToken(creds.token!);
      } else {
        await auth.saveGlobalKey(email: creds.email!, key: creds.globalKey!);
      }
      // After saveX, the root rebuilds and this widget is disposed.
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              const SizedBox(height: 16),
              Icon(Icons.cloud_outlined, size: 64, color: AppTheme.primary),
              const SizedBox(height: 12),
              const Text(
                'Cloudflare Mobile',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in with your Cloudflare credentials',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 28),
              SegmentedButton<AuthMode>(
                segments: const [
                  ButtonSegment(value: AuthMode.apiToken, label: Text('API Token')),
                  ButtonSegment(value: AuthMode.globalKey, label: Text('Global Key')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 20),
              if (_mode == AuthMode.apiToken) ...[
                TextField(
                  controller: _tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Token',
                    hintText: 'Created at dash.cloudflare.com/profile/api-tokens',
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Account email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Global API Key'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Sign in'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Credentials are stored encrypted on this device only.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
