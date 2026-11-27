import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/express_service.dart';

/// Verificación del teléfono por SMS (Unimatrix, solo Bolivia +591).
/// Se muestra únicamente a cuentas nuevas con teléfono de Bolivia cuando el
/// interruptor del servidor está activo.
class PhoneVerificationPage extends StatefulWidget {
  final ExpressService service;
  final String? initialPhone;
  final VoidCallback onSignOut;

  const PhoneVerificationPage({
    super.key,
    required this.service,
    required this.initialPhone,
    required this.onSignOut,
  });

  @override
  State<PhoneVerificationPage> createState() => _PhoneVerificationPageState();
}

class _PhoneVerificationPageState extends State<PhoneVerificationPage> {
  static const _dial = '591';

  late final TextEditingController phone;
  final code = TextEditingController();
  bool sending = false;
  bool verifying = false;
  bool codeSent = false;
  int cooldown = 0;
  String? message;
  bool providerFailed = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    var digits = (widget.initialPhone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith(_dial)) digits = digits.substring(_dial.length);
    phone = TextEditingController(text: digits);
  }

  @override
  void dispose() {
    timer?.cancel();
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  String get _fullPhone =>
      '+$_dial${phone.text.replaceAll(RegExp(r'\D'), '')}';

  void _startCooldown(int seconds) {
    timer?.cancel();
    setState(() => cooldown = seconds);
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => cooldown = cooldown > 0 ? cooldown - 1 : 0);
      if (cooldown == 0) t.cancel();
    });
  }

  Future<void> _send() async {
    if (sending || cooldown > 0) return;
    final digits = phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) {
      setState(() => message = 'Escribe tu número de 8 dígitos de Bolivia.');
      return;
    }
    setState(() {
      sending = true;
      message = null;
    });
    final result = await widget.service.phoneOtp('send', phone: _fullPhone);
    if (!mounted) return;
    setState(() {
      sending = false;
      providerFailed = const {'provider_send_failed', 'provider_not_configured', 'internal_error'}
          .contains(result['code']);
      if (result['ok'] == true) {
        codeSent = true;
        message = 'Te enviamos un código por SMS al $_fullPhone.';
      } else {
        message = result['message']?.toString() ??
            'No se pudo enviar el código.';
      }
    });
    if (result['ok'] == true) {
      _startCooldown((result['resend_in'] as num?)?.toInt() ?? 60);
    } else if (result['code'] == 'resend_cooldown') {
      _startCooldown(60);
    }
  }

  Future<void> _verify() async {
    if (verifying) return;
    final digits = code.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) {
      setState(() => message = 'Escribe el código que recibiste.');
      return;
    }
    setState(() {
      verifying = true;
      message = null;
    });
    final result = await widget.service
        .phoneOtp('verify', phone: _fullPhone, code: digits);
    if (!mounted) return;
    if (result['ok'] == true && result['verified'] == true) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      verifying = false;
      message = result['message']?.toString() ?? 'No se pudo verificar.';
      if (result['code'] == 'code_expired' ||
          result['code'] == 'too_many_attempts' ||
          result['code'] == 'no_challenge') {
        codeSent = false;
        code.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.sms_outlined,
                        size: 54, color: Color(0xFF2563EB)),
                    const SizedBox(height: 14),
                    const Text(
                      'Verifica tu teléfono',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Te enviaremos un código por SMS para confirmar que el número es tuyo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF667085), height: 1.4),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: phone,
                      enabled: !codeSent && !sending,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Tu número de Bolivia',
                        prefixText: '+591  ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (codeSent) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: code,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Código del SMS',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _verify(),
                      ),
                    ],
                    if (message != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFF475467), height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (!codeSent)
                      FilledButton(
                        onPressed: sending ? null : _send,
                        child: Text(sending ? 'Enviando…' : 'Enviar código'),
                      )
                    else ...[
                      FilledButton(
                        onPressed: verifying ? null : _verify,
                        child: Text(verifying ? 'Verificando…' : 'Verificar'),
                      ),
                      TextButton(
                        onPressed: (sending || cooldown > 0) ? null : _send,
                        child: Text(cooldown > 0
                            ? 'Reenviar código en $cooldown s'
                            : 'Reenviar código'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          codeSent = false;
                          code.clear();
                          message = null;
                        }),
                        child: const Text('Cambiar número'),
                      ),
                    ],
                    if (providerFailed)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('No llega el SMS · continuar por ahora'),
                      ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: widget.onSignOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
