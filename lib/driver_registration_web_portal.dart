import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/supabase_client.dart';
import 'driver_setup.dart';
import 'services/express_service.dart';

const _officialAndroidAppUrl =
    'https://play.google.com/store/apps/details?id=com.express.usuario1';

class ExpressDriverRegistrationWebPortal extends StatefulWidget {
  const ExpressDriverRegistrationWebPortal({super.key});

  @override
  State<ExpressDriverRegistrationWebPortal> createState() =>
      _ExpressDriverRegistrationWebPortalState();
}

class _ExpressDriverRegistrationWebPortalState
    extends State<ExpressDriverRegistrationWebPortal> {
  final _phone = TextEditingController();
  Timer? _refreshTimer;
  bool _loading = true;
  bool _savingPhone = false;
  String? _error;
  String _approvalStatus = 'not_started';
  String _dialCode = '+56';

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _phone.dispose();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<void> _refresh() async {
    try {
      final state = _map(await _supabase.rpc('my_driver_onboarding_state'));
      final profile = _map(state['profile']);
      final nextStatus =
          profile['approval_status']?.toString().trim().toLowerCase() ??
              'not_started';
      final currentUser = _supabase.auth.currentUser;
      final publicUser = await _supabase
          .from('users')
          .select('full_name,phone')
          .eq('id', currentUser!.id)
          .maybeSingle();
      final phoneValue = publicUser?['phone']?.toString().trim() ?? '';
      if (!mounted) return;
      setState(() {
        _approvalStatus = nextStatus;
        _error = null;
        if (_phone.text.trim().isEmpty) {
          if (phoneValue.startsWith('+591')) {
            _phone.text = phoneValue.substring(4);
          } else if (phoneValue.startsWith('+56')) {
            _phone.text = phoneValue.substring(3);
          } else {
            _phone.text = phoneValue.replaceAll(RegExp(r'\D'), '');
          }
          if (phoneValue.startsWith('+591')) {
            _dialCode = '+591';
          } else {
            _dialCode = '+56';
          }
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error =
          'No pudimos consultar el estado del registro. Revisa tu conexión e inténtalo de nuevo.');
      debugPrint('Driver web registration state failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePhoneAndContinue() async {
    var digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final dialDigits = _dialCode.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith(dialDigits) && digits.length > dialDigits.length) {
      digits = digits.substring(dialDigits.length);
    }
    if (digits.length < 7 || digits.length > 15) {
      _showMessage('Ingresa un teléfono válido con código de país.');
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _savingPhone = true);
    try {
      final row = await _supabase
          .from('users')
          .update({
            'phone': '$_dialCode$digits',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', userId)
          .select('id')
          .maybeSingle();
      if (row == null) {
        throw StateError('No se pudo guardar el teléfono de la cuenta.');
      }
      await _openDriverSetup();
    } catch (error) {
      _showMessage(
        'No se pudo guardar el teléfono. Revisa los datos e inténtalo de nuevo.',
      );
      debugPrint('Driver web registration phone save failed: $error');
    } finally {
      if (mounted) setState(() => _savingPhone = false);
    }
  }

  Future<void> _openDriverSetup() async {
    await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => DriverSetupPage(service: ExpressService()),
      ),
    );
    await _refresh();
  }

  Future<void> _openOfficialApp() async {
    final opened = await launchUrl(
      Uri.parse(_officialAndroidAppUrl),
      mode: LaunchMode.platformDefault,
    );
    if (!opened) _showMessage('No se pudo abrir la página de Express en Play.');
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final email = _supabase.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de conductor'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.local_taxi_rounded,
                              color: Color(0xFF0B57D0),
                              size: 38,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Conduce con Express',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            Text('Cuenta: $email'),
                            const SizedBox(height: 12),
                            const Text(
                              'Completa tu información y carga los documentos solicitados para tu zona. El equipo revisará tu solicitud y recibirás un correo cuando se apruebe.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _refresh,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      _statusCard(context),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    switch (_approvalStatus) {
      case 'approved':
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_rounded,
                    color: Color(0xFF16803C), size: 38),
                const SizedBox(height: 10),
                Text(
                  'Tu registro fue aprobado',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Descarga la aplicación oficial e inicia sesión con la misma cuenta que usaste para registrarte.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _openOfficialApp,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Descargar Express'),
                ),
              ],
            ),
          ),
        );
      case 'pending':
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.hourglass_top_rounded,
                    color: Color(0xFF0B57D0), size: 38),
                const SizedBox(height: 10),
                Text(
                  'Solicitud en revisión',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Te avisaremos por correo cuando el equipo termine la revisión.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Actualizar estado'),
                ),
              ],
            ),
          ),
        );
      default:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Antes de continuar',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Necesitamos un número de teléfono para contactarte durante el proceso.',
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _dialCode,
                  decoration: const InputDecoration(labelText: 'País'),
                  items: const [
                    DropdownMenuItem(value: '+56', child: Text('Chile (+56)')),
                    DropdownMenuItem(
                        value: '+591', child: Text('Bolivia (+591)')),
                  ],
                  onChanged: _savingPhone
                      ? null
                      : (value) {
                          if (value != null) setState(() => _dialCode = value);
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Número de teléfono',
                    prefixText: '$_dialCode ',
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _savingPhone ? null : _savePhoneAndContinue,
                    child: _savingPhone
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continuar al registro'),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}
