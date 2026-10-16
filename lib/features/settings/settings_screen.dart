import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/display_preferences.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../bookmarks/library_navigation.dart';
import '../export/export_dialog.dart';

/// Account, storage, library tools, integrations and preferences.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Switches between the on-device library and an account, after
  /// explaining that the two libraries are separate.
  static Future<void> _switchStorage(
    BuildContext context, {
    required bool toDevice,
  }) async {
    final backend = AppDependencies.of(context).backend;
    final router = GoRouter.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          toDevice ? 'Use on this device only?' : 'Use an account instead?',
        ),
        content: Text(
          toDevice
              ? 'Capsula will keep a separate library on this device, without '
                    'an account. Your account library stays in your account; '
                    'switch back any time in Settings.'
              : 'Your on-device library stays on this device and is not '
                    'copied to your account. To bring it along, export it '
                    'first, then import it after signing in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (toDevice) {
      await backend.useDevice();
    } else {
      await backend.useAccount();
    }
    router.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);
    final backend = deps.backend;
    final deviceOnly = backend.deviceOnly;
    final user = deps.authSession.user;
    final handle = userHandle(user);
    final theme = Theme.of(context);

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.lg, Gap.md, Gap.xs),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.only(bottom: Gap.xl),
            children: [
              header('Account'),
              if (deviceOnly) ...[
                const ListTile(
                  leading: Icon(Icons.phone_android),
                  title: Text('On this device only'),
                  subtitle: Text(
                    'No account. Your library is not synced or backed up; '
                    'export it to keep a copy.',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('Use an account instead'),
                  subtitle: const Text('Sign in and sync across devices'),
                  onTap: () => _switchStorage(context, toDevice: false),
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(handle.isEmpty ? 'Signed in' : '@$handle'),
                  subtitle: user?.email == null ? null : Text(user!.email!),
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Log out'),
                  onTap: () {
                    deps.authRepository.signOut();
                  },
                ),
                if (backend.canUseDevice)
                  ListTile(
                    leading: const Icon(Icons.phone_android),
                    title: const Text('Use on this device only'),
                    subtitle: const Text('Without an account or sync'),
                    onTap: () => _switchStorage(context, toDevice: true),
                  ),
              ],
              header('Library'),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Import bookmarks'),
                subtitle: const Text(
                  'From browsers, Raindrop, Pocket or a file',
                ),
                onTap: () => context.push(AppRoutes.import),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export library'),
                subtitle: const Text('JSON backup or browser bookmarks'),
                onTap: () => showExportDialog(context),
              ),
              ListTile(
                leading: const Icon(Icons.build_outlined),
                title: const Text('Maintenance'),
                subtitle: const Text(
                  'Broken links, duplicates, page text index',
                ),
                onTap: () => context.push(AppRoutes.maintenance),
              ),
              header('Saving'),
              ListenableBuilder(
                listenable: deps.display,
                builder: (context, _) => SwitchListTile(
                  secondary: const Icon(Icons.content_paste_go),
                  title: const Text('Offer to save copied links'),
                  subtitle: Text(
                    kIsWeb
                        ? 'Available in the Android app'
                        : 'When you copy a link in another app, Capsula '
                              'offers to save it when you open it.',
                  ),
                  value: !kIsWeb && deps.display.offerCopiedLinks,
                  onChanged: kIsWeb ? null : deps.display.setOfferCopiedLinks,
                ),
              ),
              header('Display'),
              ListenableBuilder(
                listenable: deps.display,
                builder: (context, _) => ListTile(
                  leading: const Icon(Icons.view_agenda_outlined),
                  title: const Text('Library layout'),
                  trailing: DropdownButton<LibraryLayout>(
                    value: deps.display.layout,
                    underline: const SizedBox.shrink(),
                    onChanged: (l) {
                      if (l != null) deps.display.setLayout(l);
                    },
                    items: [
                      for (final l in LibraryLayout.values)
                        DropdownMenuItem(value: l, child: Text(l.label)),
                    ],
                  ),
                ),
              ),
              header('Connections'),
              // The API identifies users by their account.
              if (!deviceOnly)
                ListTile(
                  leading: const Icon(Icons.api),
                  title: const Text('API & integrations'),
                  subtitle: const Text('Server address and API tokens'),
                  onTap: () => context.push(AppRoutes.integrations),
                ),
              ListTile(
                leading: const Icon(Icons.settings_ethernet),
                title: const Text('Connection settings'),
                subtitle: Text(
                  deviceOnly
                      ? 'Connect a Firebase project'
                      : 'Firebase project',
                ),
                onTap: () => context.push(AppRoutes.connection),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
