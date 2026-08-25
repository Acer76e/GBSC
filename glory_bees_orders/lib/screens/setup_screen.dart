import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_service.dart';
import '../services/woo_api.dart';
import '../theme.dart';

/// First-run screen: point the app at the store and hand it an API key.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _urlController;
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();

  bool _obscureSecret = true;
  bool _busy = false;
  WooException? _error;

  @override
  void initState() {
    super.initState();
    final saved = context.read<AppSettings>().storeUrl;
    _urlController =
        TextEditingController(text: saved.isEmpty ? kDefaultStoreUrl : saved);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final settings = context.read<AppSettings>();
    final api = context.read<WooApi>();
    final creds = WooCreds(
      storeUrl: normalizeStoreUrl(_urlController.text),
      consumerKey: _keyController.text.trim(),
      consumerSecret: _secretController.text.trim(),
    );

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Prove the key works before storing it, so a typo can't leave the app
      // sitting on a broken order list.
      await api.testConnection(creds: creds);
      await settings.saveCredentials(
        storeUrl: creds.storeUrl,
        consumerKey: creds.consumerKey,
        consumerSecret: creds.consumerSecret,
      );
      // The app shell watches AppSettings and swaps in the orders screen.
    } on WooException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openKeysPage() async {
    final base = normalizeStoreUrl(_urlController.text);
    if (base.isEmpty) return;
    final uri = Uri.parse(
        '$base/wp-admin/admin.php?page=wc-settings&tab=advanced&section=keys');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t open the browser.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.honey,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.local_shipping_outlined,
                      color: AppTheme.primaryDark, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Glory Bees Orders',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.text,
                        ),
                      ),
                      Text(
                        'Website orders waiting to ship',
                        style: TextStyle(color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            const _FieldLabel('Store web address'),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(hintText: kDefaultStoreUrl),
            ),
            const SizedBox(height: 18),
            const _FieldLabel('Consumer key'),
            TextField(
              controller: _keyController,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: 'ck_…'),
            ),
            const SizedBox(height: 18),
            const _FieldLabel('Consumer secret'),
            TextField(
              controller: _secretController,
              autocorrect: false,
              enableSuggestions: false,
              obscureText: _obscureSecret,
              decoration: InputDecoration(
                hintText: 'cs_…',
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscureSecret = !_obscureSecret),
                  icon: Icon(_obscureSecret
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Card(
                color: AppTheme.lateBg,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _error!.message,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.lateFg,
                        ),
                      ),
                      if (_error!.detail != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _error!.detail!,
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.text),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: _busy ? null : _connect,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Connect'),
            ),
            const SizedBox(height: 22),
            const HowToGetAKey(),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _openKeysPage,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open the API keys page'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.muted,
        ),
      ),
    );
  }
}

/// The one-time WooCommerce setup, spelled out. Shown on the setup screen and
/// again in Settings, since a key can be revoked long after first run.
class HowToGetAKey extends StatelessWidget {
  const HowToGetAKey({super.key});

  static const List<String> steps = [
    'Sign in to the website as an administrator.',
    'Go to WooCommerce → Settings → Advanced → REST API.',
    'Tap "Add key" (or "Create an API key").',
    'Description: "Phone — orders". User: your admin account.',
    'Permissions: "Read" to just look, or "Read/Write" to also mark orders '
        'shipped from the phone.',
    'Tap "Generate API key", then copy the consumer key and secret into the '
        'boxes above. They are only shown once.',
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text(
              'How do I get a key?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            children: [
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${i + 1}.',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          steps[i],
                          style: const TextStyle(
                              fontSize: 14, color: AppTheme.text, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
