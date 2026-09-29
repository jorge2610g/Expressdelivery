import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_client.dart';
import 'login_preview.dart';

const appVersionLabel = 'v1.0.5 · build 7';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(const ExpressWebPreview());
}

class ExpressWebPreview extends StatefulWidget {
  const ExpressWebPreview({super.key});

  @override
  State<ExpressWebPreview> createState() => _ExpressWebPreviewState();
}

class _ExpressWebPreviewState extends State<ExpressWebPreview> {
  bool demoMode = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Express Preview',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B57D0)),
      ),
      home: demoMode
          ? _DemoHome(onExit: () => setState(() => demoMode = false))
          : Scaffold(
              body: Stack(
                children: [
                  const Positioned.fill(child: ExpressLoginPreviewApp()),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 22,
                    child: SafeArea(
                      top: false,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 430),
                          child: Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => setState(() => demoMode = true),
                                  icon: const Icon(Icons.play_circle_outline_rounded),
                                  label: const Text('Entrar como demo'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  appVersionLabel,
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DemoHome extends StatelessWidget {
  final VoidCallback onExit;

  const _DemoHome({required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Express · Demo'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(appVersionLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Salir del modo demo',
            onPressed: onExit,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE4E9F0)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            child: Icon(Icons.person_outline_rounded),
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Usuario Demo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                                SizedBox(height: 3),
                                Text('Modo de prueba local · no usa una cuenta real', style: TextStyle(color: Color(0xFF667085))),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 18),
                      Text(
                        'Desde aquí podemos construir y probar el flujo del pasajero sin depender del registro de Supabase mientras corregimos la conexión de Auth.',
                        style: TextStyle(height: 1.45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 620;
                    final cards = [
                      const _ServiceCard(
                        icon: Icons.local_taxi_rounded,
                        title: 'Viajes',
                        subtitle: 'Solicitar un taxi y seguir el viaje.',
                      ),
                      const _ServiceCard(
                        icon: Icons.local_shipping_rounded,
                        title: 'Delivery',
                        subtitle: 'Solicitar una entrega o envío.',
                      ),
                    ];
                    if (wide) {
                      return Row(
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 16),
                          Expanded(child: cards[1]),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        cards[0],
                        const SizedBox(height: 14),
                        cards[1],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: onExit,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Volver al login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ServiceCard({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFE4E9F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$title: siguiente módulo a implementar.')),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: Color(0xFF667085), height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}
