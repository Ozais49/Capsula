import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/display_preferences.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../bookmarks/library_navigation.dart';
import '../export/export_dialog.dart';

/// Account, library tools, integrations and preferences.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);
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
              ListTile(
                leading: const Icon(Icons.api),
                title: const Text('API & integrations'),
                subtitle: const Text('Server address and API tokens'),
                onTap: () => context.push(AppRoutes.integrations),
              ),
              ListTile(
                leading: const Icon(Icons.settings_ethernet),
                title: const Text('Connection settings'),
                subtitle: const Text('Firebase project'),
                onTap: () => context.push(AppRoutes.connection),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
