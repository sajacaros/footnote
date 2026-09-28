/// 비밀번호 규칙 — backend/app/password_policy.py 와 같은 규칙.
/// 서버가 최종 판단하고, 이 파일은 입력하는 동안 체크리스트를 보여 주는 용도다.
class PasswordRule {
  const PasswordRule(this.code, this.label, this._test);

  final String code;
  final String label;
  final bool Function(String password, String? email) _test;

  bool passes(String password, [String? email]) => _test(password, email);
}

class PasswordPolicy {
  static const minLength = 10;
  static const maxLength = 64;

  static const _sequences = [
    'abcdefghijklmnopqrstuvwxyz',
    '0123456789',
    'qwertyuiop',
    'asdfghjkl',
    'zxcvbnm',
  ];
  static const _commonWords = [
    'password',
    'passw0rd',
    'qwerty',
    'iloveyou',
    'admin',
    'welcome',
    'letmein',
    'footnote',
    'sunshine',
    'princess',
    'dragon',
    'monkey',
    'master',
    'login',
  ];

  static final rules = <PasswordRule>[
    PasswordRule(
      'length',
      '$minLength자 이상 $maxLength자 이하',
      (p, _) => p.length >= minLength && p.length <= maxLength,
    ),
    PasswordRule('letter', '영문 포함', (p, _) => RegExp('[A-Za-z]').hasMatch(p)),
    PasswordRule('digit', '숫자 포함', (p, _) => RegExp('[0-9]').hasMatch(p)),
    PasswordRule(
      'special',
      '특수문자 포함 (예: ! @ # \$ %)',
      (p, _) => RegExp(r'[^A-Za-z0-9\s]').hasMatch(p),
    ),
    PasswordRule('no_space', '공백 없음', (p, _) => !RegExp(r'\s').hasMatch(p)),
    PasswordRule(
      'no_repeat',
      '같은 문자 3번 이상 연속 금지 (예: aaa, 111)',
      (p, _) => !RegExp(r'(.)\1\1').hasMatch(p),
    ),
    PasswordRule(
      'no_sequence',
      '연속된 문자 4자리 이상 금지 (예: 1234, abcd, qwer)',
      (p, _) => !_hasSequence(p),
    ),
    PasswordRule('no_email', '이메일 아이디 포함 금지', (p, email) {
      final local = (email ?? '').split('@').first.toLowerCase();
      return local.length < 3 || !p.toLowerCase().contains(local);
    }),
    PasswordRule(
      'no_common',
      '쉽게 추측되는 단어 금지 (예: password, qwerty)',
      (p, _) => !_commonWords.any((word) => p.toLowerCase().contains(word)),
    ),
  ];

  static bool isValid(String password, [String? email]) =>
      rules.every((rule) => rule.passes(password, email));

  static bool _hasSequence(String password) {
    final lowered = password.toLowerCase();
    for (final sequence in _sequences) {
      for (final text in [sequence, sequence.split('').reversed.join()]) {
        for (var start = 0; start + 4 <= text.length; start += 1) {
          if (lowered.contains(text.substring(start, start + 4))) {
            return true;
          }
        }
      }
    }
    return false;
  }
}
