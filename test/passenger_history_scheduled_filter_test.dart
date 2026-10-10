import 'package:flutter_test/flutter_test.dart';
import 'package:expressdelivery/express_account_pages.dart';

void main() {
  final scheduled = <String, dynamic>{
    'status': 'pending',
    'scheduled_for': '2026-10-11T15:00:00Z',
  };
  final immediate = <String, dynamic>{'status': 'completed'};
  final cancelledImmediate = <String, dynamic>{'status': 'cancelled'};

  test('filtro scheduled solo deja pasar registros con scheduled_for', () {
    expect(historyFilterMatches('scheduled', scheduled, scheduled), isTrue);
    expect(historyFilterMatches('scheduled', immediate, immediate), isFalse);
    expect(
      historyFilterMatches('scheduled', cancelledImmediate, cancelledImmediate),
      isFalse,
    );
  });

  test('filtro scheduled usa la ruta del viaje cuando el dato viene anidado', () {
    final trip = <String, dynamic>{'status': 'completed'};
    final route = <String, dynamic>{'scheduled_for': '2026-10-11T15:00:00Z'};
    expect(historyFilterMatches('scheduled', trip, route), isTrue);
  });

  test('los filtros existentes no cambian', () {
    expect(historyFilterMatches('all', immediate, immediate), isTrue);
    expect(historyFilterMatches('all', scheduled, scheduled), isTrue);
    expect(historyFilterMatches('completed', immediate, immediate), isTrue);
    expect(historyFilterMatches('completed', scheduled, scheduled), isFalse);
    expect(
      historyFilterMatches('cancelled', cancelledImmediate, cancelledImmediate),
      isTrue,
    );
  });
}
