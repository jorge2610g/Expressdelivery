import 'package:flutter_test/flutter_test.dart';
import '../lib/banner_creatives.dart';

void main() {
  test('expande las imágenes ordenadas de una campaña con enlaces propios', () {
    final ads = bannerCreatives([
      {
        'id': 'campaign-1',
        'title': 'Solo interno',
        'slides': [
          {
            'image_url': 'https://cdn.example/a.webp',
            'target_url': 'https://a.example',
          },
          {
            'image_url': 'https://cdn.example/b.webp',
            'target_url': 'https://b.example',
          },
          {
            'media_type': 'video',
            'video_url': 'https://cdn.example/c.mp4',
            'target_url': 'https://c.example',
          },
        ],
      },
    ]);
    expect(ads, hasLength(3));
    expect(ads.map((ad) => ad['image_url']), [
      'https://cdn.example/a.webp',
      'https://cdn.example/b.webp',
      null,
    ]);
    expect(ads.map((ad) => ad['target_url']), [
      'https://a.example',
      'https://b.example',
      'https://c.example',
    ]);
    expect(ads.map((ad) => ad['id']).toSet(), {'campaign-1'});
    expect(ads.map((ad) => ad['creative_key']).toSet(), hasLength(3));
    expect(ads[2]['media_type'], 'video');
    expect(ads[2]['media_url'], 'https://cdn.example/c.mp4');
    expect(ads.every((ad) => (ad['slides'] as List).isEmpty), isTrue);
  });

  test(
    'normalizar dos veces mantiene el carrusel y respeta campañas antiguas',
    () {
      final ads = bannerCreatives([
        {
          'id': 'gallery',
          'slides': [
            {
              'image_url': 'https://cdn.example/a.webp',
              'target_url': 'https://a.example',
            },
            {
              'image_url': 'https://cdn.example/b.webp',
              'target_url': 'https://b.example',
            },
          ],
        },
        {'id': 'legacy', 'image_url': 'https://cdn.example/legacy.webp'},
      ]);
      expect(
        bannerCreatives(ads).map((ad) => ad['creative_key']),
        ads.map((ad) => ad['creative_key']),
      );
      expect(ads, hasLength(3));
      expect(ads.last['id'], 'legacy');
      expect(ads.last['target_url'], isNull);
    },
  );
}
