import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/basemap.dart';
import 'services/server_config.dart';
import 'services/sync_service.dart';
import 'services/walk_reminder_service.dart';
import 'theme/app_theme.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await WalkReminderService.instance.initialize();
  } catch (error) {
    // 알림 설정이 실패해도 기록 기능은 쓸 수 있어야 한다.
    debugPrint('Walk reminder init failed: $error');
  }
  await ServerConfig.instance.load();
  await AuthService.instance.restore();
  // 기다리지 않는다. 준비되기 전에는 지도가 대체 타일로 그려진다.
  Basemap.instance.preload();
  runApp(const FootnoteWalkApp());
}

class FootnoteWalkApp extends StatelessWidget {
  const FootnoteWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: '풋노트 산책',
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}

/// 로그인 전에는 로그인 화면, 로그인 후에는 홈. 앱이 다시 앞으로 오면 동기화한다.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final AuthService _auth = AuthService.instance;
  AuthState? _previous;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SyncService.instance.sync();
    }
  }

  void _onAuthChanged() {
    final state = _auth.state;
    if (state == _previous) {
      return;
    }
    if (state == AuthState.signedIn) {
      SyncService.instance.sync();
    } else if (state == AuthState.signedOut &&
        _previous == AuthState.signedIn) {
      // 세부 화면 위에서 로그아웃돼도(승인 취소 등) 로그인 화면이 바로 보이게 한다.
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    _previous = state;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_auth.state) {
      AuthState.loading =>
        const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthState.signedOut => const LoginScreen(),
      AuthState.signedIn => const HomeScreen(),
    };
  }
}
