import 'package:flutter_test/flutter_test.dart';
import 'package:footnote_walk/services/server_config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('normalize', () {
    test('adds https and drops trailing slashes', () {
      expect(ServerConfig.normalize(' api.example.com:8443/ '),
          'https://api.example.com:8443');
      expect(ServerConfig.normalize('https://api.example.com/footnote//'),
          'https://api.example.com/footnote');
      expect(ServerConfig.normalize('http://10.0.2.2:8000'),
          'http://10.0.2.2:8000');
    });

    test('rejects things that are not server addresses', () {
      expect(ServerConfig.normalize(''), isNull);
      expect(ServerConfig.normalize('ftp://example.com'), isNull);
      expect(ServerConfig.normalize('https://example.com/?a=1'), isNull);
      expect(ServerConfig.normalize('https://'), isNull);
    });
  });

  group('check', () {
    test('accepts a footnote server', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/healthz');
        return http.Response('{"status":"ok"}', 200);
      });
      expect(
          await ServerConfig.check('https://api.example.com', client: client),
          isNull);
    });

    test('explains when the address is something else', () async {
      final client = MockClient((_) async => http.Response('<html>', 404));
      expect(
        await ServerConfig.check('https://example.com', client: client),
        contains('404'),
      );
    });
  });
}
