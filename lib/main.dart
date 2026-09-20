import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://cdgemtkumzxlbhdgxlwn.supabase.co';
const supabasePublishableKey = 'sb_publishable_j7QozgTeNDz7jHch6W0XKg_VgSsvxXq';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(const ExpressDeliveryApp());
}

final supabase = Supabase.instance.client;

class ExpressDeliveryApp extends StatelessWidget {
  const ExpressDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Express Delivery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _testConnection(BuildContext context) async {
    try {
      await supabase.from('profiles').select('id').limit(1);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supabase conectado correctamente.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de conexión: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Express Delivery'), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_shipping_rounded, size: 96,
                color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 24),
              Text('Express Delivery',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Aplicación de entregas conectada a Supabase.',
                textAlign: TextAlign.center),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => _testConnection(context),
                icon: const Icon(Icons.cloud_done),
                label: const Text('Probar conexión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
