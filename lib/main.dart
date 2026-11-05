import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'config/firebase_options.dart';
import 'providers/session_provider.dart';
import 'screens/connect_tracker_screen.dart';
import 'screens/login_screen.dart';
import 'screens/mfa_code_screen.dart';
import 'screens/tracker_screen.dart';
import 'services/auth_service.dart';
import 'services/email_service.dart';
import 'services/pending_queue_service.dart';
import 'services/screenshot_service.dart';
import 'services/session_service.dart';
import 'services/settings_service.dart';
import 'services/tray_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(480, 700),
      minimumSize: Size(440, 620),
      center: true,
      // Rebrand (v8): product name is Performance Gear. The company
      // stays Digital Bizz (logo assets unchanged).
      title: 'Performance Gear',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  // Intercept close so an open session is never killed silently.
  await windowManager.setPreventClose(true);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final pendingQueue = PendingQueueService();
  final sessionService = SessionService(pendingQueue: pendingQueue);
  final screenshotService = MethodChannelScreenshotService();
  // Real availability probe: true only if the native plugin answers.
  // (5-second timeout inside; a missing plugin means capture stays off
  // while Time In/Out and late alerts keep working.)
  await screenshotService.initialize();
  final provider = SessionProvider(
    authService: AuthService(),
    sessionService: sessionService,
    settingsService: SettingsService(),
    emailService: EmailService(),
    screenshotService: screenshotService,
  );

  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      child: const AppShell(),
    ),
  );
}

/// App shell: owns window close interception, tray wiring, and the
/// login/tracker switch. It contains no business logic itself.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WindowListener {
  final _tray = TrayService();
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
    // Firebase may restore a persisted user just after start; keep the
    // provider in sync with the auth stream (idempotent by uid).
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      context.read<SessionProvider>().syncAuthUser(user);
    });
  }

  Future<void> _boot() async {
    if (_booted || !mounted) return;
    _booted = true;
    final provider = context.read<SessionProvider>();
    _tray.onShowRequested = () async {
      await windowManager.show();
      await windowManager.focus();
    };
    _tray.onQuitRequested = () async {
      if (provider.hasOpenSession) await provider.timeOut();
      await windowManager.destroy();
    };
    await _tray.init();
    await provider.init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (!mounted) return;
    final provider = context.read<SessionProvider>();
    if (!provider.hasOpenSession) {
      await windowManager.destroy();
      return;
    }
    // Open session: never close silently. Offer tray / close-with-timeout.
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Session in progress'),
        content: const Text(
          'Your session is still open. What would you like to do?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('tray'),
            child: const Text('Keep in tray'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('timeout'),
            child: const Text('Time Out and close'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'tray':
        await windowManager.hide();
      case 'timeout':
        await provider.timeOut();
        await windowManager.destroy();
      default:
        // Cancel: window stays open (preventClose is on).
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Performance Gear',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: Consumer<SessionProvider>(
        builder: (context, provider, _) {
          // A pending TOTP challenge outranks the login form: the user
          // has already passed email/password and must enter the code
          // before the timer screen. Login and tracker screens untouched.
          if (provider.mfaRequired) return const MfaCodeScreen();
          if (provider.user == null) return const LoginScreen();
          // v11 link gate: after sign-in (and MFA) the tracker must be
          // linked with the staff member's secret token before the
          // timer screen — Time In stays unreachable until linked.
          if (provider.linkRequired) return const ConnectTrackerScreen();
          return const TrackerScreen();
        },
      ),
    );
  }
}
