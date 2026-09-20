import '../core/supabase_client.dart';
import '../models/order_model.dart';

class OrderService {
  Future<List<OrderModel>> customerOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];
    final rows = await supabase
        .from('orders')
        .select('id,pickup_address,delivery_address,status,total,created_at')
        .eq('customer_id', user.id)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => OrderModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> createOrder({
    required String pickupAddress,
    required String deliveryAddress,
    String? notes,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw StateError('Sesión no disponible.');
    await supabase.from('orders').insert({
      'customer_id': user.id,
      'pickup_address': pickupAddress,
      'delivery_address': deliveryAddress,
      'notes': notes,
    });
  }

  Future<List<Map<String, dynamic>>> tracking(String orderId) async {
    final rows = await supabase
        .from('order_status_history')
        .select('status,created_at')
        .eq('order_id', orderId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<OrderModel>> driverOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];
    final rows = await supabase
        .from('orders')
        .select('id,pickup_address,delivery_address,status,total,created_at')
        .or('driver_id.eq.${user.id},status.eq.pending')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => OrderModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> updateOrder(String id, String status) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw StateError('Sesión no disponible.');
    await supabase
        .from('orders')
        .update({'status': status, 'driver_id': user.id})
        .eq('id', id);
  }
}
