import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/passenger_ads.dart';
import '../lib/passenger_content_sheet.dart';
import '../lib/content_sized_collections.dart';

void main() {
  testWidgets(
    'banner keeps full uploaded proportions without public campaign text',
    (tester) async {
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(1280, 400);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return bytes;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 320,
                child: ExpressBannerImage(
                  image: MemoryImage(bytes!.buffer.asUint8List()),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          tester
              .widget<ExpressBannerImage>(find.byType(ExpressBannerImage))
              .image,
          tester.element(find.byType(ExpressBannerImage)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Image)), const Size(320, 100));
      expect(find.byType(Text), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('home sheet grows upward and caps only for available screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final height = ValueNotifier<double>(120);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: height,
            builder: (_, value, __) => PassengerContentSheet(
              child: SizedBox(width: double.infinity, height: value),
            ),
          ),
        ),
      ),
    );
    final scroll = find.byType(SingleChildScrollView);
    expect(tester.getSize(scroll).height, 120);
    height.value = 430;
    await tester.pumpAndSettle();
    expect(tester.getSize(scroll).height, 430);
    height.value = 1100;
    await tester.pumpAndSettle();
    expect(tester.getSize(scroll).height, 624);
    await tester.drag(scroll, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    height.dispose();
  });
  testWidgets('card grids and horizontal lists grow and shrink with text', (
    tester,
  ) async {
    final text = ValueNotifier<String>('Corto');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<String>(
              valueListenable: text,
              builder: (context, value, _) => Column(
                children: [
                  ContentSizedGrid(
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(value),
                        ),
                      ),
                    ],
                  ),
                  ContentSizedHorizontalList(
                    itemCount: 1,
                    itemBuilder: (_, i) => SizedBox(
                      width: 160,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(value),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final cards = find.byType(Card);
    final small = tester.getSize(cards.first).height;
    text.value = List.filled(30, 'Información adicional').join(' ');
    await tester.pumpAndSettle();
    expect(tester.getSize(cards.first).height, greaterThan(small));
    expect(tester.getSize(cards.last).height, greaterThan(small));
    text.value = 'Corto';
    await tester.pumpAndSettle();
    expect(tester.getSize(cards.first).height, small);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    text.dispose();
  });
}
