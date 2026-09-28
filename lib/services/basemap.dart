import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:http/http.dart' as http;

/// 배경지도: OpenFreeMap "Bright" 벡터 스타일.
///
/// 키 없이 쓸 수 있고, 스타일을 받을 때 라벨을 한글만 보이게 고친다.
/// 불러오지 못하면 [style]이 null로 남고 지도는 OSM 이미지 타일로 대신 그린다.
class Basemap {
  Basemap._();

  static final Basemap instance = Basemap._();

  static const styleUrl = 'https://tiles.openfreemap.org/styles/bright';
  static const attribution =
      'OpenFreeMap © OpenMapTiles Data from OpenStreetMap';

  /// 불러온 스타일. 지도 위젯이 듣고 있다가 준비되면 벡터 지도로 바꾼다.
  final ValueNotifier<vt.Style?> style = ValueNotifier(null);
  Future<void>? _loading;

  /// 앱 시작 때 한 번 부른다. 스타일은 기기에 캐시돼 다음부터는 오프라인에서도 바로 뜬다.
  Future<void> preload() {
    return _loading ??= () async {
      try {
        style.value = await vt.StyleReader(
          uri: styleUrl,
          httpClient: _KoreanLabelsClient(http.Client()),
        ).read().timeout(const Duration(seconds: 15));
      } catch (error) {
        debugPrint('basemap style load failed, using OSM raster: $error');
        _loading = null;
      }
    }();
  }
}

/// 스타일 문서를 받을 때만 끼어들어 [customizeStyle]을 적용한다. 타일·스프라이트는 그대로 보낸다.
class _KoreanLabelsClient extends http.BaseClient {
  _KoreanLabelsClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (request.url.toString() != Basemap.styleUrl ||
        response.statusCode != 200) {
      return response;
    }
    final body = await response.stream.bytesToString();
    final customized = utf8.encode(
      jsonEncode(customizeStyle(jsonDecode(body) as Map<String, dynamic>)),
    );
    return http.StreamedResponse(
      Stream.value(customized),
      response.statusCode,
      contentLength: customized.length,
      request: request,
      headers: {
        ...response.headers,
        'content-length': '${customized.length}',
      }..remove('content-encoding'),
    );
  }

  @override
  void close() => _inner.close();
}

/// 산책 지도에 맞게 스타일을 고친다.
/// - 지명·도로명은 영문 병기 없이 한글(없으면 현지 이름)만 쓴다.
/// - 도시 이름("서울특별시")은 동네 단위로 확대하면 숨긴다.
@visibleForTesting
Map<String, dynamic> customizeStyle(Map<String, dynamic> style) {
  const koreanName = [
    'coalesce',
    ['get', 'name:ko'],
    ['get', 'name:nonlatin'],
    ['get', 'name'],
  ];
  for (final layer in (style['layers'] as List).cast<Map<String, dynamic>>()) {
    final layout = layer['layout'];
    if (layout is Map<String, dynamic> &&
        jsonEncode(layout['text-field']).contains('name:latin')) {
      layout['text-field'] = koreanName;
    }
    final id = layer['id'] as String;
    if (id.startsWith('label_city') || id == 'label_state') {
      layer['maxzoom'] = 12;
    }
  }
  return style;
}
