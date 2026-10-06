import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth_redirect.dart';
import 'core/runtime_access.dart';
import 'core/runtime_channel.dart';
import 'core/supabase_client.dart';
import 'express_branding.dart';
import 'phone_utils.dart';

const _googleAuthEnabled = bool.fromEnvironment(
  'EXPRESS_GOOGLE_AUTH_ENABLED',
  defaultValue: true,
);

class ExpressAuthPage extends StatefulWidget {
  const ExpressAuthPage({super.key});

  @override
  State<ExpressAuthPage> createState() => _ExpressAuthPageState();
}

class _ExpressAuthPageState extends State<ExpressAuthPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();

  bool register = false;
  bool busy = false;
  bool obscurePassword = true;
  bool accountLocked = false;
  int? remainingAttempts;
  String phoneCountryCode = 'CL';
  List<Map<String, dynamic>> phoneCountries = const [
    {'country_code': 'CL', 'name': 'Chile', 'calling_code': '+56'},
    {'country_code': 'BO', 'name': 'Bolivia', 'calling_code': '+591'},
  ];

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadPhoneCountries();
  }

  Future<void> _loadPhoneCountries() async {
    try {
      final value = await supabase.rpc('phone_country_catalog');
      if (value is! List) return;
      final rows = value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where(
            (row) =>
                row['country_code']?.toString().isNotEmpty == true &&
                row['calling_code']?.toString().isNotEmpty == true,
          )
          .toList();
      if (rows.isEmpty || !mounted) return;
      final hasCurrent = rows.any(
        (row) =>
            row['country_code']?.toString().toUpperCase() ==
            phoneCountryCode,
      );
      setState(() {
        phoneCountries = rows;
        if (!hasCurrent) {
          phoneCountryCode =
              rows.first['country_code']?.toString().toUpperCase() ?? 'CL';
        }
      });
    } catch (_) {
      // Keep the safe CL/BO fallback already rendered.
    }
  }

  String _phoneDialCode(String code) {
    for (final row in phoneCountries) {
      if (row['country_code']?.toString().toUpperCase() ==
          code.toUpperCase()) {
        return row['calling_code']?.toString() ?? '+56';
      }
    }
    return expressPhoneDialCode(code);
  }

  String _normalizeRegistrationPhone() {
    var digits = phone.text.replaceAll(RegExp(r'\D'), '');
    final dial = _phoneDialCode(phoneCountryCode);
    final dialDigits = dial.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith(dialDigits)) {
      digits = digits.substring(dialDigits.length);
    }
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return dial + digits;
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _authRedirectUrl() {
    return expressAuthRedirectUrl(isWeb: kIsWeb);
  }

  Future<void> _openPolicy(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
    if (!ok) {
      _message('No se pudo abrir el enlace.');
    }
  }

  Future<void> _signInWithGoogle() async {
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      final redirectTo = _authRedirectUrl();
      final started = await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        authScreenLaunchMode:
            kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
      if (!started) {
        _message('No se pudo abrir el inicio de sesión con Google.');
      }
    } on AuthException catch (e) {
      _message(e.message);
    } catch (error, stack) {
      debugPrint('Express Google OAuth start failed: $error\n$stack');
      _message('No se pudo iniciar sesión con Google. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Map<String, dynamic>> _loginGuardState(String emailValue) async {
    final data = await supabase.rpc(
      'auth_login_guard_state',
      params: {'p_email': emailValue},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> _recordLoginFailure(String emailValue) async {
    final data = await supabase.rpc(
      'auth_login_guard_record_failure',
      params: {'p_email': emailValue},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> _clearLoginGuard() async {
    await supabase.rpc('auth_login_guard_clear_current');
  }

  Future<bool> _validateRuntimeAccess() async {
    final scope = await resolveExpressRuntimeAccess();
    final allowed = scope['allowed'] == true;

    if (allowed) return true;

    final boundEnvironment = scope['bound_environment']?.toString();
    await supabase.auth.signOut();
    ExpressRuntimeChannel.resetToCompiledMode();
    _message(
      ExpressRuntimeChannel.compiledPreviewMode
          ? boundEnvironment == 'production'
              ? 'Esta cuenta ya pertenece a Producción. Usa una cuenta Google de prueba distinta para Express Preview.'
              : 'Esta cuenta no está habilitada para Express Preview.'
          : boundEnvironment == 'preview'
              ? 'Esta cuenta de prueba no está activa para Express Preview.'
              : 'Esta cuenta no está habilitada para esta aplicación.',
    );
    return false;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      _message('Ingresa tu correo y contraseña.');
      return;
    }
    if (register && name.text.trim().isEmpty) {
      _message('Ingresa tu nombre completo.');
      return;
    }
    if (register && phone.text.trim().isEmpty) {
      _message('Ingresa tu número de teléfono.');
      return;
    }
    if (register && password.text.length < 8) {
      _message('Usa una contraseña de al menos 8 caracteres.');
      return;
    }

    setState(() => busy = true);
    try {
      if (register) {
        final redirectTo = _authRedirectUrl();
        final normalizedPhone = _normalizeRegistrationPhone();
        final normalizedDigits =
            normalizedPhone.replaceAll(RegExp('[^0-9]'), '');
        if (!normalizedPhone.startsWith('+') ||
            normalizedDigits.length < 7 ||
            normalizedDigits.length > 15) {
          _message('Ingresa un número de teléfono válido.');
          return;
        }
        final response = await supabase.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: redirectTo,
          data: {
            'full_name': name.text.trim(),
            'phone': normalizedPhone,
            'phone_country_code': phoneCountryCode,
            'account_type': 'passenger',
            'active_mode': 'passenger',
          },
        );

        if (!mounted) return;
        if (response.session == null) {
          _message(
            'Cuenta Express creada. Confirma tu correo para ingresar. '
            'Después verificaremos tu teléfono por SMS antes de entrar a los servicios.',
          );
          setState(() => register = false);
        }
      } else {
        final loginEmail = email.text.trim();
        final guard = await _loginGuardState(loginEmail);
        final isLocked = guard['locked'] == true;

        if (isLocked) {
          if (mounted) {
            setState(() {
              accountLocked = true;
              remainingAttempts = 0;
            });
          }
          _message(
            'Cuenta bloqueada por seguridad. Restablece tu contraseña para reactivar el acceso.',
          );
          return;
        }

        try {
          await supabase.auth.signInWithPassword(
            email: loginEmail,
            password: password.text,
          );
          final runtimeAllowed = await _validateRuntimeAccess();
          if (!runtimeAllowed) return;
          await _clearLoginGuard();
          if (mounted) {
            setState(() {
              accountLocked = false;
              remainingAttempts = null;
            });
          }
        } on AuthException catch (e) {
          if (e.code == 'invalid_credentials') {
            final failure = await _recordLoginFailure(loginEmail);
            final locked = failure['locked'] == true;
            final remaining =
                (failure['remaining_attempts'] as num?)?.toInt() ?? 0;

            if (mounted) {
              setState(() {
                accountLocked = locked;
                remainingAttempts = remaining;
              });
            }

            _message(
              locked
                  ? 'Cuenta bloqueada por seguridad. Restablece tu contraseña para reactivar el acceso.'
                  : remaining == 1
                      ? 'Correo o contraseña incorrectos. Te queda 1 intento.'
                      : 'Correo o contraseña incorrectos. Te quedan $remaining intentos.',
            );
            return;
          }
          rethrow;
        }
      }
    } on AuthException catch (e) {
      _message(
        e.code == 'email_not_confirmed'
            ? 'Confirma tu correo antes de iniciar sesión.'
            : 'No se pudo iniciar sesión. Revisa tus datos e intenta nuevamente.',
      );
    } catch (error, stack) {
      debugPrint('Express auth operation failed: $error\n$stack');
      _message('No se pudo completar la operación. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final value = email.text.trim();
    if (value.isEmpty) {
      _message('Escribe primero tu correo.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      final redirectTo = _authRedirectUrl();
      await supabase.auth.resetPasswordForEmail(
        value,
        redirectTo: redirectTo,
      );
      _message(
        'Si el correo está registrado, recibirás un enlace seguro para restablecer tu contraseña y reactivar la cuenta. Revisa también spam.',
      );
    } on AuthException catch (e) {
      _message(e.message);
    } catch (error, stack) {
      debugPrint('Express password recovery failed: $error\n$stack');
      _message('No se pudo enviar el correo de recuperación. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0F1115) : const Color(0xFFF5F7FB),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 900;
            return desktop
                ? Row(
                    children: [
                      const Expanded(flex: 11, child: _BrandPanel()),
                      Expanded(flex: 9, child: _formArea()),
                    ],
                  )
                : _mobileLayout();
          },
        ),
      ),
    );
  }

  Widget _mobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
      child: Column(
        children: [
          const _CompactBrand(),
          const SizedBox(height: 28),
          _authCard(),
        ],
      ),
    );
  }

  Widget _formArea() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(42),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _authCard(),
        ),
      ),
    );
  }

  Widget _authCard() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = dark ? const Color(0xFFF8FAFC) : const Color(0xFF101828);
    final bodyColor = dark ? const Color(0xFFB9C0CC) : const Color(0xFF667085);
    final cardColor = dark ? const Color(0xFF17191E) : Colors.white;
    final borderColor = dark ? const Color(0xFF2B2F36) : const Color(0xFFE4E9F0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x66000000) : const Color(0x12000000),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            register ? 'Crea tu cuenta' : 'Bienvenido a Express',
            style: TextStyle(
              color: titleColor,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            register
                ? 'Crea una sola cuenta Express. Luego podrás activar el modo Conductor desde tu perfil.'
                : 'Ingresa con tu cuenta Express.',
            style: TextStyle(color: bodyColor, height: 1.4),
          ),
          const SizedBox(height: 24),
          if (register) ...[
            TextField(
              controller: name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 128,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      'register-phone-country-' +
                          phoneCountryCode +
                          '-' +
                          phoneCountries.length.toString(),
                    ),
                    initialValue: phoneCountryCode,
                    decoration: const InputDecoration(
                      labelText: 'País',
                    ),
                    items: phoneCountries
                        .map(
                          (row) => DropdownMenuItem<String>(
                            value: row['country_code']
                                ?.toString()
                                .toUpperCase(),
                            child: Text(
                              (row['country_code'] ?? '').toString() +
                                  ' ' +
                                  (row['calling_code'] ?? '').toString(),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => phoneCountryCode = value);
                            }
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Teléfono',
                      prefixText:
                          _phoneDialCode(phoneCountryCode) + ' ',
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Correo electrónico',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => busy ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: () => setState(() => obscurePassword = !obscurePassword),
                icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
            ),
          ),
          if (!register)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: dark
                      ? const Color(0xFF9CC2FF)
                      : const Color(0xFF0B57D0),
                ),
                onPressed: busy ? null : _resetPassword,
                child: const Text('¿Olvidaste tu contraseña?'),
              ),
            )
          else
            const SizedBox(height: 20),
          if (!register && accountLocked) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xFF2A1D1D)
                    : const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: dark
                      ? const Color(0xFF6F3838)
                      : const Color(0xFFF3B4AF),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cuenta bloqueada por seguridad',
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Se alcanzaron 3 intentos incorrectos. Para volver a ingresar, restablece tu contraseña desde el correo.',
                    style: TextStyle(color: bodyColor, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: busy ? null : _resetPassword,
                      icon: const Icon(Icons.mark_email_read_outlined),
                      label: const Text('Restablecer y reactivar cuenta'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ] else if (!register && remainingAttempts != null) ...[
            const SizedBox(height: 4),
            Text(
              remainingAttempts == 1
                  ? 'Te queda 1 intento antes del bloqueo.'
                  : 'Te quedan $remainingAttempts intentos antes del bloqueo.',
              style: TextStyle(
                color: bodyColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: busy ? null : _submit,
              child: busy
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.2))
                  : Text(register ? 'Crear cuenta' : 'Ingresar'),
            ),
          ),
          if (!register && _googleAuthEnabled) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'o',
                    style: TextStyle(
                      color: dark
                          ? const Color(0xFFAAB2C0)
                          : const Color(0xFF98A2B3),
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: dark
                      ? const Color(0xFFF1F5F9)
                      : const Color(0xFF101828),
                  side: BorderSide(
                    color: dark
                        ? const Color(0xFF3B424E)
                        : const Color(0xFFD0D5DD),
                  ),
                ),
                onPressed: busy ? null : _signInWithGoogle,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFF4285F4),
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text('Continuar con Google'),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                        register = !register;
                        obscurePassword = true;
                        accountLocked = false;
                        remainingAttempts = null;
                      }),
              child: Text(register ? 'Ya tengo cuenta' : 'Crear una cuenta'),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => _openPolicy(
                    'https://expressviajes.online/privacidad/',
                  ),
                  child: const Text('Privacidad'),
                ),
                Text(
                  '·',
                  style: TextStyle(color: bodyColor),
                ),
                TextButton(
                  onPressed: () => _openPolicy(
                    'https://expressviajes.online/terminos/',
                  ),
                  child: const Text('Términos'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExpressPasswordRecoveryPage extends StatefulWidget {
  final VoidCallback onDone;

  const ExpressPasswordRecoveryPage({
    super.key,
    required this.onDone,
  });

  @override
  State<ExpressPasswordRecoveryPage> createState() =>
      _ExpressPasswordRecoveryPageState();
}

class _ExpressPasswordRecoveryPageState
    extends State<ExpressPasswordRecoveryPage> {
  final password = TextEditingController();
  final confirmation = TextEditingController();

  bool busy = false;
  bool obscurePassword = true;
  bool obscureConfirmation = true;

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final value = password.text;

    if (value.length < 8) {
      _message('La nueva contraseña debe tener al menos 8 caracteres.');
      return;
    }
    if (value != confirmation.text) {
      _message('Las contraseñas no coinciden.');
      return;
    }

    setState(() => busy = true);
    var passwordUpdated = false;
    try {
      await supabase.auth.updateUser(
        UserAttributes(password: value),
      );
      passwordUpdated = true;
      await supabase.rpc('auth_login_guard_clear_current');
      _message('Contraseña actualizada y cuenta reactivada correctamente.');
      await Future<void>.delayed(const Duration(milliseconds: 650));
      await supabase.auth.signOut();
      widget.onDone();
    } on AuthException catch (e) {
      _message(e.message);
    } catch (_) {
      _message(
        passwordUpdated
            ? 'La contraseña cambió, pero no se pudo reactivar el acceso. Abre nuevamente el enlace de recuperación e inténtalo otra vez.'
            : 'No se pudo actualizar la contraseña. Solicita un enlace nuevo.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cancel() async {
    if (busy) return;
    try {
      await supabase.auth.signOut();
    } finally {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF17191E) : Colors.white;
    final borderColor = dark ? const Color(0xFF2B2F36) : const Color(0xFFE4E9F0);
    final titleColor = dark ? const Color(0xFFF8FAFC) : const Color(0xFF101828);
    final bodyColor = dark ? const Color(0xFFB9C0CC) : const Color(0xFF667085);

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0F1115) : const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: dark
                          ? const Color(0x66000000)
                          : const Color(0x12000000),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _LogoMark(light: false),
                    const SizedBox(height: 26),
                    Text(
                      'Crea una contraseña nueva',
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'El enlace de recuperación fue validado. Escribe una contraseña nueva para tu cuenta Express.',
                      style: TextStyle(
                        color: bodyColor,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: password,
                      obscureText: obscurePassword,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Nueva contraseña',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => obscurePassword = !obscurePassword,
                          ),
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: confirmation,
                      obscureText: obscureConfirmation,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => busy ? null : _save(),
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Confirmar contraseña',
                        prefixIcon: const Icon(Icons.lock_reset_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => obscureConfirmation = !obscureConfirmation,
                          ),
                          icon: Icon(
                            obscureConfirmation
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0B57D0),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: dark
                              ? const Color(0xFF293B5F)
                              : const Color(0xFFAFC4F7),
                        ),
                        onPressed: busy ? null : _save,
                        child: busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Text('Guardar nueva contraseña'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: dark
                              ? const Color(0xFF9CC2FF)
                              : const Color(0xFF0B57D0),
                        ),
                        onPressed: busy ? null : _cancel,
                        child: const Text('Cancelar y volver al inicio de sesión'),
                      ),
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

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(54),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF073B8C), Color(0xFF0B57D0), Color(0xFF39A0FF)],
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LogoMark(light: true),
          Spacer(),
          Text(
            'Muévete. Envía.\nTrabaja con Express.',
            style: TextStyle(color: Colors.white, fontSize: 44, height: 1.05, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 18),
          Text(
            'Una sola plataforma para clientes y conductores.',
            style: TextStyle(color: Color(0xFFDCEAFF), fontSize: 17, height: 1.5),
          ),
          Spacer(),
          Text('Express · Viajes', style: TextStyle(color: Color(0xFFBFD8FF))),
        ],
      ),
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        const _LogoMark(light: false),
        const SizedBox(height: 10),
        Text(
          'Viajes en una sola app',
          style: TextStyle(
            color: dark ? const Color(0xFFB9C0CC) : const Color(0xFF667085),
          ),
        ),
      ],
    );
  }
}

class _LogoMark extends StatelessWidget {
  final bool light;
  const _LogoMark({required this.light});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ExpressOfficialLogo(size: 48, radius: 15),
        const SizedBox(width: 12),
        Text(
          'Express',
          style: TextStyle(
            color: light
                ? Colors.white
                : (dark ? const Color(0xFFF8FAFC) : const Color(0xFF101828)),
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
