import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/jsc/jsc_api.dart';
import '../../services/jsc/jsc_auth_service.dart';
import '../../theme.dart';

class JscLoginScreen extends StatefulWidget {
  const JscLoginScreen({super.key});

  @override
  State<JscLoginScreen> createState() => _JscLoginScreenState();
}

class _JscLoginScreenState extends State<JscLoginScreen> {
  JscLoginMode _mode = JscLoginMode.admin;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _showServerConfig = false;
  late TextEditingController _baseUrl;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: context.read<JscAuthService>().baseUrl);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = context.read<JscAuthService>();
      if (_baseUrl.text.trim() != auth.baseUrl) {
        await auth.setBaseUrl(_baseUrl.text);
      }
      final api = JscApi(auth);
      final r = await api.login(
        mode: _mode,
        email: _email.text.trim(),
        password: _password.text,
      );
      await api.dispose();
      await auth.saveSession(token: r.token, user: r.user);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Support Center',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              const SizedBox(height: 8),
              Icon(Icons.support_agent, size: 64, color: AppTheme.primary),
              const SizedBox(height: 12),
              const Text(
                'JUICE Support Center',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SegmentedButton<JscLoginMode>(
                segments: const [
                  ButtonSegment(value: JscLoginMode.admin, label: Text('Admin / Agent')),
                  ButtonSegment(value: JscLoginMode.client, label: Text('Client')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
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
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showServerConfig = !_showServerConfig),
                  child: Text(
                    _showServerConfig ? 'Hide server settings' : 'Server settings',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              ),
              if (_showServerConfig) ...[
                TextField(
                  controller: _baseUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://juicesupportcenter.com',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Change only if you self-host or use a different domain.',
                  style: TextStyle(color: Colors.black45, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
