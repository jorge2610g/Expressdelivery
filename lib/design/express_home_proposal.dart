import 'package:flutter/material.dart';

import 'express_brand.dart';

/// Propuesta de rediseño de la pantalla de inicio del pasajero.
/// Solo presentación: recibe datos y callbacks. No llama a servicios.
class ExpressHomeProposal extends StatelessWidget {
  const ExpressHomeProposal({
    super.key,
    required this.zoneName,
    required this.hasRides,
    required this.hasParcels,
    required this.onRide,
    required this.onParcel,
    required this.onRefresh,
    this.selectedTab = 0,
    this.onTab,
  });

  final String zoneName;
  final bool hasRides;
  final bool hasParcels;
  final VoidCallback onRide;
  final VoidCallback onParcel;
  final VoidCallback onRefresh;
  final int selectedTab;
  final ValueChanged<int>? onTab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brand = Theme.of(context).extension<ExpressBrandColors>() ??
        ExpressBrandColors.dark;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: ExpressSpace.l,
        title: Row(
          children: [
            Text(
              'EXPRESS',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: ExpressSpace.s),
            Flexible(
              child: Text(
                zoneName,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: brand.muted),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar servicios',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          ExpressSpace.l,
          ExpressSpace.s,
          ExpressSpace.l,
          ExpressSpace.xl,
        ),
        children: [
          Text(
            '¿Qué necesitas hoy?',
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: ExpressSpace.xs),
          Text(
            'Elige un servicio de Express',
            style: text.bodyMedium?.copyWith(color: brand.muted),
          ),
          const SizedBox(height: ExpressSpace.l),
          IntrinsicHeight(
            child: Row(
              children: [
                if (hasRides)
                  Expanded(
                    child: _ServiceCard(
                      title: 'Viajes',
                      subtitle: 'Taxi y mototaxi',
                      icon: Icons.local_taxi_rounded,
                      start: brand.rideStart,
                      end: brand.rideEnd,
                      onTap: onRide,
                    ),
                  ),
                if (hasRides && hasParcels)
                  const SizedBox(width: ExpressSpace.m),
                if (hasParcels)
                  Expanded(
                    child: _ServiceCard(
                      title: 'Envíos',
                      subtitle: 'Paquetes seguros',
                      icon: Icons.inventory_2_rounded,
                      start: brand.parcelStart,
                      end: brand.parcelEnd,
                      onTap: onParcel,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: ExpressSpace.xl),
          Text(
            'Accesos rápidos',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: ExpressSpace.s),
          if (hasRides)
            _QuickAction(
              icon: Icons.location_on_rounded,
              title: '¿A dónde vamos?',
              subtitle: 'Buscar destino de tu viaje',
              onTap: onRide,
            ),
          if (hasRides && hasParcels) const SizedBox(height: ExpressSpace.s),
          if (hasParcels)
            _QuickAction(
              icon: Icons.inventory_2_rounded,
              title: 'Enviar un paquete',
              subtitle: 'Buscar dirección de entrega',
              onTap: onParcel,
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: onTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Historial',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Pagos',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.start,
    required this.end,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color start;
  final Color end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Ink(
            height: 190,
            padding: const EdgeInsets.all(ExpressSpace.l),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [start, end],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: ExpressSpace.xs),
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(icon, color: Colors.white, size: 52),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brand = Theme.of(context).extension<ExpressBrandColors>() ??
        ExpressBrandColors.dark;

    return Material(
      color: brand.quickTile,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ExpressSpace.m),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: brand.quickIconBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: ExpressSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(color: brand.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: brand.muted),
            ],
          ),
        ),
      ),
    );
  }
}
