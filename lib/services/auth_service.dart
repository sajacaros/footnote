import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'server_config.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isAdmin,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String,
      isAdmin: json['is_admin'] as bool? ?? false,
    );
  }

  final String id;
  final String email;
  final String displayName;
  final bool isAdmin;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'is_admin': isAdmin,
      };
}

enum AuthState { loading, signedOut, signedIn }

/// 로그인 상태와 토큰을 관리한다.
///
/// 토큰은 기기 보안 저장소에 두고, 앱을 다시 열면 네트워크 없이도 로그인 상태로 시작한다.
/// 액세스 토큰이 만료되면 refresh 토큰으로 한 번 갱신하고, 그것도 실패하면 로그아웃한다.
class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const _accessKey = 'auth.access';
  static const _refreshKey = 'auth.refresh';
  static const _userKey = 'auth.user';
  static const _serverKey = 'auth.server';

  final ApiClient api = ApiClient();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AuthState _state = AuthState.loading;
  AuthUser? _user;
  String? _access;
  String? _refresh;
  Future<bool>? _refreshing;

  /// 강제로 로그아웃된 이유(승인 취소 등). 로그인 화면에서 한 번 보여 준다.
  String? signOutReason;

  AuthState get state => _state;
  AuthUser? get user => _user;

  Future<void> restore() async {
    try {
      _access = await _storage.read(key: _accessKey);
      _refresh = await _storage.read(key: _refreshKey);
      final userJson = await _storage.read(key: _userKey);
      final server = await _storage.read(key: _serverKey);
      // 서버 기록이 없는 토큰은 서버 설정 기능 전에 받은 것이라 지금 서버의 것으로 본다.
      if (server != null && server != ServerConfig.instance.baseUrl) {
        // 다른 서버에서 받은 토큰이다.
        await _clear();
        _state = AuthState.signedOut;
      } else if (_refresh != null && userJson != null) {
        _user = AuthUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
        _state = AuthState.signedIn;
      } else {
        _state = AuthState.signedOut;
      }
    } catch (_) {
      _state = AuthState.signedOut;
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final body = await api.send(
      'POST',
      '/v1/auth/login',
      json: {'email': email.trim(), 'password': password},
    );
    await _saveTokens(body as Map<String, dynamic>);
    signOutReason = null;
    _state = AuthState.signedIn;
    notifyListeners();
  }

  /// 가입 신청. 관리자가 승인해야 로그인할 수 있으므로 안내 문구만 돌려준다.
  Future<String> signup({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final body = await api.send(
      'POST',
      '/v1/auth/signup',
      json: {
        'email': email.trim(),
        'password': password,
        'display_name': displayName.trim(),
      },
    );
    return (body as Map<String, dynamic>)['message'] as String;
  }

  /// 비밀번호를 바꾼다. 서버가 다른 기기의 로그인을 모두 끊고 이 기기에는 새 토큰을 준다.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final body = await authorized(
      'POST',
      '/v1/me/password',
      json: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
    await _saveTokens(body as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> logout({String? reason}) async {
    final refresh = _refresh;
    await _clear();
    signOutReason = reason;
    _state = AuthState.signedOut;
    notifyListeners();
    if (refresh != null) {
      try {
        await api.send(
          'POST',
          '/v1/auth/logout',
          json: {'refresh_token': refresh},
        );
      } catch (_) {}
    }
  }

  /// 인증이 필요한 API 호출. 401이면 토큰을 갱신하고 한 번만 다시 시도한다.
  Future<Object?> authorized(
    String method,
    String path, {
    Object? json,
    bool gzipBody = false,
  }) async {
    try {
      return await _authorizedOnce(method, path,
          json: json, gzipBody: gzipBody);
    } on ApiException catch (error) {
      if (error.statusCode == 401 && await _refreshTokens()) {
        return _authorizedOnce(method, path, json: json, gzipBody: gzipBody);
      }
      await _handleAccountError(error);
      rethrow;
    }
  }

  Future<Object?> _authorizedOnce(
    String method,
    String path, {
    Object? json,
    bool gzipBody = false,
  }) {
    return api.send(
      method,
      path,
      json: json,
      gzipBody: gzipBody,
      headers: {if (_access != null) 'Authorization': 'Bearer $_access'},
    );
  }

  /// 동시에 여러 요청이 401을 받아도 갱신은 한 번만 한다. refresh 토큰은 한 번만 쓸 수 있기 때문이다.
  Future<bool> _refreshTokens() {
    return _refreshing ??= () async {
      try {
        final refresh = _refresh;
        if (refresh == null) {
          return false;
        }
        final body = await api.send(
          'POST',
          '/v1/auth/refresh',
          json: {'refresh_token': refresh},
        );
        await _saveTokens(body as Map<String, dynamic>);
        return true;
      } on ApiException catch (error) {
        if (error.isNetwork) {
          return false;
        }
        await logout(
          reason:
              error.code == null ? '로그인이 만료됐습니다. 다시 로그인해 주세요.' : error.message,
        );
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<void> _handleAccountError(ApiException error) async {
    if (error.code == 'account_rejected' || error.code == 'pending_approval') {
      await logout(reason: error.message);
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> body) async {
    _access = body['access_token'] as String;
    _refresh = body['refresh_token'] as String;
    _user = AuthUser.fromJson(body['user'] as Map<String, dynamic>);
    await _storage.write(key: _accessKey, value: _access);
    await _storage.write(key: _refreshKey, value: _refresh);
    await _storage.write(key: _userKey, value: jsonEncode(_user!.toJson()));
    await _storage.write(key: _serverKey, value: ServerConfig.instance.baseUrl);
  }

  Future<void> _clear() async {
    _access = null;
    _refresh = null;
    _user = null;
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }
}
