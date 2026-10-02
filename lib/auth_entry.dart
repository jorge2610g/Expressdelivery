import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_client.dart';

const _googleAuthEnabled = bool.fromEnvironment(
  'EXPRESS_GOOGLE_AUTH_ENABLED',
  defaultValue: false,
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
  String accountType = 'passenger';

  SupabaseClient get supabase => Supabase.instance.client;

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

  Future<String> _authRedirectUrl() async {
    if (kIsWeb) {
      return 'https://jorge2610g.github.io/Expressdelivery/';
    }
    final info = await PackageInfo.fromPlatform();
    return '${info.packageName}://login-callback/';
  }

  Future<void> _signInWithGoogle() async {
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      final redirectTo = await _authRedirectUrl();
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
    } catch (_) {
      _message('No se pudo iniciar sesión con Google. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
    if (register && password.text.length < 8) {
      _message('Usa una contraseña de al menos 8 caracteres.');
      return;
    }

    setState(() => busy = true);
    try {
      if (register) {
        final redirectTo = await _authRedirectUrl();
        final response = await supabase.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: redirectTo,
          data: {
            'full_name': name.text.trim(),
            'phone': phone.text.trim(),
            'account_type': accountType,
            'active_mode': accountType,
          },
        );

        if (!mounted) return;
        if (response.session == null) {
          _message(
            accountType == 'driver'
                ? 'Cuenta de conductor creada. Confirma tu correo; tu perfil quedará pendiente de aprobación.'
                : 'Cuenta de cliente creada. Confirma tu correo para ingresar.',
          );
          setState(() => register = false);
        }
      } else {
        await supabase.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on AuthException catch (e) {
      _message(e.message);
    } catch (_) {
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
      final redirectTo = await _authRedirectUrl();
      await supabase.auth.resetPasswordForEmail(
        value,
        redirectTo: redirectTo,
      );
      _message(
        'Te enviamos un enlace de recuperación. Revisa también la carpeta de spam.',
      );
    } on AuthException catch (e) {
      _message(e.message);
    } catch (_) {
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
                ? 'Elige cómo vas a usar Express y crea tu acceso.'
                : 'Ingresa con tu cuenta de cliente o conductor.',
            style: TextStyle(color: bodyColor, height: 1.4),
          ),
          const SizedBox(height: 24),
          if (register) ...[
            Text(
              'Tipo de cuenta',
              style: TextStyle(
                color: titleColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _AccountTypeCard(
                    selected: accountType == 'passenger',
                    icon: Icons.person_rounded,
                    title: 'Cliente',
                    subtitle: 'Pedir viajes',
                    onTap: () => setState(() => accountType = 'passenger'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AccountTypeCard(
                    selected: accountType == 'driver',
                    icon: Icons.drive_eta_rounded,
                    title: 'Conductor',
                    subtitle: 'Viajes',
                    onTap: () => setState(() => accountType = 'driver'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
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
                      }),
              child: Text(register ? 'Ya tengo cuenta' : 'Crear una cuenta'),
            ),
          ),
          if (register && accountType == 'driver') ...[
            const SizedBox(height: 14),
            Text(
              'Los conductores deben completar licencia y vehículo. La cuenta queda pendiente hasta ser aprobada.',
              style: TextStyle(
                color: bodyColor,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
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
    try {
      await supabase.auth.updateUser(
        UserAttributes(password: value),
      );
      _message('Contraseña actualizada correctamente.');
      await Future<void>.delayed(const Duration(milliseconds: 650));
      await supabase.auth.signOut();
      widget.onDone();
    } on AuthException catch (e) {
      _message(e.message);
    } catch (_) {
      _message('No se pudo actualizar la contraseña. Solicita un enlace nuevo.');
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

class _AccountTypeCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AccountTypeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = selected
        ? (dark ? const Color(0xFF17315E) : const Color(0xFFEAF2FF))
        : (dark ? const Color(0xFF1D2026) : const Color(0xFFF8FAFC));
    final border = selected
        ? (dark ? const Color(0xFF6EA8FF) : const Color(0xFF0B57D0))
        : (dark ? const Color(0xFF383E48) : const Color(0xFFD9E0EA));
    final titleColor = dark ? const Color(0xFFF8FAFC) : const Color(0xFF101828);
    final subtitleColor = dark ? const Color(0xFFB9C0CC) : const Color(0xFF667085);
    final iconColor = dark ? const Color(0xFF9CC2FF) : const Color(0xFF0B57D0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: titleColor,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: subtitleColor,
              ),
            ),
          ],
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
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: light ? Colors.white : const Color(0xFF0B57D0),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(Icons.bolt_rounded, color: light ? const Color(0xFF0B57D0) : Colors.white, size: 30),
        ),
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
