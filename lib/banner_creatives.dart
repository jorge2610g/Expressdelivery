/// Expands one campaign's ordered gallery into clickable carousel creatives.
/// The database UUID is retained for campaign metrics and authorization.
List<Map<String, dynamic>> bannerCreatives(
  List<Map<String, dynamic>> campaigns,
) {
  final result = <Map<String, dynamic>>[];
  for (final campaign in campaigns) {
    final slides = campaign['slides'];
    if (slides is List && slides.isNotEmpty) {
      for (var i = 0; i < slides.length; i++) {
        final slide = slides[i];
        if (slide is! Map) continue;
        final isVideo = slide['media_type'] == 'video';
        final image = (slide['image_url'] ?? '').toString().trim();
        final video = (slide['video_url'] ?? '').toString().trim();
        if (isVideo
            ? !video.startsWith('https://')
            : !image.startsWith('https://')) {
          continue;
        }
        final url = isVideo ? video : image;
        result.add({
          ...campaign,
          'image_url': isVideo ? null : image,
          'media_type': isVideo ? 'video' : 'image',
          'media_url': isVideo ? video : null,
          'target_url':
              slide['target_url']?.toString() ?? campaign['target_url'],
          'slides': const <dynamic>[],
          'creative_key': '${campaign['id']}/$i/$url',
        });
      }
    } else {
      final image = (campaign['image_url'] ?? '').toString();
      final video = (campaign['media_url'] ?? '').toString();
      if (image.startsWith('https://') ||
          (campaign['media_type'] == 'video' && video.startsWith('https://'))) {
        result.add({
          ...campaign,
          'creative_key': campaign['creative_key'] ?? campaign['id'].toString(),
        });
      }
    }
  }
  return result;
}
