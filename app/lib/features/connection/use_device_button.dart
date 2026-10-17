import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';

/// Offers to use Capsula without Firebase or an account, keeping the
/// library on this device only. Hidden in builds that can't do that.
class UseDeviceButton extends StatefulWidget {
  const UseDeviceButton({super.key, this.enabled = true});

  final bool enabled;

  @override
  State<UseDeviceButton> createState() => _UseDeviceButtonState();
}

class _UseDeviceButtonState extends State<UseDeviceButton> {
  bool _busy = false;

  Future<void> _use() async {
    final backend = AppDependencies.of(context).backend;
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    await backend.useDevice();
    if (backend.deviceOnly) {
      router.go(AppRoutes.home);
    } else if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(backend.error ?? 'Could not open the library')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = AppDependencies.of(context).backend;
    if (!backend.canUseDevice) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: widget.enabled && !_busy ? _use : null,
          icon: const Icon(Icons.phone_android),
          label: const Text('Use without an account'),
        ),
        const SizedBox(height: Gap.xs),
        Text(
          'Keeps your library on this device only. No sign-in, no sync. '
          'You can connect an account later in Settings.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
