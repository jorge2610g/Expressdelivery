import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(const ExpressLoginPreviewApp());
}

class ExpressLoginPreviewApp extends StatelessWidget {
  const ExpressLoginPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B57D0),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Express',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD9E0EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD9E0EA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF0B57D0), width: 1.6),
          ),
        ),
      ),
      home: const _PreviewAuthGate(),
    );
  }
}

class _PreviewAuthGate extends StatelessWidget {
  const _PreviewAuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) return const ModernLoginPage();
        return const _LoggedInPreview();
      },
    );
  }
}

class ModernLoginPage extends StatefulWidget {
  const ModernLoginPage({super.key});

  @override
  State<ModernLoginPage> createState() => _ModernLoginPageState();
}

class _ModernLoginPageState extends State<ModernLoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();

  bool register = false;
  bool busy = false;
  bool obscurePassword = true;

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();

    if (email.text.trim().isEmpty || password.text.isEmpty) {
      _message('Ingresa tu correo y contraseña.');
      return;
    }

    if (register && name.text.trim().isEmpty) {
      _message('Ingresa tu nombre completo.');
      return;
    }

    setState(() => busy = true);
    try {
      if (register) {
        final response = await supabase.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: 'https://jorge2610g.github.io/Expressdelivery/',
          data: {
            'full_name': name.text.trim(),
            'phone': phone.text.trim(),
          },
        );

        if (mounted && response.session == null) {
          _message('Cuenta creada. Revisa tu correo o inicia sesión.');
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
    } catch (e) {
      _message('No se pudo completar la operación. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    final value = email.text.trim();
    if (value.isEmpty) {
      _message('Escribe primero tu correo.');
      return;
    }

    try {
      await supabase.auth.resetPasswordForEmail(
        value,
        redirectTo: 'https://jorge2610g.github.io/Expressdelivery/',
      );
      _message('Te enviamos un enlace para recuperar tu contraseña.');
    } on AuthException catch (e) {
      _message(e.message);
    } catch (_) {
      _message('No se pudo enviar el correo de recuperación.');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 900;
            if (desktop) {
              return Row(
                children: [
                  const Expanded(flex: 11, child: _BrandPanel()),
                  Expanded(flex: 9, child: _formArea()),
                ],
              );
            }

            return _mobileLayout();
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
          _loginCard(),
          const SizedBox(height: 20),
          const _TrustFooter(),
        ],
      ),
    );
  }

  Widget _formArea() {
    return Container(
      color: const Color(0xFFF5F7FB),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(42),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Column(
            children: [
              _loginCard(),
              const SizedBox(height: 22),
              const _TrustFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loginCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE4E9F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            register ? 'Crea tu cuenta' : 'Bienvenido de nuevo',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            register
                ? 'Regístrate para pedir viajes y envíos desde una sola app.'
                : 'Ingresa para continuar con tus viajes y entregas.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF667085),
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 26),
          if (register) ...[
            TextField(
              controller: name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 14),
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
          const SizedBox(height: 14),
          TextField(
            controller: password,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => busy ? null : submit(),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: obscurePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                onPressed: () => setState(() => obscurePassword = !obscurePassword),
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          if (!register) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : resetPassword,
                child: const Text('¿Olvidaste tu contraseña?'),
              ),
            ),
          ] else
            const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: busy ? null : submit,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Text(
                      register ? 'Crear cuenta' : 'Ingresar',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  register ? '¿Ya tienes cuenta?' : '¿Eres nuevo en Express?',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                      ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 12),
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
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(register ? 'Iniciar sesión' : 'Crear una cuenta'),
            ),
          ),
        ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LogoMark(light: true),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            child: const Text(
              'VIAJES + DELIVERY',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Muévete. Envía.\nTodo en Express.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 46,
              height: 1.05,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.4,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Una sola cuenta para pedir un viaje, enviar un paquete y seguir cada servicio en tiempo real.',
            style: TextStyle(
              color: Color(0xFFDCEAFF),
              fontSize: 17,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 34),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FeaturePill(icon: Icons.local_taxi_rounded, text: 'Viajes'),
              _FeaturePill(icon: Icons.local_shipping_rounded, text: 'Delivery'),
              _FeaturePill(icon: Icons.shield_outlined, text: 'Seguro'),
            ],
          ),
          const Spacer(),
          const Text(
            'Express · Movilidad y entregas en una sola plataforma',
            style: TextStyle(color: Color(0xFFBFD8FF), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _LogoMark(light: false),
        SizedBox(height: 10),
        Text(
          'Viajes y delivery en una sola app',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF667085), fontSize: 14),
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
          child: Icon(
            Icons.bolt_rounded,
            color: light ? const Color(0xFF0B57D0) : Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Express',
          style: TextStyle(
            color: light ? Colors.white : const Color(0xFF101828),
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeaturePill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TrustFooter extends StatelessWidget {
  const _TrustFooter();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 15, color: Color(0xFF98A2B3)),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'Acceso protegido con autenticación segura',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _LoggedInPreview extends StatelessWidget {
  const _LoggedInPreview();

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, size: 72, color: Color(0xFF12B76A)),
                const SizedBox(height: 18),
                Text(
                  'Sesión iniciada',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  user?.email ?? 'Usuario de Express',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF667085)),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Supabase.instance.client.auth.signOut(),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Cerrar sesión'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
