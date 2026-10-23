import 'dart:ui' as ui;

import 'package:expressdelivery/map_tile_handover.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedImageProvider extends ImageProvider<Object> {
  const _FixedImageProvider(this.image);
  final ui.Image image;

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<Object>(this);

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
      );
}

Future<ui.Image> _solidImage(int size) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  return recorder.endRecording().toImage(size, size);
}

void main() {
  test('the first mount shows the active source without a handover', () {
    final controller = TileHandoverController();
    expect(controller.begin(false), 1);
    expect(controller.handoverPending, isFalse);
    expect(controller.attributionIsMapbox, isFalse);
  });

  test('switching to Mapbox keeps the old layer until its first real tile', () {
    final controller = TileHandoverController();
    controller.begin(false);
    final gen = controller.begin(true)!;
    expect(controller.handoverPending, isTrue);
    expect(controller.attributionIsMapbox, isFalse,
        reason: 'OSM tiles are still the ones on screen');

    controller.onRealTile(gen);
    expect(controller.handoverPending, isFalse);
    expect(controller.attributionIsMapbox, isTrue);
  });

  test('no amount of waiting releases the old layer without a real tile', () {
    // Six seconds of silence, or any number of them, must not remove the
    // previous map while the new source has produced no valid image.
    final controller = TileHandoverController();
    controller.begin(false);
    controller.begin(true);
    expect(controller.handoverPending, isTrue);
    expect(controller.attributionIsMapbox, isFalse);
  });

  test('switching away from Mapbox keeps Mapbox attribution until the swap ends', () {
    final controller = TileHandoverController();
    controller.begin(true);
    final gen = controller.begin(false)!;
    expect(controller.attributionIsMapbox, isTrue,
        reason: 'Mapbox tiles are still on screen');

    controller.onRealTile(gen);
    expect(controller.attributionIsMapbox, isFalse);
  });

  test('a tile from an older generation never ends the current handover', () {
    final controller = TileHandoverController();
    controller.begin(false);
    final first = controller.begin(true)!;
    final second = controller.begin(false)!;
    controller.onRealTile(first);
    expect(controller.handoverPending, isTrue);
    controller.onRealTile(second);
    expect(controller.handoverPending, isFalse);
  });

  test('A to B to A within the window ends only with the newest generation', () {
    final controller = TileHandoverController();
    controller.begin(false);
    final b = controller.begin(true)!;
    final a = controller.begin(false)!;
    expect(a, 3);
    controller.onRealTile(b);
    expect(controller.handoverPending, isTrue);
    controller.onRealTile(a);
    expect(controller.handoverPending, isFalse);
  });

  test('a second switch keeps the visible outgoing layer instead of replacing it', () {
    // OSM is on screen. Switching to Mapbox and back before any Mapbox tile
    // arrives must keep showing OSM as the old layer, not the never-shown
    // intermediate Mapbox layer.
    final controller = TileHandoverController();
    controller.begin(false);
    final first = controller.begin(true)!;
    final second = controller.begin(false)!;
    expect(controller.handoverPending, isTrue);
    expect(controller.attributionIsMapbox, isFalse);
    controller.onRealTile(first);
    expect(controller.handoverPending, isTrue, reason: 'stale generation');
    controller.onRealTile(second);
    expect(controller.handoverPending, isFalse);
  });

  test('requesting the mode already active changes nothing', () {
    final controller = TileHandoverController();
    controller.begin(true);
    var notified = 0;
    controller.addListener(() => notified++);
    expect(controller.begin(true), isNull);
    expect(notified, 0);
  });

  testWidgets('a 1x1 silenced failure does not count as a loaded tile', (tester) async {
    late ui.Image silenced;
    await tester.runAsync(() async {
      silenced = await _solidImage(1);
    });
    var loaded = 0;
    final wrapped = ExpressFirstRealTileImageProvider(
      _FixedImageProvider(silenced),
      () => loaded++,
    );
    final stream = wrapped.resolve(ImageConfiguration.empty);
    stream.addListener(ImageStreamListener((_, __) {}));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(loaded, 0);
  });

  testWidgets('a real 256px tile notifies the handover exactly once', (tester) async {
    late ui.Image real;
    await tester.runAsync(() async {
      real = await _solidImage(256);
    });
    var loaded = 0;
    final wrapped = ExpressFirstRealTileImageProvider(
      _FixedImageProvider(real),
      () => loaded++,
    );
    final stream = wrapped.resolve(ImageConfiguration.empty);
    stream.addListener(ImageStreamListener((_, __) {}));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(loaded, 1);
  });

  test('only real tile widths count as loaded', () {
    expect(isRealTileWidth(1), isFalse);
    expect(isRealTileWidth(256), isTrue);
    expect(isRealTileWidth(512), isTrue);
  });

  test('a cold start with no visible map falls back to OSM only when Mapbox never delivered', () {
    expect(coldStartNeedsOsmFallback(mapboxActive: true, outgoingVisible: false, realTileSeen: false), isTrue);
    expect(coldStartNeedsOsmFallback(mapboxActive: true, outgoingVisible: false, realTileSeen: true), isFalse);
    expect(coldStartNeedsOsmFallback(mapboxActive: true, outgoingVisible: true, realTileSeen: false), isFalse,
        reason: 'a visible old map is never removed by time');
    expect(coldStartNeedsOsmFallback(mapboxActive: false, outgoingVisible: false, realTileSeen: false), isFalse);
  });

  test('a cold-start fallback drops the never-shown Mapbox layer without a handover', () {
    final controller = TileHandoverController();
    controller.begin(true);
    final gen = controller.beginWithoutOutgoing(false);
    expect(controller.handoverPending, isFalse);
    expect(controller.attributionIsMapbox, isFalse);
    expect(controller.activeIsMapbox, isFalse);
    expect(gen, 2);
  });
}
