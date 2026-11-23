import 'package:flutter/material.dart';

import 'location_picker.dart';
import 'services/express_service.dart';

/// Mis direcciones. Con [selectable] cada dirección se puede tocar para
/// usarla como destino: la pantalla devuelve esa fila al cerrarse.
class SavedAddressesPage extends StatefulWidget {
  final ExpressService service;
  final bool selectable;
  const SavedAddressesPage({
    super.key,
    required this.service,
    this.selectable = false,
  });
  @override
  State<SavedAddressesPage> createState() => SavedAddressesPageState();
}

class SavedAddressesPageState extends State<SavedAddressesPage> {
  int refresh = 0;

  Future<void> add() async {
    final picked = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => const LocationPickerPage(
          title: 'Guardar dirección',
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final labelController = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nombre de la dirección'),
        content: TextField(
          controller: labelController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Ej. Casa, Trabajo',
            helperText: picked.label,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    final label = labelController.text.trim();
    labelController.dispose();
    if (save != true || label.isEmpty || !mounted) return;

    try {
      await widget.service.addSavedAddress(
        label: label,
        address: picked.label,
        latitude: picked.latitude,
        longitude: picked.longitude,
      );
      if (mounted) setState(() => refresh++);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  /// Devuelve la dirección elegida a la pantalla de inicio para cotizar.
  void choose(Map<String, dynamic> row) {
    final lat = row['latitude'];
    final lng = row['longitude'];
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta dirección no tiene ubicación en el mapa. Elimínala y vuelve a guardarla.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(context, row);
  }

  Future<void> remove(Map<String, dynamic> row) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar dirección'),
        content: Text(
          '¿Eliminar ${row['label'] ?? 'esta dirección'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await widget.service.deleteSavedAddress(row['id'].toString());
    if (mounted) setState(() => refresh++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.selectable
              ? 'Elige tu destino'
              : 'Mis direcciones'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: add,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Agregar'),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey(refresh),
          future: widget.service.savedAddresses(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data ?? [];
            if (rows.isEmpty) {
              return const Center(
                child: Text('Todavía no tienes direcciones guardadas.'),
              );
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: rows
                  .map(
                    (row) => ListTile(
                      onTap: widget.selectable ? () => choose(row) : null,
                      leading: const CircleAvatar(
                        child: Icon(Icons.location_on_outlined),
                      ),
                      title: Text(row['label'].toString()),
                      subtitle: Text(row['address'].toString()),
                      trailing: IconButton(
                        tooltip: 'Eliminar',
                        onPressed: () => remove(row),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
}

