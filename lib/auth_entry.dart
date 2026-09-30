import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_client.dart';

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
    try {
      await supabase.auth.resetPasswordForEmail(
        value,
        redirectTo: 'https://jorge2610g.github.io/Expressdelivery/',
      );
      _message('Te enviamos un enlace para recuperar tu contraseña.');
    } on AuthException catch (e) {
      _message(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE4E9F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 30, offset: Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            register ? 'Crea tu cuenta' : 'Bienvenido a Express',
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            register
                ? 'Elige cómo vas a usar Express y crea tu acceso.'
                : 'Ingresa con tu cuenta de cliente o conductor.',
            style: const TextStyle(color: Color(0xFF667085), height: 1.4),
          ),
          const SizedBox(height: 24),
          if (register) ...[
            const Text('Tipo de cuenta', style: TextStyle(fontWeight: FontWeight.w800)),
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
            const Text(
              'Los conductores deben completar licencia y vehículo. La cuenta queda pendiente hasta ser aprobada.',
              style: TextStyle(color: Color(0xFF667085), fontSize: 12, height: 1.4),
            ),
          ],
        ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF0B57D0) : const Color(0xFFD9E0EA),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF0B57D0)),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF667085))),
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
    return const Column(
      children: [
        _LogoMark(light: false),
        SizedBox(height: 10),
        Text('Viajes en una sola app', style: TextStyle(color: Color(0xFF667085))),
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
          child: Icon(Icons.bolt_rounded, color: light ? const Color(0xFF0B57D0) : Colors.white, size: 30),
        ),
        const SizedBox(width: 12),
        Text(
          'Express',
          style: TextStyle(
            color: light ? Colors.white : const Color(0xFF101828),
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
