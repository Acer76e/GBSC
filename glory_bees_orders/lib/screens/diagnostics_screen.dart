import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/diagnostics.dart';
import '../services/settings_service.dart';
import '../services/woo_api.dart';
import '../theme.dart';

/// Asks the store a few direct questions and shows the answers verbatim, so an
/// empty order list can be explained instead of guessed at.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<ProbeResult>? _results;
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    final diagnostics = Diagnostics(
      context.read<WooApi>(),
      context.read<AppSettings>(),
    );
    final results = await diagnostics.run();
    if (!mounted) return;
    setState(() {
      _results = results;
      _running = false;
    });
  }

  String get _asText {
    final settings = context.read<AppSettings>();
    return [
      'Glory Bees Orders diagnostics',
      'Store: ${settings.storeUrl}',
      'Statuses selected: ${settings.activeStatuses.join(', ')}',
      '',
      ...?_results?.map((r) => r.asText),
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          if (_results != null)
            IconButton(
              tooltip: 'Copy results',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _asText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Results copied')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This asks the store four questions and shows exactly what '
                    'it answers. Nothing is changed.',
                    style: TextStyle(color: AppTheme.text, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Store: ${settings.storeUrl}\n'
                    'Statuses: ${settings.activeStatuses.join(', ')}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The API key never appears in these results, so they are '
                    'safe to copy and share.',
                    style: TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _running ? null : _run,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_running ? 'Asking the store…' : 'Run checks'),
          ),
          for (final result in _results ?? const <ProbeResult>[]) ...[
            const SizedBox(height: 12),
            _ProbeCard(result: result),
          ],
          if (_results != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _asText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Results copied')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy all results'),
              style:
                  OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProbeCard extends StatelessWidget {
  final ProbeResult result;

  const _ProbeCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  result.ok ? Icons.check_circle : Icons.error_outline,
                  size: 18,
                  color: result.ok ? AppTheme.freshFg : AppTheme.lateFg,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              result.outcome,
              style: const TextStyle(fontSize: 14, color: AppTheme.text),
            ),
            if (result.detail != null) ...[
              const SizedBox(height: 6),
              SelectableText(
                result.detail!,
                style: const TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
            ],
            const SizedBox(height: 8),
            SelectableText(
              result.url,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.muted, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
