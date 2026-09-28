import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'server_config.dart';

/// 서버가 돌려준 오류. [code]는 승인 대기처럼 앱이 화면을 나눠야 하는 경우에만 온다.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.code, this.body});

  final int statusCode;
  final String message;
  final String? code;
  final Object? body;

  /// 서버에 닿지 못한 경우(오프라인 등).
  bool get isNetwork => statusCode == 0;

  /// 비밀번호 규칙 위반이면 어긴 규칙 코드 목록.
  Set<String> get passwordProblems {
    final detail = body;
    if (code != 'weak_password' || detail is! Map) {
      return const {};
    }
    final problems = detail['problems'];
    if (problems is! List) {
      return const {};
    }
    return {
      for (final problem in problems)
        if (problem is Map && problem['code'] is String)
          problem['code'] as String,
    };
  }

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';

  static ApiException fromResponse(http.Response response) {
    Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {}
    final detail = body is Map ? body['detail'] : null;
    if (detail is Map) {
      return ApiException(
        response.statusCode,
        (detail['message'] as String?) ?? '요청을 처리하지 못했습니다.',
        code: detail['code'] as String?,
        body: detail,
      );
    }
    if (detail is String) {
      return ApiException(response.statusCode, detail, body: body);
    }
    if (detail is List) {
      return ApiException(response.statusCode, '입력값을 확인해 주세요.', body: body);
    }
    return ApiException(
        response.statusCode, '서버 오류가 발생했습니다. (${response.statusCode})');
  }
}

/// JSON API 호출. 인증 헤더는 호출하는 쪽([AuthService])이 붙인다.
class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _fixedBaseUrl = baseUrl;

  final http.Client _client;
  final String? _fixedBaseUrl;

  static const _timeout = Duration(seconds: 30);

  Future<Object?> send(
    String method,
    String path, {
    Object? json,
    Map<String, String>? headers,
    bool gzipBody = false,
  }) async {
    final baseUrl = _fixedBaseUrl ?? ServerConfig.instance.baseUrl;
    if (baseUrl == null) {
      throw const ApiException(0, '동기화 서버 주소를 먼저 설정해 주세요.', code: 'no_server');
    }
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers.addAll(headers ?? const {});
    if (json != null) {
      final bytes = utf8.encode(jsonEncode(json));
      request.headers['Content-Type'] = 'application/json';
      if (gzipBody) {
        request.headers['Content-Encoding'] = 'gzip';
        request.bodyBytes = gzip.encode(bytes);
      } else {
        request.bodyBytes = bytes;
      }
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      ).timeout(_timeout);
    } on Exception {
      throw const ApiException(0, '서버에 연결할 수 없습니다. 네트워크를 확인해 주세요.');
    }

    if (response.statusCode >= 400) {
      throw ApiException.fromResponse(response);
    }
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  /// presigned URL로 스토리지에 직접 올린다. 서명에 들어간 헤더를 그대로 보내야 한다.
  Future<void> putBytes(
    String url,
    List<int> bytes,
    Map<String, String> headers,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .put(Uri.parse(url), headers: headers, body: bytes)
          .timeout(const Duration(minutes: 2));
    } on Exception {
      throw const ApiException(0, '사진을 올리지 못했습니다. 네트워크를 확인해 주세요.');
    }
    if (response.statusCode >= 300) {
      throw ApiException(
          response.statusCode, '사진 업로드가 거부됐습니다. (${response.statusCode})');
    }
  }
}
