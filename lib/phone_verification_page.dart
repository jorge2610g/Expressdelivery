import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/runtime_channel.dart';
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
  String countryCode = 'CL';
  late TextEditingController phoneController;
  final codeController = TextEditingController();

  List<Map<String, dynamic>> countries = const [];
  bool loadingCountries = true;
  bool sending = false;
  bool verifying = false;
  bool codeSent = false;
  String? requestedPhone;

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    phoneController = TextEditingController();
    _loadCountries();
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

  Future<void> _loadCountries() async {
    try {
      var rows = await widget.service.phoneCountryCatalog();
      if (rows.isEmpty) {
        rows = expressPhoneDialCodes.entries
            .map(
              (entry) => <String, dynamic>{
                'country_code': entry.key,
                'name': entry.key == 'CL' ? 'Chile' : 'Bolivia',
                'calling_code': entry.value,
              },
            )
            .toList();
      }

      final initial = (widget.initialPhone ?? '').trim();
      Map<String, dynamic>? selected;
      for (final row in rows) {
        final dial = row['calling_code']?.toString() ?? '';
        if (dial.isNotEmpty && initial.startsWith(dial)) {
          if (selected == null ||
              dial.length >
                  (selected['calling_code']?.toString().length ?? 0)) {
            selected = row;
          }
        }
      }
      selected ??= rows.first;

      final selectedCode =
          selected['country_code']?.toString().toUpperCase() ?? 'CL';
      final selectedDial = selected['calling_code']?.toString() ?? '+56';
      final normalizedInitial =
          initial.replaceAll(RegExp(r'[\s()-]'), '');
      final localPhone = normalizedInitial.startsWith(selectedDial)
          ? normalizedInitial.substring(selectedDial.length)
          : normalizedInitial.replaceFirst(RegExp(r'^\+'), '');

      if (!mounted) return;
      setState(() {
        countries = rows;
        countryCode = selectedCode;
        phoneController.text = localPhone;
        loadingCountries = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        countries = const [
          {
            'country_code': 'CL',
            'name': 'Chile',
            'calling_code': '+56',
          },
          {
            'country_code': 'BO',
            'name': 'Bolivia',
            'calling_code': '+591',
          },
        ];
        countryCode = expressPhoneCountryFromNumber(widget.initialPhone);
        phoneController.text = expressLocalPhone(widget.initialPhone);
        loadingCountries = false;
      });
    }
  }

  Map<String, dynamic>? get _selectedCountry {
    for (final row in countries) {
      if (row['country_code']?.toString().toUpperCase() == countryCode) {
        return row;
      }
    }
    return countries.isEmpty ? null : countries.first;
  }

  String get _dialCode =>
      _selectedCountry?['calling_code']?.toString() ??
      expressPhoneDialCode(countryCode);

  String? _normalizedPhone() {
    var digits = phoneController.text.replaceAll(RegExp(r'\D'), '');
    final dialDigits = _dialCode.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith(dialDigits)) {
      digits = digits.substring(dialDigits.length);
    }
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    final normalized = _dialCode + digits;
    final normalizedDigits = normalized.replaceAll(RegExp('[^0-9]'), '');
    if (!normalized.startsWith('+') ||
        normalizedDigits.length < 7 ||
        normalizedDigits.length > 15) {
      return null;
    }
    return normalized;
  }

  Future<void> _sendCode() async {
    final enabled = await widget.service.phoneVerificationEnabledForMode(
      widget.driver ? 'driver' : 'passenger',
      forceRefresh: true,
    );
    if (!enabled) {
      _message(
        ExpressRuntimeChannel.technicalOr(
          production:
              'La verificación de teléfono todavía no está habilitada para Producción.',
          preview:
              'La verificación SMS está desactivada temporalmente por administración.',
        ),
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
      _message('Enviamos un código de 6 dígitos a $phone.');
    } on AuthException catch (e) {
      _message(
        ExpressRuntimeChannel.technicalOr(
          production: 'No se pudo enviar el código SMS. Intenta nuevamente.',
          preview: e.message.isEmpty
              ? 'No se pudo enviar el código SMS.'
              : e.message,
        ),
      );
    } catch (_) {
      _message(
        ExpressRuntimeChannel.technicalOr(
          production:
              'No se pudo enviar el código. Intenta nuevamente más tarde.',
          preview:
              'No se pudo enviar el código. Verifica que el proveedor SMS esté configurado.',
        ),
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
        countryCode: countryCode,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AuthException catch (e) {
      _message(
        ExpressRuntimeChannel.technicalOr(
          production:
              'No pudimos verificar el código. Revisa los datos e intenta nuevamente.',
          preview: e.message,
        ),
      );
    } catch (e) {
      _message(
        ExpressRuntimeChannel.technicalOr(
          production:
              'El SMS fue confirmado, pero no pudimos sincronizar tu perfil. Intenta nuevamente.',
          preview: 'No pudimos completar la verificación: $e',
        ),
      );
    } finally {
      if (mounted) setState(() => verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = sending || verifying || loadingCountries;
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
              'Selecciona tu país, ingresa tu número y confirma el código SMS. Solo se muestran países activos de Express con prefijo telefónico configurado.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF667085),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'phone-country-' + countryCode + '-' + countries.length.toString(),
              ),
              initialValue: countries.any(
                (row) =>
                    row['country_code']?.toString().toUpperCase() ==
                    countryCode,
              )
                  ? countryCode
                  : null,
              decoration: const InputDecoration(
                labelText: 'País',
                prefixIcon: Icon(Icons.public_rounded),
              ),
              items: countries
                  .map(
                    (row) => DropdownMenuItem<String>(
                      value: row['country_code']?.toString().toUpperCase(),
                      child: Text(
                        '${row['name'] ?? row['country_code']} · ${row['calling_code'] ?? ''}',
                      ),
                    ),
                  )
                  .toList(),
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
                prefixText: '$_dialCode ',
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: busy || countries.isEmpty ? null : _sendCode,
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
