/// The reset password screen.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'ui.dart';

/// Password reset in two steps: ask for an emailed 6-digit code, then send the
/// code with a new password. The API answers the first step the same way
/// whether or not the address has an account.
class ForgotScreen extends StatefulWidget {
  const ForgotScreen({super.key, required this.state, this.email = ''});

  final AppState state;
  final String email;

  @override
  State<ForgotScreen> createState() => _ForgotScreenState();
}

class _ForgotScreenState extends State<ForgotScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;
  String? _info;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Runs one call, shows its message or error, and returns the message (null on error).
  Future<String?> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final message = await action();
      if (mounted) setState(() => _info = message);
      return message;
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // POST /api/users/forgot
  Future<void> _requestCode() async {
    final message = await _run(() => widget.state.api.forgotPassword(_email.text.trim()));
    if (message != null && mounted) setState(() => _codeSent = true);
  }

  // POST /api/users/reset
  Future<void> _reset() async {
    final message = await _run(
      () =>
          widget.state.api.resetPassword(email: _email.text.trim(), code: _code.text.trim(), password: _password.text),
    );
    if (message == null || !mounted) return;
    Navigator.of(context).pop();
    showSnack(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Centered(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Step 1: we email a 6-digit code to the address you registered with.'),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(onPressed: _busy ? null : _requestCode, child: const Text('Email me a code')),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 24),
              const Text('Step 2: enter the code and choose a new password.'),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                decoration: const InputDecoration(labelText: '6-digit code', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _reset(),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(onPressed: _busy ? null : _reset, child: const Text('Set new password')),
              ),
            ],
            if (_info != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_info!)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
