import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/map_vehicle_marker.dart';

void main() {
  for (final type in ['car', 'motorcycle', 'motocar']) {
    testWidgets(
      '$type artwork loads for waiting passenger and driver markers',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(child: ExpressMapVehicleMarker(vehicleType: type)),
          ),
        );
        await tester.pumpAndSettle();
        final image = tester.widget<Image>(find.byType(Image));
        expect(
          ((image.image as ResizeImage).imageProvider as AssetImage).assetName,
          'assets/map_markers/$type.png',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'active trip uses a navigation arrow and smoothly crosses north',
    (tester) async {
      Widget marker(double heading) => MaterialApp(
        home: Center(
          child: ExpressMapVehicleMarker(
            vehicleType: 'motorcycle',
            navigating: true,
            headingDegrees: heading,
          ),
        ),
      );
      await tester.pumpWidget(marker(359));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(marker(1));
      await tester.pump(const Duration(milliseconds: 225));
      final transform = tester
          .widgetList<Transform>(find.byType(Transform))
          .last;
      expect(transform.transform.entry(0, 0), greaterThan(.99));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
