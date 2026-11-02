/// Marca de lectura fallida. Se usa en vez de null para no confundir un fallo
/// con una lectura correcta que no devolvió nada.
const Object passengerReadFailed = Object();

/// Valor de una lectura del home. Si falló, conserva el valor previo (solo si
/// era de la misma entidad, lo decide quien llama) y, si no había, usa el de
/// respaldo. Si la lectura salió bien, devuelve lo leído, aunque sea null.
T resolvePassengerRead<T>(
  Object? read, {
  required T? previous,
  required T fallback,
}) {
  if (identical(read, passengerReadFailed)) {
    return previous ?? fallback;
  }
  return read as T;
}
