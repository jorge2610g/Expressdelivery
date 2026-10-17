/// Mensajes que ve el conductor cuando no puede aceptar una oferta.
///
/// El servidor responde con excepciones de PostgreSQL. Esos textos técnicos
/// (código P0001, Bad Request, hint) nunca se muestran al usuario: se traducen
/// aquí y el detalle original queda para diagnóstico.
///
/// `select_ride_offer` no distingue entre oferta vencida, tomada por otro
/// conductor o cancelada: todas llegan como «Oferta vencida o no disponible».
/// Por eso ese caso usa un mensaje genérico y no uno específico.
String friendlyRideOfferError(Object? error) {
  final text = (error?.toString() ?? '').toLowerCase();
  if (text.contains('no disponible') ||
      text.contains('vencid') ||
      text.contains('ya venció') ||
      text.contains('ya no está')) {
    return 'Esta solicitud ya no está disponible. Puedes elegir otra.';
  }
  if (text.contains('propia solicitud')) {
    return 'No puedes aceptar tu propia solicitud.';
  }
  if (text.contains('entorno operativo')) {
    return 'Esta solicitud no está disponible para tu zona o servicio.';
  }
  if (text.contains('no autorizado')) {
    return 'Tu sesión no tiene permiso para esta acción. Vuelve a iniciar sesión.';
  }
  return 'No pudimos aceptar la solicitud. Intenta de nuevo.';
}
