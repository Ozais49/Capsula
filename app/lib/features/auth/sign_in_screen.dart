import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../connection/use_device_button.dart';
import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';

import 'package:capsula_core/domain/auth/auth_repository.dart';

enum _Mode { signIn, register }

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  AuthRepository get _auth => AppDependencies.of(context).authRepository;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      final email = _email.text.trim();
      final password = _password.text;
      if (_mode == _Mode.signIn) {
        await _auth.signInWithEmail(email: email, password: password);
      } else {
        await _auth.registerWithEmail(email: email, password: password);
      }
      // On success the router redirects away from this screen.
    });
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (_validateEmail(email) != null) {
      setState(() => _error = 'Enter your email above to reset your password.');
      return;
    }
    await _run(() async {
      await _auth.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email.')),
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleMode() => setState(() {
    _mode = _mode == _Mode.signIn ? _Mode.register : _Mode.signIn;
    _error = null;
  });

  static String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required.';
    if (_mode == _Mode.register && v.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSignIn = _mode == _Mode.signIn;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Capsula',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(
                        isSignIn
                            ? 'Sign in to your library'
                            : 'Create your account',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: Gap.xl),
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        validator: _validateEmail,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: Gap.md),
                      TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        obscureText: true,
                        autofillHints: [
                          isSignIn
                              ? AutofillHints.password
                              : AutofillHints.newPassword,
                        ],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: _validatePassword,
                        enabled: !_busy,
                      ),
                      if (_error case final error?) ...[
                        const SizedBox(height: Gap.md),
                        Text(
                          error,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: Gap.lg),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(isSignIn ? 'Sign in' : 'Create account'),
                      ),
                      const SizedBox(height: Gap.sm),
                      if (isSignIn)
                        TextButton(
                          onPressed: _busy ? null : _resetPassword,
                          child: const Text('Forgot password?'),
                        ),
                      TextButton(
                        onPressed: _busy ? null : _toggleMode,
                        child: Text(
                          isSignIn
                              ? "Don't have an account? Create one"
                              : 'Already have an account? Sign in',
                        ),
                      ),
                      const SizedBox(height: Gap.lg),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => context.push(AppRoutes.connection),
                        icon: const Icon(Icons.settings_ethernet, size: 18),
                        label: const Text('Connection settings'),
                      ),
                      const SizedBox(height: Gap.md),
                      UseDeviceButton(enabled: !_busy),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
