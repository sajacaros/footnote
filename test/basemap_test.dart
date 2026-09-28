import 'package:flutter_test/flutter_test.dart';
import 'package:footnote_walk/services/basemap.dart';

void main() {
  test('labels show Korean only and city names hide when zoomed in', () {
    final style = customizeStyle({
      'layers': [
        {
          'id': 'highway-name-minor',
          'layout': {
            'text-field': [
              'case',
              ['has', 'name:nonlatin'],
              [
                'concat',
                ['get', 'name:latin'],
                ' ',
                ['get', 'name:nonlatin']
              ],
              [
                'coalesce',
                ['get', 'name_en'],
                ['get', 'name']
              ],
            ],
          },
        },
        {'id': 'label_city', 'minzoom': 3, 'layout': {}},
        {
          'id': 'highway-shield-non-us',
          'layout': {
            'text-field': [
              'to-string',
              ['get', 'ref']
            ],
          },
        },
      ],
    });
    final layers = style['layers'] as List;
    expect(layers[0]['layout']['text-field'][1], ['get', 'name:ko']);
    expect(layers[1]['maxzoom'], 12);
    // 이름이 아닌 라벨(도로 번호)은 그대로 둔다.
    expect(layers[2]['layout']['text-field'], [
      'to-string',
      ['get', 'ref']
    ]);
  });
}
