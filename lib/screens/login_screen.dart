import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/password_policy.dart';
import '../services/server_config.dart';
import '../theme/app_theme.dart';
import '../widgets/password_checklist.dart';
import '../widgets/server_settings_dialog.dart';

/// 로그인과 가입 신청을 한 화면에서 전환한다.
/// 가입은 관리자 승인이 필요해서, 신청이 끝나면 안내만 보여 주고 로그인으로 돌아온다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService.instance;
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  bool _signupMode = false;
  bool _busy = false;
  String? _error;
  Set<String> _serverProblems = const {};

  /// 가입 신청 완료, 승인 대기 같은 안내(오류가 아닌 알림).
  String? _notice;

  @override
  void initState() {
    super.initState();
    _notice = _auth.signOutReason;
    // 가입 모드에서는 입력할 때마다 체크리스트를 다시 그린다.
    void refresh() {
      if (_signupMode) {
        setState(() => _serverProblems = const {});
      }
    }

    _password.addListener(refresh);
    _email.addListener(refresh);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('풋노트 산책',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 6),
                    Text(
                      _signupMode
                          ? '가입을 신청하면 관리자가 승인한 뒤 로그인할 수 있어요.'
                          : '산책 기록을 서버에 안전하게 보관합니다.',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 20),
                    _ServerRow(onChange: _changeServer),
                    const SizedBox(height: 16),
                    if (_notice != null) ...[
                      _Banner(text: _notice!, color: AppColors.brandTint),
                      const SizedBox(height: 16),
                    ],
                    if (_signupMode) ...[
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '이름',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? '이름을 입력해 주세요.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '이메일',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value ?? '').contains('@')
                          ? null
                          : '이메일 주소를 확인해 주세요.',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: [
                        _signupMode
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: '비밀번호',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final text = value ?? '';
                        if (text.isEmpty) {
                          return '비밀번호를 입력해 주세요.';
                        }
                        if (_signupMode &&
                            !PasswordPolicy.isValid(text, _email.text)) {
                          return '아래 비밀번호 규칙을 모두 지켜 주세요.';
                        }
                        return null;
                      },
                    ),
                    if (_signupMode)
                      PasswordChecklist(
                        password: _password.text,
                        email: _email.text.contains('@') ? _email.text : null,
                        serverProblems: _serverProblems,
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _Banner(text: _error!, color: AppColors.warningTint),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52)),
                      onPressed: _busy || ServerConfig.instance.baseUrl == null
                          ? null
                          : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_signupMode ? '가입 신청' : '로그인'),
                    ),
                    const SizedBox(height: 8),
                    if (!_signupMode)
                      TextButton(
                        onPressed: _showForgotPassword,
                        child: const Text('비밀번호를 잊었어요'),
                      ),
                    TextButton(
                      onPressed: _busy ? null : _toggleMode,
                      child: Text(
                        _signupMode ? '이미 계정이 있어요. 로그인' : '계정이 없어요. 가입 신청',
                      ),
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

  /// 메일 발송이 없어서, 관리자가 만든 재설정 링크를 받는 방법을 안내한다.
  Future<void> _showForgotPassword() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('비밀번호를 잊으셨나요?'),
        content: const Text(
          '관리자에게 비밀번호 재설정 링크를 요청하세요. '
          '받은 링크를 열어 새 비밀번호를 정한 뒤 이 화면에서 로그인하면 됩니다.\n\n'
          '링크는 30분 동안 한 번만 쓸 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeServer() async {
    final changed = await showServerSettingsDialog(context);
    if (changed && mounted) {
      setState(() {
        _error = null;
        _notice = '서버를 ${ServerConfig.instance.displayName}(으)로 설정했습니다.';
      });
    }
  }

  void _toggleMode() {
    setState(() {
      _signupMode = !_signupMode;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signupMode) {
        final message = await _auth.signup(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _signupMode = false;
          _notice = message;
          _password.clear();
        });
      } else {
        // 성공하면 AuthGate가 홈 화면으로 바꾼다.
        await _auth.login(_email.text, _password.text);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          if (error.code == 'weak_password') {
            _serverProblems = error.passwordProblems;
            _error = '비밀번호가 규칙에 맞지 않습니다. ✕ 표시된 항목을 확인해 주세요.';
          } else if (error.code == 'pending_approval') {
            _notice = error.message;
          } else {
            _error = error.message;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(text),
    );
  }
}

/// 지금 연결할 동기화 서버와 [변경] 버튼. 서버가 없으면 먼저 설정하라고 알린다.
class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.onChange});

  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final name = ServerConfig.instance.displayName;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: name == null ? AppColors.warningTint : AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.dns_outlined, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name == null ? '동기화 서버를 먼저 설정해 주세요.' : '서버 $name',
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: name == null ? AppColors.ink : AppColors.inkMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: onChange,
            child: Text(name == null ? '설정' : '변경'),
          ),
        ],
      ),
    );
  }
}
