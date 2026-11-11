import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_client.dart';
import 'sales_code_intake.dart';

/// Asesores de ventas: código del asesor al registrarse, código de
/// verificación para la persona registrada y portal del asesor.

const String salesPublicBaseUrl = 'https://expressviajes.online';
const String _pendingCodeKey = 'express_sales_pending_code';
final RegExp _salesCodePattern = RegExp(r'^[A-Z0-9-]{4,20}$');

/// Normaliza un código de asesor; devuelve null si no tiene formato válido.
String? normalizeSalesCode(String? raw) {
  final value = (raw ?? '').trim().toUpperCase();
  return _salesCodePattern.hasMatch(value) ? value : null;
}

/// Código de asesor en el enlace del QR: `/r/CODIGO` o `?asesor=CODIGO`.
String? salesCodeFromUri(Uri uri) {
  final fromQuery = normalizeSalesCode(uri.queryParameters['asesor']);
  if (fromQuery != null) return fromQuery;
  final segments =
      uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
  if (segments.length == 2 && segments[0].toLowerCase() == 'r') {
    return normalizeSalesCode(segments[1]);
  }
  return null;
}

/// Código del asesor dentro del referrer de Google Play:
/// `sales_code=CODIGO` (ya decodificado o codificado).
String? salesCodeFromReferrer(String raw) {
  if (raw.trim().isEmpty) return null;
  try {
    final decoded = Uri.decodeComponent(raw);
    return normalizeSalesCode(Uri.splitQueryString(decoded)['sales_code']);
  } catch (_) {
    return null;
  }
}

/// Portal del asesor: `/asesor` o `?portal=asesor`.
bool isSalesAdvisorPortalUri(Uri uri) {
  if (uri.queryParameters['portal']?.trim().toLowerCase() == 'asesor') {
    return true;
  }
  final segments =
      uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
  return segments.length == 1 && segments[0].toLowerCase() == 'asesor';
}

class SalesCodeStore {
  SalesCodeStore._();

  static Future<void> save(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingCodeKey, code);
    } catch (_) {}
  }

  static Future<String?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return normalizeSalesCode(prefs.getString(_pendingCodeKey));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingCodeKey);
    } catch (_) {}
  }
}

/// Muestra a la persona registrada su código de verificación para el asesor.
/// No muestra nada si la cuenta no llegó por un asesor.
class SalesVerificationOverlay extends StatefulWidget {
  final Widget child;
  const SalesVerificationOverlay({super.key, required this.child});

  @override
  State<SalesVerificationOverlay> createState() =>
      _SalesVerificationOverlayState();
}

