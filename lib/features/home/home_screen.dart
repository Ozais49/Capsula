import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';

/// Placeholder until the library screens are built in later phases.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);
    final user = deps.authSession.user;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capsula'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: deps.authRepository.signOut,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: Gap.md),
              Text(
                'Your library will appear here.',
                style: theme.textTheme.titleMedium,
              ),
              if (user?.email case final email?) ...[
                const SizedBox(height: Gap.sm),
                Text('Signed in as $email', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
