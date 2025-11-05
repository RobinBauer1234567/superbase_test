// lib/screens/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLogin = true;
  bool _isLoading = false;

  String _email = '';
  String _password = '';
  String _username = '';

  void _trySubmit() {
    final isValid = _formKey.currentState?.validate() ?? false;
    FocusScope.of(context).unfocus();

    if (isValid) {
      _formKey.currentState?.save();
      setState(() => _isLoading = true);
      final authService = Provider.of<AuthService>(context, listen: false);

      if (_isLogin) {
        authService.signIn(context, email: _email, password: _password).whenComplete(() {
          if (mounted) setState(() => _isLoading = false);
        });
      } else {
        authService.signUp(context, email: _email, password: _password, username: _username).whenComplete(() {
          if (mounted) setState(() => _isLoading = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _isLogin ? 'Login' : 'Registrieren',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),
                if (!_isLogin)
                  TextFormField(
                    key: const ValueKey('username'),
                    validator: (value) {
                      if (value == null || value.isEmpty || value.length < 4) {
                        return 'Bitte gib mindestens 4 Zeichen ein.';
                      }
                      return null;
                    },
                    onSaved: (value) => _username = value!,
                    decoration: const InputDecoration(labelText: 'Benutzername'),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('email'),
                  validator: (value) {
                    if (value == null || !value.contains('@')) {
                      return 'Bitte gib eine gültige E-Mail-Adresse ein.';
                    }
                    return null;
                  },
                  onSaved: (value) => _email = value!,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-Mail'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('password'),
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return 'Das Passwort muss mindestens 6 Zeichen lang sein.';
                    }
                    return null;
                  },
                  onSaved: (value) => _password = value!,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Passwort'),
                ),
                const SizedBox(height: 20),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: _trySubmit,
                    child: Text(_isLogin ? 'Anmelden' : 'Registrieren'),
                  ),
                if (!_isLoading)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                      });
                    },
                    child: Text(_isLogin
                        ? 'Neuen Account erstellen'
                        : 'Ich habe bereits einen Account'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}