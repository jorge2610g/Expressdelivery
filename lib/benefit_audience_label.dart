/// Texto de «Dirigido a» para un beneficio, según la audiencia guardada en su
/// configuración. Sin audiencia o con 'all', el beneficio va a todos.
String benefitAudienceLabel(Object? audience) {
  return switch (audience?.toString()) {
    'drivers' => 'Conductores',
    'passengers' => 'Pasajeros',
    _ => 'Todos los usuarios',
  };
}
