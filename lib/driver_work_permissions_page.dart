import 'package:flutter/material.dart';

import 'core/runtime_channel.dart';
import 'core/driver_work_scope.dart';
import 'core/supabase_client.dart';

/// A request never grants permission. Approval is an admin-only action.
class DriverWorkPermissionsPage extends StatefulWidget {
  const DriverWorkPermissionsPage({super.key});

  @override
  State<DriverWorkPermissionsPage> createState() =>
      _DriverWorkPermissionsPageState();
}

class _DriverWorkPermissionsPageState
    extends State<DriverWorkPermissionsPage> {
  bool loading = true;
  String? error;
  String? submitting;
  List<Map<String, dynamic>> permissions = const [];
  static const labels = <String, String>{
    'ride': 'Taxi y pasajeros',
    'parcel': 'Paquetería y documentos',
    'market': 'Pedidos de restaurantes',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final raw = await supabase.rpc(
        'my_driver_work_permissions',
        params: {'p_channel': ExpressRuntimeChannel.name},
      );
      if (!mounted) return;
      setState(() => permissions = (raw as List)
          .whereType<Map>()
          .where((row) => expressPrimaryDriverServices.contains(
                row['service_key']?.toString(),
              ))
          .map((row) => Map<String, dynamic>.from(row))
          .toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => error = ExpressRuntimeChannel.userSafeError(
        e, fallback: 'No pudimos consultar tus servicios autorizados.',
      ));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _request(String serviceKey) async {
    if (submitting != null) return;
    setState(() => submitting = serviceKey);
    try {
      await supabase.rpc('request_driver_work_permission', params: {
        'p_service_key': serviceKey,
        'p_channel': ExpressRuntimeChannel.name,
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Solicitud enviada. Te avisaremos cuando haya novedades.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ExpressRuntimeChannel.userSafeError(
          e, fallback: 'No se pudo solicitar este servicio.',
        )),
      ));
    } finally {
      if (mounted) setState(() => submitting = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mis servicios autorizados')),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Consulta y solicita tus autorizaciones para Taxi, Envíos y '
                'pedidos de restaurantes.',
              ),
              const SizedBox(height: 16),
              if (loading)
                const Center(child: CircularProgressIndicator())
              else if (error != null)
                ListTile(
                  title: Text(error!),
                  trailing: TextButton(
                    onPressed: _load,
                    child: const Text('Reintentar'),
                  ),
                )
              else
                ...permissions.map((row) {
                  final key = row['service_key']?.toString() ?? '';
                  final status = row['status']?.toString() ?? 'not_requested';
                  final label = switch (status) {
                    'approved' => 'Aprobado',
                    'pending' => 'Pendiente de aprobación',
                    'rejected' => 'Rechazado',
                    _ => 'No solicitado',
                  };
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            labels[key] ?? key,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(label),
                          if (status != 'approved' && status != 'pending')
                            TextButton.icon(
                              onPressed: submitting == null
                                  ? () => _request(key)
                                  : null,
                              icon: const Icon(Icons.add_task_outlined),
                              label: Text(submitting == key
                                  ? 'Enviando…'
                                  : 'Solicitar servicio'),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      );
}
