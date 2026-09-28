import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/password_policy.dart';
import '../theme/app_theme.dart';
import '../widgets/password_checklist.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  Set<String> _serverProblems = const {};

  String? get _email => AuthService.instance.user?.email;

  @override
  void initState() {
    super.initState();
    void refresh() => setState(() => _serverProblems = const {});
    _next.addListener(refresh);
    _confirm.addListener(refresh);
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 변경')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Text(
                '비밀번호를 바꾸면 다른 기기에서는 로그아웃됩니다.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.inkMuted),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _current,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '현재 비밀번호',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value ?? '').isEmpty ? '현재 비밀번호를 입력해 주세요.' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _next,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '새 비밀번호',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value ?? '';
                  if (!PasswordPolicy.isValid(text, _email)) {
                    return '아래 비밀번호 규칙을 모두 지켜 주세요.';
                  }
                  if (text == _current.text) {
                    return '지금과 다른 비밀번호로 정해 주세요.';
                  }
                  return null;
                },
              ),
              PasswordChecklist(
                password: _next.text,
                email: _email,
                serverProblems: _serverProblems,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: '새 비밀번호 확인',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == _next.text ? null : '새 비밀번호가 서로 다릅니다.',
              ),
              if (_confirm.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    _confirm.text == _next.text
                        ? '✓ 비밀번호가 같습니다.'
                        : '✕ 비밀번호가 서로 다릅니다.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _confirm.text == _next.text
                              ? AppColors.brandText
                              : AppColors.danger,
                        ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warningTint,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(_error!),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('변경하기'),
              ),
            ],
          ),
        ),
      ),
    );
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
      await AuthService.instance.changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호를 바꿨습니다.')),
      );
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          if (error.code == 'weak_password') {
            _serverProblems = error.passwordProblems;
            _error = '비밀번호가 규칙에 맞지 않습니다. ✕ 표시된 항목을 확인해 주세요.';
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
