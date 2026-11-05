import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/status_banner.dart';

/// Workstatus-style split login: brand panel + sign-in form.
/// This screen only collects input and forwards it to [SessionProvider];
/// it owns no auth logic.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _showPassword = false;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    // Compact login window (single-column layout below): the tracker
    // screen shrinks it further after login (see TrackerScreen).
    // Best-effort; a failure just leaves the current window size.
    Future.microtask(() async {
      try {
        await windowManager.setMinimumSize(const Size(440, 620));
        await windowManager.setSize(const Size(480, 700));
        await windowManager.center();
      } catch (_) {
        // Non-fatal: login still works at the current window size.
      }
    });
    // Prefill the remembered email (address only — never a password).
    // Provider is captured synchronously; only the await happens later.
    final provider = context.read<SessionProvider>();
    Future.microtask(() async {
      final saved = await provider.rememberedEmail();
      if (saved != null && mounted) {
        _emailController.text = saved;
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final provider = context.read<SessionProvider>();
    await provider.signIn(
      email: _emailController.text.trim(),
      password: _passController.text,
      rememberMe: _rememberMe,
    );
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    final provider = context.read<SessionProvider>();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email first.')),
      );
      return;
    }
    final ok = await provider.resetPassword(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'A password reset link has been sent to your email ✓'
              : 'The reset link could not be sent.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SessionProvider>();
    final form = _buildForm(provider);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Compact single-column login for the small window.
          if (constraints.maxWidth < 700) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/digital-bizz-mark.png',
                      height: 72,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.diamond,
                        size: 64,
                        color: AppTheme.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'DIGITAL BIZZ',
                      style: TextStyle(
                        color: AppTheme.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const Center(
                    child: Text(
                      'Your Digital Partner',
                      style: TextStyle(
                        color: AppTheme.redDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  form,
                ],
              ),
            );
          }
          return Row(
            children: [
              // Brand panel (light theme: white panel, red diamond mark +
              // dark-slate wordmark rendered as text. NOTE: the full lockup
              // image has a white wordmark made for dark backgrounds, so it
              // cannot be used on white — the mark + text carry the brand
              // here instead. The lockup asset is retained for dark surfaces
              // only, e.g. the app icon.)
              Expanded(
                flex: 5,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/digital-bizz-mark.png',
                        height: 110,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.diamond,
                          size: 96,
                          color: AppTheme.red,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'DIGITAL BIZZ',
                        style: TextStyle(
                          color: AppTheme.ink,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Text(
                        'Your Digital Partner',
                        style: TextStyle(
                          color: AppTheme.redDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Welcome to\nthe team',
                        style: TextStyle(
                          color: AppTheme.ink,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(width: 48, height: 3, color: AppTheme.red),
                      const SizedBox(height: 16),
                      const Text(
                        'Staff time tracking — Time In, Time Out, screenshots '
                        'and late alerts, all in one place.',
                        style: TextStyle(color: AppTheme.secondary, fontSize: 15),
                      ),
                      const SizedBox(height: 24),
                      const _Bullet('Time In / Time Out with live timer'),
                      const _Bullet('Automatic screenshots during sessions'),
                      const _Bullet('Late-start alert straight to admin'),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 6,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 64),
                    child: form,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The sign-in form, shared by the wide split layout and the compact layout.
  Widget _buildForm(SessionProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sign in to Digital Bizz',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your credentials to access your account.',
          style: TextStyle(color: AppTheme.muted),
        ),
        const SizedBox(height: 24),
        if (provider.error != null) ...[
          StatusBanner(
            message: provider.error!,
            kind: BannerKind.error,
          ),
          const SizedBox(height: 16),
        ],
        const Text('Email*',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'Enter Your Email',
          ),
          onSubmitted: (_) => _login(),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Password*',
                style: TextStyle(fontWeight: FontWeight.w600)),
            TextButton(
              onPressed: _forgotPassword,
              child: const Text('Forgot password?'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _passController,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            hintText: 'Enter Password',
            suffixIcon: TextButton(
              onPressed: () => setState(
                () => _showPassword = !_showPassword,
              ),
              child: Text(_showPassword ? 'Hide' : 'Show'),
            ),
          ),
          onSubmitted: (_) => _login(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Checkbox(
              value: _rememberMe,
              onChanged: (v) => setState(
                () => _rememberMe = v ?? true,
              ),
            ),
            const Text('Remember me'),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: provider.busy ? null : _login,
            child: provider.busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Login'),
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text.rich(
            TextSpan(
              text: "Don't have an account? ",
              children: [
                TextSpan(
                  text: 'Contact the admin',
                  style: TextStyle(
                    color: AppTheme.redDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '✓  $text',
        style: const TextStyle(color: AppTheme.secondary),
      ),
    );
  }
}
