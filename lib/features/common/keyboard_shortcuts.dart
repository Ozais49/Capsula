import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Single-key shortcuts (like `/` or `n`) that stay out of the way while
/// the user types in a text field.
class SingleKeyShortcuts extends StatelessWidget {
  const SingleKeyShortcuts({
    super.key,
    required this.bindings,
    required this.child,
  });

  final Map<LogicalKeyboardKey, VoidCallback> bindings;
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: {
      for (final key in bindings.keys) SingleActivator(key): _KeyIntent(key),
    },
    child: Actions(
      actions: {_KeyIntent: _KeyAction(bindings)},
      child: Focus(autofocus: true, child: child),
    ),
  );
}

class _KeyIntent extends Intent {
  const _KeyIntent(this.key);

  final LogicalKeyboardKey key;
}

class _KeyAction extends Action<_KeyIntent> {
  _KeyAction(this.bindings);

  final Map<LogicalKeyboardKey, VoidCallback> bindings;

  /// Disabled while typing, so the key reaches the text field instead.
  @override
  bool isEnabled(_KeyIntent intent, [BuildContext? context]) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return true;
    return focused.widget is! EditableText &&
        focused.findAncestorWidgetOfExactType<EditableText>() == null;
  }

  @override
  Object? invoke(_KeyIntent intent) {
    bindings[intent.key]?.call();
    return null;
  }
}