class _SalesVerificationOverlayState extends State<SalesVerificationOverlay> {
  String? _code;
  bool _dismissed = false;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
    // Revisa de nuevo cada minuto: el conductor recibe el código al ser aprobado.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_code == null) unawaited(_check());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      await SalesCodeIntake.attachPending();
      await supabase.rpc('sales_check_my_registration');
      final value = await supabase.rpc('sales_my_verification_code');
      if (!mounted) return;
      final code = value?.toString().trim() ?? '';
      if (code.length == 4) setState(() => _code = code);
    } catch (_) {
      // Sin asesor o sin conexión: no se muestra nada.
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (code != null && !_dismissed)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFF0B1739),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Registro completado',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Muestra este código a tu asesor:',
                              style: TextStyle(color: Color(0xFFDCEAFF)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              code.split('').join(' '),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => setState(() => _dismissed = true),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Portal del asesor: su QR, totales y las personas que registró.
class SalesAdvisorPortalPage extends StatefulWidget {
  final VoidCallback onExit;
  const SalesAdvisorPortalPage({super.key, required this.onExit});

  @override
  State<SalesAdvisorPortalPage> createState() => _SalesAdvisorPortalPageState();
}

class _SalesAdvisorPortalPageState extends State<SalesAdvisorPortalPage> {
  late Future<({Map<String, dynamic> me, List<Map<String, dynamic>> people})>
      _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({Map<String, dynamic> me, List<Map<String, dynamic>> people})>
      _load() async {
    final me = await supabase.rpc('sales_advisor_me');
    final people = await supabase.rpc('sales_advisor_people');
    return (
      me: Map<String, dynamic>.from(me as Map),
      people: (people as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
    );
  }

  void _reload() => setState(() => _future = _load());

  static const _stages = <String, (String, Color)>{
    'cuenta_creada': ('Cuenta creada · falta terminar', Color(0xFF8A6D00)),
    'esperando_aprobacion': ('Conductor · esperando aprobación', Color(0xFF8A6D00)),
    'falta_foto': ('Registro completado · falta la foto', Color(0xFF0B57D0)),
    'foto_en_revision': ('Foto en revisión', Color(0xFF0B57D0)),
    'foto_rechazada': ('Foto rechazada · envíala otra vez', Color(0xFFB3261E)),
    'aprobado_para_pago': ('Aprobado · por pagar', Color(0xFF1B7F3B)),
    'pagado': ('Pagado', Color(0xFF1B7F3B)),
    'en_revision': ('En revisión de Express', Color(0xFFB3261E)),
  };

  String _money(dynamic amount, [dynamic currency]) {
    final value = num.tryParse(amount?.toString() ?? '') ?? 0;
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return '${currency == null || currency == 'BOB' ? 'Bs' : currency} $text';
  }

  String _error(Object error) {
    if (error is PostgrestException) return error.message;
    return 'No se pudo completar. Intenta de nuevo.';
  }

  Future<void> _sendEvidence(String advisorId, Map<String, dynamic> row) async {
    if (_busy) return;
    final codeController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Foto de ${row['first_name'] ?? 'la persona'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escribe el código de 4 dígitos que aparece en la app de la '
              'persona. Después tómale una foto con su teléfono mostrando '
              'ese código.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              autofocus: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Código'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (codeController.text.trim().length == 4) {
                Navigator.pop(dialogContext, codeController.text.trim());
              }
            },
            child: const Text('Tomar foto'),
          ),
        ],
      ),
    );
    codeController.dispose();
    if (code == null || !mounted) return;

    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (photo == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final bytes = await photo.readAsBytes();
      final path =
          '$advisorId/${row['attribution_id']}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('sales-evidence').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      await supabase.rpc('sales_submit_evidence', params: {
        'p_attribution_id': row['attribution_id'],
        'p_code': code,
        'p_storage_path': path,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto enviada. Express la revisará.')),
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_error(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _total(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F2)),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0B1739),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF5B6577)),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Página del asesor'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: widget.onExit,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'Esta cuenta no está registrada como asesor de ventas. '
                      'Pide a Express que la active.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data!;
          final advisor = Map<String, dynamic>.from(data.me['advisor'] as Map);
          final totals = Map<String, dynamic>.from(data.me['totals'] as Map);
          final code = advisor['code'].toString();
          final link = '$salesPublicBaseUrl/r/$code';

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F2)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Hola, ${advisor['name']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Pide a la persona que escanee este QR para registrarse.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF5B6577)),
                      ),
                      const SizedBox(height: 12),
                      QrImageView(data: link, size: 210),
                      const SizedBox(height: 6),
                      SelectableText(
                        'Código: $code',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: link));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Enlace copiado.')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiar enlace'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _total('Registrados', '${totals['attributed'] ?? 0}'),
                    const SizedBox(width: 8),
                    _total('Completados', '${totals['registered'] ?? 0}'),
                    const SizedBox(width: 8),
                    _total('Por pagar', _money(totals['to_pay'])),
                    const SizedBox(width: 8),
                    _total('Pagado', _money(totals['paid'])),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Personas registradas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (data.people.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Todavía no hay registros con tu código.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF5B6577)),
                    ),
                  ),
                for (final row in data.people)
                  _personCard(advisor['id'].toString(), row),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _personCard(String advisorId, Map<String, dynamic> row) {
    final stageKey = row['stage']?.toString() ?? '';
    final stage = _stages[stageKey] ?? (stageKey, const Color(0xFF5B6577));
    final isDriver = row['role'] == 'driver';
    final canSendPhoto =
        stageKey == 'falta_foto' || stageKey == 'foto_rechazada';
    final name = (row['first_name']?.toString().trim().isNotEmpty ?? false)
        ? row['first_name'].toString()
        : 'Sin nombre';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDriver ? Icons.two_wheeler : Icons.person,
                color: const Color(0xFF0B57D0),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$name · ${isDriver ? 'Conductor' : 'Pasajero'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (row['amount'] != null)
                Text(
                  _money(row['amount'], row['currency']),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            stage.$1,
            style: TextStyle(color: stage.$2, fontWeight: FontWeight.w700),
          ),
          if (canSendPhoto) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : () => _sendEvidence(advisorId, row),
              icon: const Icon(Icons.photo_camera, size: 18),
              label: const Text('Enviar foto con código'),
            ),
          ],
        ],
      ),
    );
  }
}
