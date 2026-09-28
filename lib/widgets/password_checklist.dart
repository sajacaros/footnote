import 'package:flutter/material.dart';

import '../services/password_policy.dart';
import '../theme/app_theme.dart';

/// 비밀번호 입력칸 아래에 규칙별 통과 여부를 보여 준다.
/// [serverProblems]는 서버가 거부한 규칙 코드로, 화면에서 판단할 수 없는 규칙도 ✕로 표시한다.
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({
    required this.password,
    this.email,
    this.serverProblems = const {},
    super.key,
  });

  final String password;
  final String? email;
  final Set<String> serverProblems;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final rule in PasswordPolicy.rules)
            if (rule.code != 'no_email' || (email ?? '').isNotEmpty)
              _RuleRow(
                label: rule.label,
                state: password.isEmpty && !serverProblems.contains(rule.code)
                    ? _RuleState.idle
                    : rule.passes(password, email) &&
                            !serverProblems.contains(rule.code)
                        ? _RuleState.ok
                        : _RuleState.bad,
                style: style,
              ),
        ],
      ),
    );
  }
}

enum _RuleState { idle, ok, bad }

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.label, required this.state, this.style});

  final String label;
  final _RuleState state;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (state) {
      _RuleState.idle => (Icons.circle, AppColors.inkSubtle),
      _RuleState.ok => (Icons.check_rounded, AppColors.brandText),
      _RuleState.bad => (Icons.close_rounded, AppColors.danger),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Icon(
              icon,
              size: state == _RuleState.idle ? 5 : 15,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(label, style: style?.copyWith(color: color))),
        ],
      ),
    );
  }
}
