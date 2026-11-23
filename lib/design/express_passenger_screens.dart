import 'package:flutter/material.dart';

import 'express_components.dart';
import 'express_tokens.dart';

/// Pantallas del pasajero en el sistema de diseño nuevo. Son estáticas (datos
/// de ejemplo) para revisar el diseño; la lógica real se conecta después.

class _ScreenShell extends StatelessWidget {
  const _ScreenShell({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ExpressTheme.light(),
      child: Material(
        color: ExpressColors.mapGround,
        child: SizedBox(
          width: 390,
          height: 844,
          child: Stack(children: children),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: ExpressColors.card,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE3E7EF)),
      ),
      child: Icon(icon, size: 20, color: ExpressColors.text),
    );
  }
}

/// 2 · Elige tu viaje: las dos tarjetas de precio lado a lado.
class ExpressChooseTripScreen extends StatelessWidget {
  const ExpressChooseTripScreen({
    super.key,
    this.fixedSelected = true,
    this.onConfirm,
  });

  final bool fixedSelected;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return _ScreenShell(
      children: [
        const Positioned.fill(child: ExpressMapBackdrop()),
        const Positioned(
          left: 16,
          top: 16,
          child: _RoundIcon(Icons.arrow_back_ios_new_rounded),
        ),
        const Positioned(
          right: 16,
          top: 20,
          child: ExpressPill(
            text: 'Demanda normal',
            background: ExpressColors.mintInk,
            foreground: ExpressColors.mint,
            icon: Icons.check_rounded,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 424,
          child: ExpressSheet(
            gap: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Elige tu viaje',
                              style: ExpressType.title.copyWith(fontSize: 22)),
                          const SizedBox(height: 2),
                          Text('Express · 4 asientos · 2,7 km · 4 min',
                              style: ExpressType.caption),
                        ],
                      ),
                    ),
                    Text('Cambiar',
                        style: ExpressType.bodyStrong
                            .copyWith(color: ExpressColors.blueSoft)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ExpressPriceCard(
                        mode: ExpressPriceMode.fixed,
                        amount: r'$ 2.315',
                        note: 'el conductor más cercano, sin ofertas',
                        selected: fixedSelected,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ExpressPriceCard(
                        mode: ExpressPriceMode.offer,
                        amount: r'$ 1.815',
                        note: 'sube o baja; pueden contraofertar',
                        selected: !fixedSelected,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _InfoTile(Icons.schedule_rounded, 'Cuándo', 'Ahora')),
                    const SizedBox(width: 10),
                    Expanded(child: _InfoTile(Icons.payments_outlined, 'Pago', 'Efectivo')),
                  ],
                ),
                const Spacer(),
                ExpressButton(
                  label: r'Confirmar viaje · $ 2.315',
                  onPressed: onConfirm,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ExpressColors.card,
        borderRadius: BorderRadius.circular(ExpressRadii.control),
        border: Border.all(color: ExpressColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: ExpressColors.blueSoft),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: ExpressType.caption.copyWith(fontSize: 11)),
              Text(value, style: ExpressType.bodyStrong),
            ],
          ),
        ],
      ),
    );
  }
}

/// 3 · Buscando conductor cerca de ti (1 minuto, un conductor a la vez).
class ExpressSearchingScreen extends StatelessWidget {
  const ExpressSearchingScreen({super.key, this.onCancel});
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return _ScreenShell(
      children: [
        const Positioned.fill(child: ExpressMapBackdrop()),
        const Positioned(
          left: 16,
          top: 20,
          child: ExpressPill(
            text: r'Precio fijo · $ 2.315',
            background: ExpressColors.blueInk,
            foreground: ExpressColors.blueText,
            icon: Icons.lock_outline_rounded,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 410,
          child: ExpressSheet(
            gap: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text('Buscando conductor\ncerca de ti',
                          style: ExpressType.title
                              .copyWith(fontSize: 22, height: 1.2)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: ExpressColors.blueInk,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text('00:42',
                          style: ExpressType.title.copyWith(
                              fontSize: 22, color: ExpressColors.blueText)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const ExpressCountdownBar(progress: .3),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Te avisamos en cuanto alguien tome tu viaje',
                        style: ExpressType.caption.copyWith(fontSize: 12)),
                    Text('1 min',
                        style: ExpressType.caption.copyWith(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ExpressColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE3E7EF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('LO ESTÁ VIENDO', style: ExpressType.label),
                          Text('00:09',
                              style: ExpressType.bodyStrong.copyWith(
                                  fontSize: 13, color: ExpressColors.amber)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: ExpressColors.raised,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: ExpressColors.blue, width: 2),
                            ),
                            child: Text('CP',
                                style: ExpressType.heading
                                    .copyWith(color: ExpressColors.blueText)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(TextSpan(children: [
                                  TextSpan(
                                      text: 'Conductor Prueba ',
                                      style: ExpressType.heading
                                          .copyWith(fontSize: 16)),
                                  const WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: Icon(Icons.star_rounded,
                                          size: 16,
                                          color: ExpressColors.amber)),
                                  TextSpan(
                                      text: ' 5,00',
                                      style: ExpressType.bodyStrong.copyWith(
                                          color: ExpressColors.amber)),
                                ])),
                                Text('Express Moto · 1,1 km de ti',
                                    style: ExpressType.caption),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const ExpressCountdownBar(
                          progress: .6, color: ExpressColors.amber, height: 5),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Cada conductor tiene 15 segundos. Si no responde, pasamos al siguiente y no vuelve a recibir este viaje.',
                  style: ExpressType.caption,
                ),
                const Spacer(),
                ExpressButton(
                  label: 'Cancelar viaje',
                  kind: ExpressButtonKind.danger,
                  icon: Icons.close_rounded,
                  height: 52,
                  onPressed: onCancel,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 4 · ¿Seguimos buscando conductor? (30 s para decidir antes de cancelar).
class ExpressKeepSearchingScreen extends StatelessWidget {
  const ExpressKeepSearchingScreen({super.key, this.onKeep, this.onCancel});
  final VoidCallback? onKeep;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return _ScreenShell(
      children: [
        const Positioned.fill(child: ExpressMapBackdrop()),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 400,
          child: ExpressSheet(
            gap: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: ExpressColors.blueInk,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.schedule_rounded,
                          size: 26, color: ExpressColors.blueSoft),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('¿Seguimos buscando conductor?',
                          style: ExpressType.title
                              .copyWith(fontSize: 23, height: 1.15)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Pasó 1 minuto y ningún conductor tomó tu viaje. Puedes buscar otro minuto con conductores nuevos, o cancelar.',
                  style: ExpressType.body,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ExpressColors.card,
                    borderRadius: BorderRadius.circular(ExpressRadii.card),
                    border: Border.all(color: const Color(0xFFE3E7EF)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined,
                              size: 18, color: ExpressColors.coral),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Se cancelará automáticamente en',
                                style: ExpressType.bodyStrong
                                    .copyWith(fontSize: 14)),
                          ),
                          Text('18 s',
                              style: ExpressType.title.copyWith(
                                  fontSize: 22, color: ExpressColors.coral)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const ExpressCountdownBar(
                          progress: .6, color: ExpressColors.coral),
                    ],
                  ),
                ),
                const Spacer(),
                ExpressButton(
                  label: 'Seguir buscando',
                  icon: Icons.refresh_rounded,
                  onPressed: onKeep,
                ),
                const SizedBox(height: 10),
                ExpressButton(
                  label: 'Cancelar viaje',
                  kind: ExpressButtonKind.danger,
                  height: 52,
                  onPressed: onCancel,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
