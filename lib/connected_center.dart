import 'package:flutter/material.dart';

import 'core/supabase_client.dart';
import 'services/express_service.dart';

class ExpressCenterPage extends StatefulWidget {
  final ExpressService service;
  const ExpressCenterPage({super.key, required this.service});

  @override
  State<ExpressCenterPage> createState() => _ExpressCenterPageState();
}

class _ExpressCenterPageState extends State<ExpressCenterPage> {
  int refresh = 0;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Centro Express'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.notifications_outlined), text: 'Avisos'),
              Tab(icon: Icon(Icons.chat_bubble_outline_rounded), text: 'Chat'),
              Tab(icon: Icon(Icons.star_outline_rounded), text: 'Calificar'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _NotificationsTab(service: widget.service, revision: refresh, onChanged: () => setState(() => refresh++)),
            _ChatsTab(service: widget.service, revision: refresh),
            _RatingsTab(service: widget.service, revision: refresh, onChanged: () => setState(() => refresh++)),
          ],
        ),
      ),
    );
  }
}

class _NotificationsTab extends StatelessWidget {
  final ExpressService service;
  final int revision;
  final VoidCallback onChanged;

  const _NotificationsTab({
    required this.service,
    required this.revision,
    required this.onChanged,
  });

  Future<void> _markRead(String id) async {
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id)
        .eq('user_id', service.userId);
  }

  Future<void> _markAllRead() async {
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', service.userId)
        .eq('is_read', false);
  }

  String _timeLabel(Object? raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final now = DateTime.now();
    final sameDay =
        now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    if (sameDay) return 'Hoy · $hour:$minute';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month · $hour:$minute';
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'ride_assigned':
      case 'driver_approval':
        return Icons.local_taxi_rounded;
      case 'delivery_assigned':
        return Icons.local_shipping_rounded;
      case 'payment':
        return Icons.payments_outlined;
      case 'emergency':
        return Icons.sos_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(revision),
      future: service.myNotifications(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'No se pudieron cargar los avisos: ${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }

        final rows = snapshot.data ?? [];
        final unreadCount =
            rows.where((row) => row['is_read'] != true).length;

        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 56,
                    color: Color(0xFF98A2B3),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No tienes avisos',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Las novedades de tus servicios aparecerán aquí.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF667085)),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => onChanged(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      unreadCount == 0
                          ? 'Todo al día'
                          : '$unreadCount sin leer',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (unreadCount > 0)
                    TextButton.icon(
                      onPressed: () async {
                        await _markAllRead();
                        onChanged();
                      },
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: const Text('Marcar todas'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ...rows.map((row) {
                final unread = row['is_read'] != true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: unread
                        ? const Color(0xFFF4F8FF)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: unread
                          ? const Color(0xFFCFE0FF)
                          : const Color(0xFFE4E7EC),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: unread
                          ? const Color(0xFFEAF2FF)
                          : const Color(0xFFF2F4F7),
                      child: Icon(
                        _iconFor(row['type']?.toString()),
                        color: unread
                            ? const Color(0xFF0B57D0)
                            : const Color(0xFF667085),
                      ),
                    ),
                    title: Text(
                      row['title']?.toString() ?? 'Aviso',
                      style: TextStyle(
                        fontWeight:
                            unread ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row['body']?.toString() ?? ''),
                          const SizedBox(height: 4),
                          Text(
                            _timeLabel(row['created_at']),
                            style: const TextStyle(
                              color: Color(0xFF98A2B3),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: unread
                        ? const Icon(
                            Icons.circle,
                            size: 9,
                            color: Color(0xFF0B57D0),
                          )
                        : null,
                    onTap: unread
                        ? () async {
                            await _markRead(row['id'].toString());
                            onChanged();
                          }
                        : null,
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _ChatsTab extends StatelessWidget {
  final ExpressService service;
  final int revision;
  const _ChatsTab({required this.service, required this.revision});

  Future<_ServicesBundle> _load() async {
    final trips = await service.myTrips();
    final deliveries = await service.myDeliveries();
    return _ServicesBundle(trips, deliveries);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ServicesBundle>(
      key: ValueKey(revision),
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('No se pudieron cargar los servicios: ${snapshot.error}'));
        }
        final data = snapshot.data!;
        final deliveries = data.deliveries.where((d) => d['courier_id'] != null).toList();
        if (data.trips.isEmpty && deliveries.isEmpty) {
          return const Center(child: Text('El chat se habilita cuando un servicio tiene conductor o repartidor asignado.'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...data.trips.map((trip) {
              final ride = trip['ride_requests'];
              final title = ride is Map
                  ? '${ride['pickup_address'] ?? 'Origen'} → ${ride['destination_address'] ?? 'Destino'}'
                  : 'Viaje Express';
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.local_taxi_rounded)),
                  title: Text(title),
                  subtitle: Text('Viaje · ${trip['status']}'),
                  trailing: const Icon(Icons.chat_bubble_outline_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ServiceChatPage(
                        service: service,
                        title: title,
                        tripId: trip['id'].toString(),
                      ),
                    ),
                  ),
                ),
              );
            }),
            ...deliveries.map((delivery) {
              final title = '${delivery['pickup_address']} → ${delivery['dropoff_address']}';
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.local_shipping_rounded)),
                  title: Text(title),
                  subtitle: Text('Delivery · ${delivery['status']}'),
                  trailing: const Icon(Icons.chat_bubble_outline_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ServiceChatPage(
                        service: service,
                        title: title,
                        deliveryId: delivery['id'].toString(),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class ServiceChatPage extends StatefulWidget {
  final ExpressService service;
  final String title;
  final String? tripId;
  final String? deliveryId;
  const ServiceChatPage({
    super.key,
    required this.service,
    required this.title,
    this.tripId,
    this.deliveryId,
  });

  @override
  State<ServiceChatPage> createState() => _ServiceChatPageState();
}

class _ServiceChatPageState extends State<ServiceChatPage> {
  final controller = TextEditingController();
  int refresh = 0;
  bool sending = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await widget.service.sendMessage(
        tripId: widget.tripId,
        deliveryId: widget.deliveryId,
        body: text,
      );
      controller.clear();
      if (mounted) setState(() => refresh++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo enviar: $e')));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filterColumn = widget.tripId != null ? 'trip_id' : 'delivery_id';
    final filterValue = widget.tripId ?? widget.deliveryId!;
    final messageStream = supabase
        .from('service_messages')
        .stream(primaryKey: ['id'])
        .eq(filterColumn, filterValue)
        .order('created_at');

    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messageStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) return const Center(child: Text('Todavía no hay mensajes.'));
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final mine = row['sender_id'] == widget.service.userId;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 320),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(row['body']?.toString() ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: 'Escribe un mensaje...', counterText: ''),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: sending ? null : _send,
                    icon: sending
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingsTab extends StatelessWidget {
  final ExpressService service;
  final int revision;
  final VoidCallback onChanged;
  const _RatingsTab({required this.service, required this.revision, required this.onChanged});

  Future<_RatingBundle> _load() async {
    final trips = await service.myTrips();
    final deliveries = await service.myDeliveries();
    final ratings = await supabase
        .from('ratings')
        .select('trip_id,delivery_id,from_user_id')
        .eq('from_user_id', service.userId);
    return _RatingBundle(trips, deliveries, List<Map<String, dynamic>>.from(ratings));
  }

  bool _ratedTrip(_RatingBundle data, String id) => data.ratings.any((r) => r['trip_id']?.toString() == id);
  bool _ratedDelivery(_RatingBundle data, String id) => data.ratings.any((r) => r['delivery_id']?.toString() == id);

  Future<void> _rate(
    BuildContext context, {
    String? tripId,
    String? deliveryId,
    required String toUserId,
  }) async {
    int score = 5;
    final comment = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Calificar servicio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final value = index + 1;
                  return IconButton(
                    onPressed: () => setLocalState(() => score = value),
                    icon: Icon(value <= score ? Icons.star_rounded : Icons.star_outline_rounded),
                  );
                }),
              ),
              TextField(controller: comment, maxLines: 3, decoration: const InputDecoration(labelText: 'Comentario opcional')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                try {
                  await service.submitRating(
                    tripId: tripId,
                    deliveryId: deliveryId,
                    toUserId: toUserId,
                    score: score,
                    comment: comment.text.trim().isEmpty ? null : comment.text.trim(),
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('No se pudo guardar la calificación: $e')));
                }
              },
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    comment.dispose();
    if (saved == true) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RatingBundle>(
      key: ValueKey(revision),
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('No se pudieron cargar las calificaciones: ${snapshot.error}'));
        }
        final data = snapshot.data!;
        final completedTrips = data.trips.where((t) => t['status'] == 'completed').toList();
        final completedDeliveries = data.deliveries.where((d) => d['status'] == 'delivered').toList();
        if (completedTrips.isEmpty && completedDeliveries.isEmpty) {
          return const Center(child: Text('Los servicios completados aparecerán aquí para calificarlos.'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...completedTrips.map((trip) {
              final id = trip['id'].toString();
              final passenger = trip['passenger_id'].toString();
              final driver = trip['driver_id'].toString();
              final counterpart = service.userId == passenger ? driver : passenger;
              final rated = _ratedTrip(data, id);
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.local_taxi_rounded)),
                  title: const Text('Viaje completado'),
                  subtitle: Text('Bs ${trip['final_fare'] ?? '-'}'),
                  trailing: rated
                      ? const Chip(label: Text('Calificado'))
                      : FilledButton(onPressed: () => _rate(context, tripId: id, toUserId: counterpart), child: const Text('Calificar')),
                ),
              );
            }),
            ...completedDeliveries.map((delivery) {
              final id = delivery['id'].toString();
              final customer = delivery['customer_id'].toString();
              final courier = delivery['courier_id']?.toString();
              if (courier == null) return const SizedBox.shrink();
              final counterpart = service.userId == customer ? courier : customer;
              final rated = _ratedDelivery(data, id);
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.local_shipping_rounded)),
                  title: const Text('Delivery completado'),
                  subtitle: Text('Bs ${delivery['proposed_fare'] ?? '-'}'),
                  trailing: rated
                      ? const Chip(label: Text('Calificado'))
                      : FilledButton(onPressed: () => _rate(context, deliveryId: id, toUserId: counterpart), child: const Text('Calificar')),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _ServicesBundle {
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> deliveries;
  _ServicesBundle(this.trips, this.deliveries);
}

class _RatingBundle {
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> ratings;
  _RatingBundle(this.trips, this.deliveries, this.ratings);
}
