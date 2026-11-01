/// The log in and register screen.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'forgot_screen.dart';
import 'ui.dart';

/// Log in or register. Users belong to your key, so you can register freely
/// (a key allows 25 users). Passwords need 8+ characters.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.state, this.startAsRegister = false});

  final AppState state;
  final bool startAsRegister;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late bool _register = widget.startAsRegister;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _demo() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.loginDemo();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = describeLoginError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = widget.state.api;
      // POST /api/users/register  or  POST /api/users/login
      final result = _register
          ? await api.register(name: _name.text.trim(), email: _email.text.trim(), password: _password.text)
          : await api.login(email: _email.text.trim(), password: _password.text);
      if (result.token == null) {
        if (mounted) setState(() => _error = result.message);
        return;
      }
      widget.state.loggedInAs(result.name.isEmpty ? 'you' : result.name);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final full = _register && e is ApiException && isUserLimit(e);
      setState(() => _error = full ? demoFullMessage : (_register ? describeError(e) : describeLoginError(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_register ? 'Register' : 'Log in')),
      body: Centered(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            FilledButton(onPressed: _busy ? null : _demo, child: const Text('Try the demo account')),
            const Divider(height: 32),
            const DemoNotice(key: Key('demo-notice')),
            const SizedBox(height: 16),
            if (_register) ...[
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _register ? 'At least 8 characters' : null,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(onPressed: _busy ? null : _submit, child: Text(_register ? 'Register' : 'Log in')),
                TextButton(
                  onPressed: () => setState(() => _register = !_register),
                  child: Text(_register ? 'I already have an account' : 'Create an account'),
                ),
                if (!_register)
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ForgotScreen(state: widget.state, email: _email.text.trim()),
                      ),
                    ),
                    child: const Text('Forgot password?'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
