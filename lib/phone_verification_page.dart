import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'phone_utils.dart';
import 'services/express_service.dart';

class PhoneVerificationPage extends StatefulWidget {
  final ExpressService service;
  final String? initialPhone;
  final bool driver;

  const PhoneVerificationPage({
    super.key,
    required this.service,
    this.initialPhone,
    this.driver = false,
  });

  @override
  State<PhoneVerificationPage> createState() => _PhoneVerificationPageState();
}

class _PhoneVerificationPageState extends State<PhoneVerificationPage> {
  late String countryCode;
  late TextEditingController phoneController;
  final codeController = TextEditingController();

  bool sending = false;
  bool verifying = false;
  bool codeSent = false;
  String? requestedPhone;

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    countryCode = expressPhoneCountryFromNumber(widget.initialPhone);
    phoneController =
        TextEditingController(text: expressLocalPhone(widget.initialPhone));
  }

  @override
  void dispose() {
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String? _normalizedPhone() {
    final value = expressNormalizePhone(countryCode, phoneController.text);
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final dialDigits =
        expressPhoneDialCode(countryCode).replaceAll(RegExp(r'\D'), '');
    final localDigits = digits.substring(dialDigits.length);
    if (localDigits.length < 7) return null;
    return value;
  }

  Future<void> _sendCode() async {
    final enabled = await widget.service.phoneVerificationEnabledForMode(
      widget.driver ? 'driver' : 'passenger',
      forceRefresh: true,
    );
    if (!enabled) {
      _message(
        'La verificación SMS está desactivada temporalmente por administración.',
      );
      return;
    }

    final phone = _normalizedPhone();
    if (phone == null) {
      _message('Ingresa un número de teléfono válido.');
      return;
    }
    setState(() => sending = true);
    try {
      await supabase.auth.updateUser(UserAttributes(phone: phone));
      if (!mounted) return;
      setState(() {
        codeSent = true;
        requestedPhone = phone;
        codeController.clear();
      });
      _message('Enviamos un código de 6 dígitos a ' + phone + '.');
    } on AuthException catch (e) {
      _message(e.message.isEmpty ? 'No se pudo enviar el código SMS.' : e.message);
    } catch (_) {
      _message(
        'No se pudo enviar el código. Verifica que el servicio SMS esté disponible.',
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _verify() async {
    final phone = requestedPhone ?? _normalizedPhone();
    final code = codeController.text.replaceAll(RegExp(r'\D'), '');
    if (phone == null || code.length != 6) {
      _message('Ingresa el código de 6 dígitos.');
      return;
    }

    setState(() => verifying = true);
    try {
      await supabase.auth.verifyOTP(
        type: OtpType.phoneChange,
        phone: phone,
        token: code,
      );
      await widget.service.updateVerifiedPhone(
        phone: phone,
        countryCode: countryCode,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AuthException catch (e) {
      _message(e.message);
    } catch (_) {
      _message('No pudimos verificar el código. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = sending || verifying;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Verificar teléfono',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(
              Icons.verified_user_outlined,
              size: 62,
              color: Color(0xFF2563EB),
            ),
            const SizedBox(height: 14),
            const Text(
              'Protege tu cuenta',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'El código de país nos permite identificar si tu cuenta pertenece a Chile o Bolivia. Cuando la verificación SMS esté habilitada, te enviaremos un código para confirmar que el número es tuyo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF667085), height: 1.4),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: countryCode,
              decoration: const InputDecoration(
                labelText: 'País',
                prefixIcon: Icon(Icons.public_rounded),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'CL',
                  child: Text('Chile · +56'),
                ),
                DropdownMenuItem(
                  value: 'BO',
                  child: Text('Bolivia · +591'),
                ),
              ],
              onChanged: busy
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        countryCode = value;
                        codeSent = false;
                        requestedPhone = null;
                        codeController.clear();
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              enabled: !busy,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\s()-]')),
              ],
              onChanged: (_) {
                if (codeSent) {
                  setState(() {
                    codeSent = false;
                    requestedPhone = null;
                    codeController.clear();
                  });
                }
              },
              decoration: InputDecoration(
                labelText: 'Número de teléfono',
                prefixText: expressPhoneDialCode(countryCode) + ' ',
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: busy ? null : _sendCode,
                icon: sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sms_outlined),
                label: Text(codeSent ? 'Reenviar código' : 'Enviar código'),
              ),
            ),
            if (codeSent) ...[
              const SizedBox(height: 24),
              TextField(
                controller: codeController,
                enabled: !busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'Código de verificación',
                  counterText: '',
                  prefixIcon: Icon(Icons.password_rounded),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: busy ? null : _verify,
                  icon: verifying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_rounded),
                  label: const Text('Verificar número'),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Si cambias tu número, el nuevo número deberá verificarse antes de quedar asociado a tu perfil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
