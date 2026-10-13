import 'package:flutter/material.dart';

/// Permissions are server-approved work services, not vehicle categories.
/// If the permissions API is unavailable, preserve the legacy Taxi-only UI.
List<String> approvedDriverRequestTabs(Object? response) {
  if (response is! List) return const <String>['ride'];
  const order = <String>['ride', 'parcel', 'market'];
  final approved = <String>{};
  for (final record in response) {
    if (record is! Map) continue;
    final service = record['service_key']?.toString();
    if (record['status'] == 'approved' && service != null) {
      approved.add(service);
    }
  }
  return order.where(approved.contains).toList(growable: false);
}

String deliveryRequestServiceKey(Map<String, dynamic> delivery) {
  final orderId = delivery['marketplace_order_id'];
  return orderId == null || orderId.toString().isEmpty ? 'parcel' : 'market';
}

/// Adds category filters *only* for drivers approved for multiple services.
/// Cards are read-only: tapping them opens the existing offer experience.
class DriverServiceRequestsSheet extends StatefulWidget {
  const DriverServiceRequestsSheet({
    super.key,
    required this.approvedServices,
    required this.rides,
    required this.deliveries,
    required this.onRideTap,
    required this.onDeliveryTap,
  });

  final List<String> approvedServices;
  final List<Map<String, dynamic>> rides;
  final List<Map<String, dynamic>> deliveries;
  final ValueChanged<Map<String, dynamic>> onRideTap;
  final ValueChanged<Map<String, dynamic>> onDeliveryTap;

  @override
  State<DriverServiceRequestsSheet> createState() =>
      _DriverServiceRequestsSheetState();
}

class _DriverServiceRequestsSheetState
    extends State<DriverServiceRequestsSheet> {
  late String selectedService;

  static const labels = <String, String>{
    'ride': 'Taxi',
    'parcel': 'Envíos',
    'market': 'Delivery',
  };
  static const icons = <String, IconData>{
    'ride': Icons.local_taxi_rounded,
    'parcel': Icons.inventory_2_outlined,
    'market': Icons.storefront_rounded,
  };

  @override
  void initState() {
    super.initState();
    selectedService = widget.approvedServices.contains('ride')
        ? 'ride'
        : widget.approvedServices.isNotEmpty
            ? widget.approvedServices.first
            : '';
  }

  @override
  Widget build(BuildContext context) {
    final matching = selectedService == 'ride'
        ? widget.rides
        : widget.deliveries
            .where((delivery) =>
                deliveryRequestServiceKey(delivery) == selectedService)
            .toList(growable: false);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = Theme.of(context).dividerColor;
    final color = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.sizeOf(context).height * .72,
        decoration: BoxDecoration(
          color: color.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 9),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Solicitudes activas',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.primary,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${matching.length}',
                      style: TextStyle(
                          color: color.onPrimary, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Cerrar solicitudes',
                  ),
                ],
              ),
            ),
            if (widget.approvedServices.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    for (final service in widget.approvedServices)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: OutlinedButton(
                            onPressed: () =>
                                setState(() => selectedService = service),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: selectedService == service
                                  ? color.primaryContainer
                                  : null,
                              foregroundColor: selectedService == service
                                  ? color.onPrimaryContainer
                                  : null,
                              side: BorderSide(
                                color: selectedService == service
                                    ? color.primary
                                    : border,
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 2, vertical: 12),
                            ),
                            child: Text(labels[service] ?? service,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Divider(height: 1, color: border),
            Expanded(
              child: matching.isEmpty
                  ? const Center(child: Text('No hay solicitudes activas.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: matching.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = matching[index];
                        final ride = selectedService == 'ride';
                        final from = (item['pickup_address'] ?? 'Origen')
                            .toString();
                        final to = (ride
                                ? item['destination_address']
                                : item['dropoff_address'])?.toString() ??
                            'Destino';
                        final fare = item['proposed_fare']?.toString() ?? '—';
                        final currency =
                            item['currency']?.toString() ?? '';
                        return Material(
                          color: dark
                              ? color.surfaceContainerHighest
                              : color.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => ride
                                ? widget.onRideTap(item)
                                : widget.onDeliveryTap(item),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: color.primaryContainer,
                                    child: Icon(icons[selectedService],
                                        color: color.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('${labels[selectedService]} · $currency $fare',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 5),
                                        Text('Recogida: $from',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        Text('Destino: $to',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
