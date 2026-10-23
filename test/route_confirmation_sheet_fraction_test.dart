import 'package:expressdelivery/route_confirmation_sheet_fraction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('without a pending rating the sheet keeps its base size', () {
    final fraction = routeConfirmationSheetFraction(
      height: 914,
      classicNavigationInset: 0,
      hasPendingRating: false,
    );
    expect(fraction, closeTo(350 / 914, 0.0001));
  });

  test('a pending rating card makes the sheet grow to fit it', () {
    final without = routeConfirmationSheetFraction(
      height: 914,
      classicNavigationInset: 0,
      hasPendingRating: false,
    );
    final withRating = routeConfirmationSheetFraction(
      height: 914,
      classicNavigationInset: 0,
      hasPendingRating: true,
    );
    expect(withRating, greaterThan(without));
    expect(withRating, closeTo((350 + 76) / 914, 0.0001));
  });

  test('the sheet never exceeds its maximum fraction', () {
    final fraction = routeConfirmationSheetFraction(
      height: 500,
      classicNavigationInset: 56,
      hasPendingRating: true,
    );
    expect(fraction, lessThanOrEqualTo(0.60));
  });

  test('the sheet never drops below its minimum fraction', () {
    final fraction = routeConfirmationSheetFraction(
      height: 2000,
      classicNavigationInset: 0,
      hasPendingRating: false,
    );
    expect(fraction, greaterThanOrEqualTo(0.34));
  });

  test('a zero-height screen falls back to a safe default', () {
    final fraction = routeConfirmationSheetFraction(
      height: 0,
      classicNavigationInset: 0,
      hasPendingRating: true,
    );
    expect(fraction, .42);
  });
}
