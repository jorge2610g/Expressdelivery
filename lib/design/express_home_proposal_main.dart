import 'package:flutter/material.dart';

import 'express_brand.dart';
import 'express_home_proposal.dart';

/// Vista previa aislada de la propuesta de inicio.
/// Ejecutar con: flutter run -t lib/design/express_home_proposal_main.dart
/// Usa datos de ejemplo; no inicia sesión ni toca Supabase.
void main() {
  runApp(const ExpressHomeProposalPreviewApp());
}

class ExpressHomeProposalPreviewApp extends StatefulWidget {
  const ExpressHomeProposalPreviewApp({super.key});

  @override
  State<ExpressHomeProposalPreviewApp> createState() =>
      _ExpressHomeProposalPreviewAppState();
}

class _ExpressHomeProposalPreviewAppState
    extends State<ExpressHomeProposalPreviewApp> {
  ThemeMode _mode = ThemeMode.dark;
  int _tab = 0;

  ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F6BFF),
        brightness: brightness,
      ),
      extensions: [isDark ? ExpressBrandColors.dark : ExpressBrandColors.light],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _mode,
      home: Stack(
        children: [
          ExpressHomeProposal(
            zoneName: 'Trinidad',
            hasRides: true,
            hasParcels: true,
            selectedTab: _tab,
            onTab: (i) => setState(() => _tab = i),
            onRide: () {},
            onParcel: () {},
            onRefresh: () {},
          ),
          Positioned(
            right: ExpressSpace.l,
            bottom: 96,
            child: FloatingActionButton.small(
              tooltip: 'Cambiar tema claro u oscuro',
              onPressed: () => setState(() {
                _mode = _mode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark;
              }),
              child: Icon(
                _mode == ThemeMode.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
