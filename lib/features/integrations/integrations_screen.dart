import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../../data/api/api_client.dart';
import '../bookmarks/bookmark_display.dart';
import '../common/text_prompt.dart';

/// Connects the app to a Capsula API server and manages API tokens for
/// scripts and other integrations.
class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  final _url = TextEditingController();
  bool _initialized = false;
  String? _urlError;
  Future<bool>? _reachable;
  Future<List<ApiTokenInfo>>? _tokens;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _url.text =
        AppDependencies.of(context).apiSettings.baseUrl?.toString() ?? '';
    _refresh();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  CapsulaApiClient? get _client => AppDependencies.of(context).apiClient();

  void _refresh() {
    final client = _client;
    setState(() {
      _reachable = client?.isReachable();
      _tokens = client?.tokens();
    });
  }

  Future<void> _saveUrl() async {
    final ok = await AppDependencies.of(context).apiSettings.save(_url.text);
    if (!mounted) return;
    setState(
      () => _urlError = ok
          ? null
          : 'Enter an address like https://api.example.com',
    );
    if (ok) _refresh();
  }

  Future<void> _createToken() async {
    final client = _client;
    if (client == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = await promptText(
      context,
      title: 'New API token',
      label: 'Name, e.g. "Browser extension"',
      action: 'Create',
      maxLength: 100,
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final (_, secret) = await client.createToken(name.trim());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _NewTokenDialog(secret: secret),
      );
      _refresh();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not create: $e')));
    }
  }

  Future<void> _revoke(ApiTokenInfo token) async {
    final client = _client;
    if (client == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Revoke "${token.name}"?'),
        content: const Text('Anything using this token stops working.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await client.deleteToken(token.id);
      _refresh();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not revoke: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUrl = AppDependencies.of(context).apiSettings.baseUrl != null;

    return Scaffold(
      appBar: AppBar(title: const Text('API & integrations')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              Text('API server', style: theme.textTheme.titleMedium),
              const SizedBox(height: Gap.xs),
              Text(
                'Your self-hosted Capsula API. It lets scripts and other apps '
                'use your library, and reads pages for the web app.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: Gap.md),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Server address',
                  hintText: 'https://api.example.com',
                  errorText: _urlError,
                ),
                onSubmitted: (_) => _saveUrl(),
              ),
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  if (hasUrl)
                    Expanded(
                      child: FutureBuilder<bool>(
                        future: _reachable,
                        builder: (context, s) => _Status(
                          checking: s.connectionState != ConnectionState.done,
                          ok: s.data ?? false,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(88, 40),
                    ),
                    onPressed: _saveUrl,
                    child: const Text('Save'),
                  ),
                ],
              ),
              if (hasUrl) ...[
                const Divider(height: Gap.xl * 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'API tokens',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _createToken,
                      icon: const Icon(Icons.add),
                      label: const Text('New token'),
                    ),
                  ],
                ),
                Text(
                  'Use a token as "Authorization: Bearer <token>". Tokens can '
                  'read and change your bookmarks, so keep them private.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: Gap.sm),
                FutureBuilder<List<ApiTokenInfo>>(
                  future: _tokens,
                  builder: (context, s) {
                    if (s.hasError) {
                      return Text(
                        'Could not load tokens: ${s.error}',
                        style: TextStyle(color: theme.colorScheme.error),
                      );
                    }
                    final tokens = s.data;
                    if (tokens == null) {
                      return const Padding(
                        padding: EdgeInsets.all(Gap.md),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (tokens.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: Gap.md),
                        child: Text('No tokens yet.'),
                      );
                    }
                    return Column(
                      children: [
                        for (final t in tokens)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.key_outlined),
                            title: Text(t.name),
                            subtitle: Text(
                              'Created ${formatSavedDate(t.createdAt).toLowerCase()}'
                              '${t.lastUsedAt == null ? ' · never used' : ' · last used ${formatSavedDate(t.lastUsedAt!).toLowerCase()}'}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Revoke ${t.name}',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _revoke(t),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.checking, required this.ok});

  final bool checking;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, text) = checking
        ? (Icons.sync, scheme.onSurfaceVariant, 'Checking…')
        : ok
        ? (Icons.cloud_done_outlined, scheme.primary, 'Connected')
        : (Icons.cloud_off_outlined, scheme.error, 'Not reachable');
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: Gap.sm),
        Text(text, style: TextStyle(color: color)),
      ],
    );
  }
}

class _NewTokenDialog extends StatelessWidget {
  const _NewTokenDialog({required this.secret});

  final String secret;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Copy your new token'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('It won\'t be shown again.'),
        const SizedBox(height: Gap.md),
        SelectableText(secret, style: const TextStyle(fontFamily: 'monospace')),
      ],
    ),
    actions: [
      TextButton.icon(
        onPressed: () => Clipboard.setData(ClipboardData(text: secret)),
        icon: const Icon(Icons.copy),
        label: const Text('Copy'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
