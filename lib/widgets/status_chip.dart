import 'package:flutter/material.dart';

const statusLabels = {
  'pending': 'Pendiente',
  'accepted': 'Aceptado',
  'picked_up': 'Retirado',
  'in_transit': 'En camino',
  'delivered': 'Entregado',
  'cancelled': 'Cancelado',
};

IconData statusIcon(String status) {
  switch (status) {
    case 'accepted': return Icons.check_circle_outline;
    case 'picked_up': return Icons.inventory_2_outlined;
    case 'in_transit': return Icons.local_shipping_outlined;
    case 'delivered': return Icons.done_all;
    case 'cancelled': return Icons.cancel_outlined;
    default: return Icons.schedule;
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(statusIcon(status), size: 17),
    label: Text(statusLabels[status] ?? status),
  );
}
