import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/presentation/theme.dart';
import '../../../core/presentation/widgets/brand_mark.dart';
import 'bloc/auth_bloc.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;

  /// Sandbox demo accounts, offered as a convenience for reviewers.
  static const _demoAccounts = [
    'superadmin@demo.test',
    'ops.doha@demo.test',
    'dispatch.doha@demo.test',
    'support.doha@demo.test',
    'viewer.doha@demo.test',
    'ops.rayyan@demo.test',
    'dispatch.wakrah@demo.test',
  ];

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    context.read<AuthBloc>().add(AuthSignInRequested(email: _email.text, password: _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: _buildForm(context)),
      ),
    );
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 900
            ? form
            : Row(
                children: [
                  const Expanded(child: _BrandPanel()),
                  Expanded(child: form),
                ],
              ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) => Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _form,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandMark(size: 30, suffix: 'Ops Console'),
                  const SizedBox(height: 12),
                  Text('Sign in to the operations dashboard.', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  if (state.notice != null && state.signInError == null) ...[
                    _Notice(text: state.notice!, color: OpsColors.of(context).info, icon: Icons.info_outline),
                    const SizedBox(height: 16),
                  ],
                  if (state.signInError != null) ...[
                    _Notice(text: state.signInError!, color: theme.colorScheme.error, icon: Icons.error_outline),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _email,
                    autofillHints: const [AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your email.' : null,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    focusNode: _passwordFocus,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                    validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: state.submitting ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: state.submitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Sandbox demo accounts', style: theme.textTheme.bodySmall),
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final email in _demoAccounts)
                            ActionChip(
                              label: Text(email.split('@').first),
                              // Fills the email only (no credentials live in the
                              // repo), then puts the cursor in the password field.
                              onPressed: () {
                                setState(() => _email.text = email);
                                _passwordFocus.requestFocus();
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Left half of the sign-in screen on wide windows: what the console is for.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const _features = [
    (Icons.speed, 'Live KPIs', 'Trips, revenue and driver supply, updated as they happen.'),
    (Icons.route_outlined, 'Trips and dispatch', 'Assign drivers, cancel and refund with clear conflict handling.'),
    (Icons.map_outlined, 'Live driver map', 'Every driver on the map, colour-coded by status.'),
    (Icons.sos, 'SOS alerts', 'Critical alerts reach you on whatever page you are on.'),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const onBrand = Colors.white;
    // Solid brand red, like the hero panel on badrgo.com.
    return Container(
      color: AppTheme.brandRed,
      padding: const EdgeInsets.all(48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(size: 32, suffix: 'Ops', color: onBrand),
          const Spacer(),
          Text(
            'City operations,\nlive.',
            style: text.displaySmall?.copyWith(color: onBrand, fontWeight: FontWeight.w700, height: 1.15),
          ),
          const SizedBox(height: 12),
          Text(
            'Doha · Al Rayyan · Al Wakrah',
            style: text.titleMedium?.copyWith(color: onBrand.withValues(alpha: 0.8), fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 40),
          for (final (icon, title, body) in _features)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: onBrand.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: onBrand, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: text.titleSmall?.copyWith(color: onBrand)),
                        const SizedBox(height: 2),
                        Text(body, style: text.bodyMedium?.copyWith(color: onBrand.withValues(alpha: 0.75))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
