import 'dart:async';
import 'dart:ui' as ui;

import 'package:expressdelivery/map_tile_handover.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.callback);
  final void Function() callback;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}

class _Harness {
  _Harness() {
    controller = TileHandoverController(
      scheduler: (delay, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
  }

  late final TileHandoverController controller;
  final List<_FakeTimer> timers = <_FakeTimer>[];
}

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
    final h = _Harness();
    final generation = h.controller.begin(false);
    expect(generation, 1);
    expect(h.controller.handoverPending, isFalse);
    expect(h.controller.attributionIsMapbox, isFalse);
  });

  test('switching to Mapbox keeps the old layer until its first real tile', () {
    final h = _Harness();
    h.controller.begin(false);
    final gen = h.controller.begin(true)!;
    expect(h.controller.handoverPending, isTrue);
    expect(h.controller.attributionIsMapbox, isTrue);

    h.controller.onRealTile(gen);
    expect(h.controller.handoverPending, isFalse);
    expect(h.controller.attributionIsMapbox, isTrue);
  });

  test('switching away from Mapbox keeps Mapbox attribution until the swap ends', () {
    final h = _Harness();
    h.controller.begin(true);
    final gen = h.controller.begin(false)!;
    expect(h.controller.attributionIsMapbox, isTrue,
        reason: 'Mapbox tiles are still on screen');

    h.controller.onRealTile(gen);
    expect(h.controller.attributionIsMapbox, isFalse);
  });

  test('a tile from an older generation never ends the current handover', () {
    final h = _Harness();
    h.controller.begin(false);
    final first = h.controller.begin(true)!;
    final second = h.controller.begin(false)!;
    h.controller.onRealTile(first);
    expect(h.controller.handoverPending, isTrue);
    h.controller.onRealTile(second);
    expect(h.controller.handoverPending, isFalse);
  });

  test('A to B to A within the window ends only with the newest generation', () {
    final h = _Harness();
    h.controller.begin(false);
    final b = h.controller.begin(true)!;
    final a = h.controller.begin(false)!;
    expect(a, 3);
    h.controller.onRealTile(b);
    expect(h.controller.handoverPending, isTrue);
    h.controller.onRealTile(a);
    expect(h.controller.handoverPending, isFalse);
  });

  test('the old layer is released after the fallback timeout', () {
    final h = _Harness();
    h.controller.begin(false);
    h.controller.begin(true);
    expect(h.timers.length, 1);
    h.timers.single.callback();
    expect(h.controller.handoverPending, isFalse);
  });

  test('requesting the mode already active changes nothing', () {
    final h = _Harness();
    h.controller.begin(true);
    var notified = 0;
    h.controller.addListener(() => notified++);
    expect(h.controller.begin(true), isNull);
    expect(notified, 0);
  });

  test('a new switch cancels the previous fallback timer', () {
    final h = _Harness();
    h.controller.begin(false);
    h.controller.begin(true);
    h.controller.begin(false);
    expect(h.timers[0].cancelled, isTrue);
  });

  test('dispose cancels a pending fallback timer', () {
    final h = _Harness();
    h.controller.begin(false);
    h.controller.begin(true);
    h.controller.dispose();
    expect(h.timers.single.cancelled, isTrue);
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
}
