class OrderModel {
  final String id;
  final String pickupAddress;
  final String deliveryAddress;
  final String status;
  final num? total;
  final DateTime? createdAt;

  const OrderModel({
    required this.id,
    required this.pickupAddress,
    required this.deliveryAddress,
    required this.status,
    this.total,
    this.createdAt,
  });

  factory OrderModel.fromMap(Map<String, dynamic> map) => OrderModel(
    id: map['id'] as String,
    pickupAddress: map['pickup_address'] as String? ?? '',
    deliveryAddress: map['delivery_address'] as String? ?? '',
    status: map['status'] as String? ?? 'pending',
    total: map['total'] as num?,
    createdAt: map['created_at'] == null
        ? null
        : DateTime.tryParse(map['created_at'].toString()),
  );
}
