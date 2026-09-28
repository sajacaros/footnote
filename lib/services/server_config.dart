import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'walk_repository.dart';

/// 동기화 서버 주소. 앱 안에 저장하고, 없으면 빌드 기본값([defaultServerUrl])을 쓴다.
class ServerConfig extends ChangeNotifier {
  ServerConfig._();

  static final ServerConfig instance = ServerConfig._();

  static const _key = 'server.base_url';

  String? _baseUrl;

  /// 설정된 서버 주소(끝의 / 없음). 아직 정하지 않았으면 null.
  String? get baseUrl => _baseUrl;

  /// 화면에 보여 줄 짧은 이름(예: api.example.com:8443).
  String? get displayName {
    final url = _baseUrl;
    if (url == null) {
      return null;
    }
    final uri = Uri.parse(url);
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  Future<void> load() async {
    final saved = await WalkRepository.instance.readMeta(_key);
    _baseUrl = normalize(saved ?? '') ?? normalize(defaultServerUrl);
    notifyListeners();
  }

  Future<void> save(String url) async {
    _baseUrl = url;
    await WalkRepository.instance.writeMeta(_key, url);
    notifyListeners();
  }

  /// 입력을 `https://host[:port][/path]` 모양으로 맞춘다. 올바른 주소가 아니면 null.
  static String? normalize(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      return null;
    }
    if (!text.contains('://')) {
      text = 'https://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri.toString().replaceFirst(RegExp(r'/+$'), '');
  }

  /// 풋노트 서버가 맞는지 `/healthz`로 확인한다. 문제가 있으면 안내 문구를 돌려준다.
  static Future<String?> check(String url, {http.Client? client}) async {
    final http.Response response;
    try {
      response = await (client ?? http.Client())
          .get(Uri.parse('$url/healthz'))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return '서버에 연결할 수 없습니다. 주소와 네트워크를 확인해 주세요.';
    }
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && body is Map && body['status'] == 'ok') {
        return null;
      }
    } catch (_) {}
    return '풋노트 동기화 서버가 아닌 것 같습니다. (${response.statusCode})';
  }
}
