import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart' show syncService;
import 'main_screen.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _loading = false;
  String? _error;

  Future<void> _signInGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _loading = false);
        return;
      }
      final auth = await googleUser.authentication;
      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: auth.idToken!,
        accessToken: auth.accessToken,
      );
      _proceed();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _signInApple() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rawNonce = _generateNonce();
      final nonce = _sha256(rawNonce);
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: credential.identityToken!,
        nonce: rawNonce,
      );
      _proceed();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _continueOffline() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInAnonymously();
    } catch (_) {}
    _proceed();
  }

  void _proceed() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      syncService.setUser(userId).catchError((_) {});
    }
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  String _generateNonce([int length = 32]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)])
        .join();
  }

  String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  bool get _showApple =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const Icon(Icons.sports_golf, size: 72, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'Ugly Slice',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to sync your rounds across devices.',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              if (_loading)
                const CircularProgressIndicator()
              else ...[
                _GoogleButton(onPressed: _signInGoogle),
                if (_showApple) ...[
                  const SizedBox(height: 12),
                  _AppleButton(onPressed: _signInApple),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
              const Spacer(),
              TextButton(
                onPressed: _loading ? null : _continueOffline,
                child: const Text('Continue without signing in'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _GoogleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey[700]!),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Coloured "G" matching Google brand
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                children: [
                  TextSpan(text: 'G', style: TextStyle(color: Color(0xFF4285F4))),
                  TextSpan(text: 'o', style: TextStyle(color: Color(0xFFEA4335))),
                  TextSpan(text: 'o', style: TextStyle(color: Color(0xFFFBBC05))),
                  TextSpan(text: 'g', style: TextStyle(color: Color(0xFF4285F4))),
                  TextSpan(text: 'l', style: TextStyle(color: Color(0xFF34A853))),
                  TextSpan(text: 'e', style: TextStyle(color: Color(0xFFEA4335))),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Text('Continue with Google'),
          ],
        ),
      ),
    );
  }
}

class _AppleButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AppleButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.apple, color: Colors.black),
        label: const Text(
          'Continue with Apple',
          style: TextStyle(color: Colors.black),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
