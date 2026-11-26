import 'package:example/bootstrap.dart';
import 'package:example/features/auth/presentation/view/supabase_security_dialog.dart';
import 'package:example/shared/helper/global_helper.dart';
import 'package:flutter/material.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with GlobalHelper {
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
        // Nothing else to do: the router and the sync session both follow the
        // Supabase auth state.
        talker.debug('Signed in: ${authResponse.user?.id}');
      } on AuthException catch (e, s) {
        talker.error(e, s);
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
          padding: EdgeInsets.all(
            ResponsiveValue<double>(
              context,
              conditionalValues: [
                const Condition.equals(name: MOBILE, value: 16),
                const Condition.equals(name: TABLET, value: 24),
                const Condition.equals(name: DESKTOP, value: 32),
                const Condition.equals(name: '4K', value: 48),
              ],
              defaultValue: 16,
            ).value,
          ),
          child: ShadForm(
            key: _formKey, // Associate the form key
            child: ShadCard(
              width: ResponsiveValue<double>(
                context,
                conditionalValues: [
                  const Condition.equals(name: MOBILE, value: double.infinity),
                  const Condition.equals(name: TABLET, value: 400),
                  const Condition.equals(name: DESKTOP, value: 450),
                  const Condition.equals(name: '4K', value: 500),
                ],
                defaultValue: 350,
              ).value,
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
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 16),
                    ShadInput(
                      controller: _passwordController,
                      leading: const Text('Password'),
                      placeholder: const Text('Enter your password'),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _login(),
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
