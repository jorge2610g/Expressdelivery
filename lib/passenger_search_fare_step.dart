/// Paso de ajuste de la oferta del pasajero al seguir buscando.
///
/// Respaldo local por moneda. La regla real de cada zona y servicio aún no
/// viaja con la solicitud (pendiente en backend); cuando llegue, reemplaza a
/// esta función sin tocar el panel.
num expressSearchFareStep(String currency) {
  switch (currency.trim().toUpperCase()) {
    case 'CLP':
      return 250;
    case 'BOB':
      return 1;
    default:
      return 1;
  }
}
