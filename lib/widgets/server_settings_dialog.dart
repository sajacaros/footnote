import 'package:flutter/material.dart';

import '../services/server_config.dart';
import '../theme/app_theme.dart';

/// 동기화 서버 주소를 입력받아 연결을 확인한 뒤 저장한다. 바뀌었으면 true.
Future<bool> showServerSettingsDialog(BuildContext context) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => const _ServerSettingsDialog(),
  );
  return changed ?? false;
}

class _ServerSettingsDialog extends StatefulWidget {
  const _ServerSettingsDialog();

  @override
  State<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<_ServerSettingsDialog> {
  late final TextEditingController _url = TextEditingController(
    text: ServerConfig.instance.baseUrl ?? '',
  );
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('동기화 서버'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '산책 기록을 보관할 서버 주소를 입력하세요. 서버 관리자에게 받은 주소를 쓰면 됩니다.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enabled: !_checking,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: '서버 주소',
              hintText: 'https://api.example.com',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _checking ? null : _save,
          child: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('연결 확인 후 저장'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final url = ServerConfig.normalize(_url.text);
    if (url == null) {
      setState(() => _error = '주소 형식을 확인해 주세요. 예: https://api.example.com');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final problem = await ServerConfig.check(url);
    if (!mounted) {
      return;
    }
    if (problem != null) {
      setState(() {
        _checking = false;
        _error = problem;
      });
      return;
    }
    await ServerConfig.instance.save(url);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }
}
