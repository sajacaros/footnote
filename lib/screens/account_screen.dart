import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/server_config.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_surfaces.dart';
import 'change_password_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final AuthService _auth = AuthService.instance;
  final SyncService _sync = SyncService.instance;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_refresh);
    _sync.refreshStatus();
  }

  @override
  void dispose() {
    _sync.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.user;
    final textTheme = Theme.of(context).textTheme;
    final last = _sync.lastSyncedAt;

    return Scaffold(
      appBar: AppBar(title: const Text('계정')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            if (user != null)
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName, style: textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 6),
                    // 서버를 바꾸려면 로그아웃한 뒤 로그인 화면에서 바꾼다.
                    Text(
                      '동기화 서버 ${ServerConfig.instance.displayName ?? '-'}',
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.inkSubtle),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('서버 동기화', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    _sync.isRunning
                        ? '동기화하는 중…'
                        : _sync.pendingCount == 0
                            ? '모든 기록이 서버에 저장돼 있습니다.'
                            : '서버로 보낼 기록 ${_sync.pendingCount}건이 남아 있습니다.',
                  ),
                  const SizedBox(height: 2),
                  Text(
                    last == null
                        ? '아직 동기화한 적이 없습니다.'
                        : '마지막 동기화 ${DateFormat('M월 d일 HH:mm').format(last)}',
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppColors.inkMuted),
                  ),
                  if (_sync.error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warningTint,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(_sync.error!),
                    ),
                  ],
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _sync.isRunning ? null : _sync.sync,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('지금 동기화'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const ChangePasswordScreen(),
                ),
              ),
              icon: const Icon(Icons.lock_outline_rounded),
              label: const Text('비밀번호 변경'),
            ),
            const SizedBox(height: 24),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _confirmLogout,
              child: const Text('로그아웃'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final pending = _sync.pendingCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃할까요?'),
        content: Text(
          pending > 0
              ? '아직 서버로 보내지 않은 기록이 $pending건 있습니다. 기록은 이 기기에 남고, 다시 로그인하면 이어서 보냅니다.'
              : '기록은 이 기기에 그대로 남습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      await _auth.logout();
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }
}
