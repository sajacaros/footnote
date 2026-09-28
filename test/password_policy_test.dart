import 'package:flutter_test/flutter_test.dart';
import 'package:footnote_walk/services/password_policy.dart';

/// backend/tests/test_password_policy.py 와 같은 사례. 두 구현이 어긋나지 않게 한다.
void main() {
  const cases = {
    'Walk-2026!trail': <String>[],
    'Ab1!': ['length'],
    'walk-trail!!x': ['digit'],
    'Walk20261trail': ['special'],
    '2026-0913!!85': ['letter'],
    'Walk 2026!trail': ['no_space'],
    'Waaalk-2026!tr': ['no_repeat'],
    'Walk-1234!trail': ['no_sequence'],
    'Walk-9876!trail': ['no_sequence'],
    'Qwer-2026!trail': ['no_sequence'],
    'Password-2026!': ['no_common'],
  };

  cases.forEach((password, expected) {
    test('"$password" fails $expected', () {
      final failed = PasswordPolicy.rules
          .where((rule) => !rule.passes(password))
          .map((rule) => rule.code)
          .toList();
      expect(failed, expected);
    });
  });

  test('email local part', () {
    final rule = PasswordPolicy.rules.firstWhere((r) => r.code == 'no_email');
    expect(rule.passes('walker99-Trail!', 'walker99@example.com'), isFalse);
    expect(rule.passes('Walk-2026!trail', 'ab@example.com'), isTrue);
  });
}
