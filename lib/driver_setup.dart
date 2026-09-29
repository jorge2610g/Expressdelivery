import 'package:flutter/material.dart';

import 'core/supabase_client.dart';
import 'services/express_service.dart';

class DriverSetupPage extends StatefulWidget {
  final ExpressService service;
  const DriverSetupPage({super.key, required this.service});

  @override
  State<DriverSetupPage> createState() => _DriverSetupPageState();
}

class _DriverSetupPageState extends State<DriverSetupPage> {
  final license = TextEditingController();
  final city = TextEditingController();
  final brand = TextEditingController();
  final model = TextEditingController();
  final color = TextEditingController();
  final plate = TextEditingController();
  final year = TextEditingController();

  String vehicleType = 'car';
  String? vehicleId;
  String approval = 'pending';
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await widget.service.ensureDriverProfile();
      final vehicles = await widget.service.myVehicles();
      if (!mounted) return;
      license.text = profile['license_number']?.toString() ?? '';
      city.text = profile['city']?.toString() ?? '';
      approval = profile['approval_status']?.toString() ?? 'pending';
      if (vehicles.isNotEmpty) {
        final v = vehicles.firstWhere(
          (row) => row['is_active'] == true,
          orElse: () => vehicles.first,
        );
        vehicleId = v['id']?.toString();
        vehicleType = v['vehicle_type']?.toString() == 'motorcycle' ? 'motorcycle' : 'car';
        brand.text = v['brand']?.toString() ?? '';
        model.text = v['model']?.toString() ?? '';
        color.text = v['color']?.toString() ?? '';
        plate.text = v['plate']?.toString() ?? '';
        year.text = v['year']?.toString() ?? '';
      }
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el perfil: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (license.text.trim().isEmpty || city.text.trim().isEmpty || brand.text.trim().isEmpty || model.text.trim().isEmpty || plate.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa licencia, ciudad, marca, modelo y placa.')),
      );
      return;
    }

    final vehicleYear = year.text.trim().isEmpty ? null : int.tryParse(year.text.trim());
    if (year.text.trim().isNotEmpty && vehicleYear == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El año del vehículo no es válido.')),
      );
      return;
    }

    setState(() => saving = true);
    try {
      final summary = '${brand.text.trim()} ${model.text.trim()} · ${plate.text.trim()}';
      await widget.service.updateDriverDetails(
        licenseNumber: license.text.trim(),
        vehicleSummary: summary,
        city: city.text.trim(),
      );

      final values = {
        'vehicle_type': vehicleType,
        'brand': brand.text.trim(),
        'model': model.text.trim(),
        'color': color.text.trim().isEmpty ? null : color.text.trim(),
        'plate': plate.text.trim(),
        'year': vehicleYear,
        'is_active': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (vehicleId == null) {
        final row = await supabase
            .from('driver_vehicles')
            .insert({'driver_id': widget.service.userId, ...values})
            .select('id')
            .single();
        vehicleId = row['id']?.toString();
      } else {
        await supabase
            .from('driver_vehicles')
            .update(values)
            .eq('id', vehicleId!)
            .eq('driver_id', widget.service.userId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approval == 'approved'
                ? 'Datos de conductor actualizados.'
                : 'Datos guardados. Tu perfil queda pendiente de aprobación.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    license.dispose();
    city.dispose();
    brand.dispose();
    model.dispose();
    color.dispose();
    plate.dispose();
    year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil de conductor')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(
                      approval == 'approved' ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                    ),
                    title: Text(approval == 'approved' ? 'Conductor aprobado' : 'Aprobación pendiente'),
                    subtitle: Text(
                      approval == 'approved'
                          ? 'Tu cuenta puede ponerse en línea y recibir servicios.'
                          : 'Completa tus datos. Un administrador debe aprobar la cuenta antes de recibir solicitudes.',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: license,
                  decoration: const InputDecoration(labelText: 'Número de licencia', prefixIcon: Icon(Icons.badge_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: city,
                  decoration: const InputDecoration(labelText: 'Ciudad', prefixIcon: Icon(Icons.location_city_outlined)),
                ),
                const SizedBox(height: 22),
                const Text('Vehículo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: vehicleType,
                  decoration: const InputDecoration(labelText: 'Tipo de vehículo'),
                  items: const [
                    DropdownMenuItem(value: 'car', child: Text('Auto')),
                    DropdownMenuItem(value: 'motorcycle', child: Text('Moto')),
                  ],
                  onChanged: (value) => setState(() => vehicleType = value ?? 'car'),
                ),
                const SizedBox(height: 12),
                TextField(controller: brand, decoration: const InputDecoration(labelText: 'Marca')),
                const SizedBox(height: 12),
                TextField(controller: model, decoration: const InputDecoration(labelText: 'Modelo')),
                const SizedBox(height: 12),
                TextField(controller: color, decoration: const InputDecoration(labelText: 'Color')),
                const SizedBox(height: 12),
                TextField(controller: plate, decoration: const InputDecoration(labelText: 'Placa')),
                const SizedBox(height: 12),
                TextField(
                  controller: year,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Año'),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: saving
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar perfil de conductor'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                ),
              ],
            ),
    );
  }
}
