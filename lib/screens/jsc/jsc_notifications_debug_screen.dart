import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/jsc/jsc_auth_service.dart';
import '../../services/jsc/jsc_fcm_service.dart';
import '../../theme.dart';

class JscNotificationsDebugScreen extends StatefulWidget {
  const JscNotificationsDebugScreen({super.key});

  @override
  State<JscNotificationsDebugScreen> createState() =>
      _JscNotificationsDebugScreenState();
}

class _JscNotificationsDebugScreenState extends State<JscNotificationsDebugScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final fcm = context.watch<JscFcmService>();
    final auth = context.watch<JscAuthService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _row('Firebase initialized', fcm.firebaseOk ? 'yes' : 'no',
              fcm.firebaseOk ? Colors.green : Colors.red),
          if (fcm.lastInitError != null)
            _multiLine('Init error', fcm.lastInitError!),
          _row('Permission status', fcm.permissionStatus,
              fcm.permissionStatus == 'authorized' ? Colors.green : Colors.orange),
          _row('FCM token present', fcm.currentToken != null ? 'yes' : 'no',
              fcm.currentToken != null ? Colors.green : Colors.red),
          if (fcm.currentToken != null)
            _multiLine('Token (tap to copy)',
                '${fcm.currentToken!.substring(0, 28)}…',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: fcm.currentToken!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Token copied')),
                  );
                }),
          _row('Signed in to JSC', auth.isAuthenticated ? 'yes' : 'no',
              auth.isAuthenticated ? Colors.green : Colors.red),
          _row('Last register result',
              fcm.lastRegisterResult ?? 'never tried',
              fcm.lastRegisterResult == 'ok'
                  ? Colors.green
                  : (fcm.lastRegisterResult == null ? Colors.grey : Colors.red)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await context.read<JscFcmService>().registerNow();
                    if (mounted) setState(() => _busy = false);
                  },
            icon: const Icon(Icons.refresh),
            label: Text(_busy ? 'Registering…' : 'Register token with JSC'),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await context.read<JscFcmService>().init();
                    if (mounted) setState(() => _busy = false);
                  },
            icon: const Icon(Icons.restart_alt),
            label: const Text('Re-init Firebase / refresh token'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.black87),
          ),
          const SizedBox(height: 24),
          Card(
            color: const Color(0xFFFFF4D6),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'If "Last register result" stays "ok" but you still don\'t '
                'receive notifications, the issue is Android-side. Check '
                'Settings → Apps → JUICE Command → Notifications and make '
                'sure they\'re enabled, with no per-channel mute.',
                style: TextStyle(fontSize: 12, color: Color(0xFF8A5A00)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _multiLine(String label, String value, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
