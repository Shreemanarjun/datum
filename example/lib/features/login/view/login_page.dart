import 'package:example/bootstrap.dart';
import 'package:example/core/router/router.gr.dart';
import 'package:example/core/router/router_pod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@RoutePage()
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<ShadFormState>();

  Future<void> _login() async {
    if (_formKey.currentState!.saveAndValidate()) {
      talker.debug("Login with Email and Password");
      try {
        final authResponse =
            await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        if (authResponse.user != null && authResponse.session != null) {
          talker.debug(authResponse.user);
          talker.debug(authResponse.session);
          ref.read(autorouterProvider).replaceAll([SimpleDatumRoute()]);
        }
      } catch (e) {
        talker.error("Login failed", e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ShadForm(
            key: _formKey, // Associate the form key
            child: ShadCard(
              width: 350,
              title: const Text('Login'),
              description: const Text(
                  'Enter your email below to login to your account.'),
              footer: ShadButton(
                onPressed: _login,
                width: double.infinity,
                child: const Text('Login'),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ShadInput(
                      controller: _emailController,
                      leading: const Text('Email'),
                      placeholder: const Text('name@example.com'),
                    ),
                    const SizedBox(height: 16),
                    ShadInput(
                      controller: _passwordController,
                      leading: const Text('Password'),
                      placeholder: const Text('Enter your password'),
                      obscureText: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
