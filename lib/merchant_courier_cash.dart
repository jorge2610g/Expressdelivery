/// Reglas de cobro de un envío pedido por un restaurante («Solicitar repartidor»), tal como las ve el
/// conductor:
///  · [isCollect] (entregar y cobrar): paga el pedido al local al recoger y cobra al cliente
///    pedido + delivery; si el cliente paga con un monto mayor, se devuelve [change].
///  · solo entregar: el local ya cobró al cliente; el conductor cobra el delivery al local antes de
///    recoger y NO cobra nada al cliente.
class MerchantCourierCash {
  const MerchantCourierCash({
    required this.isCollect,
    required this.fee,
    this.order,
    this.paysWith,
  });

  final bool isCollect;

  /// Delivery: lo que gana el conductor.
  final double fee;

  /// Monto del pedido (solo «entregar y cobrar»).
  final double? order;

  /// Con cuánto paga el cliente (opcional).
  final double? paysWith;

  /// Total que el conductor cobra al cliente (0 en «solo entregar»).
  double get total => isCollect ? (order ?? 0) + fee : 0;

  /// Vuelto que debe devolver al cliente, si pagó con un monto mayor al total.
  double? get change {
    final p = paysWith;
    if (!isCollect || p == null || p <= 0 || p < total) return null;
    final c = p - total;
    return c > 0 ? c : null;
  }

  /// null si la solicitud no es de un restaurante. [ride] es la fila de `ride_requests`.
  static MerchantCourierCash? fromRide(Map<String, dynamic> ride, {double? fee}) {
    if (ride['merchant_courier'] != true) return null;
    double? num_(Object? v) => v == null ? null : double.tryParse(v.toString());
    final type = ride['merchant_service_type']?.toString();
    return MerchantCourierCash(
      isCollect: type == 'collect',
      fee: fee ?? num_(ride['proposed_fare']) ?? 0,
      order: num_(ride['merchant_order_amount']),
      paysWith: num_(ride['merchant_change_for']),
    );
  }
}
