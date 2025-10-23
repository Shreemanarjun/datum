import 'package:example/bootstrap.dart';
import 'package:example/core/router/router.gr.dart';
import 'package:example/core/router/router_pod.dart';
import 'package:example/features/login/view/supabase_security_dialog.dart';
import 'package:example/shared/helper/global_helper.dart';
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

class _LoginPageState extends ConsumerState<LoginPage> with GlobalHelper {
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
      } on AuthException catch (e, _) {
        final message = switch (e) {
          AuthWeakPasswordException() => "Weak password",
          AuthUnknownException() => "Unknown error",
          AuthApiException() => "API error",
          AuthRetryableFetchException() => "Retryable fetch error",
          AuthSessionMissingException() => "Session missing",
          AuthPKCEGrantCodeExchangeError() => "PKCE grant code exchange error",
          _ => "Unknown error",
        };
        showErrorSnack(
          child: Text(message),
        );
      } catch (e) {
        showErrorSnack(
          child: Text(e.toString()),
        );
      }
    }
  }

  Future<void> showSecutiryDialog() async {
    await showShadDialog(
      context: context,
      builder: (context) {
        return SupabaseSecurityDialog();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        actionsPadding: EdgeInsets.only(
          right: 12,
        ),
        actions: [
          ShadIconButton(
            icon: Icon(
              Icons.key,
            ),
            onPressed: showSecutiryDialog,
          ),
        ],
      ),
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
