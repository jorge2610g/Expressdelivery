import 'package:flutter/material.dart';

/// Nuevo inicio del pasajero (rediseño 2026-11).
///
/// Mismas funciones que el inicio actual, en otro lugar:
/// - la búsqueda de destino es una píldora flotante arriba del mapa;
/// - los accesos directos (Casa, Trabajo, guardados) flotan debajo de ella;
/// - el menú y «mi ubicación» van en un costado.
///
/// Solo se muestra en cuentas de Prueba (ver `ExpressRuntimeChannel.previewMode`).
/// Producción conserva el inicio de siempre.
abstract final class PassengerHomeStyle {
  static const Color blue = Color(0xFF0B57D0);
  static const Color blueSoft = Color(0xFFE3EDFD);
  static const Color amber = Color(0xFFFFB020);
  static const Color ink = Color(0xFF0E1525);
  static const Color muted = Color(0xFF5B6575);

  static Color surface(bool dark) =>
      dark ? const Color(0xFF1E1E1E) : Colors.white;
  static Color text(bool dark) => dark ? Colors.white : ink;
  static Color softText(bool dark) =>
      dark ? const Color(0xFFB7BDC8) : muted;

  static const List<BoxShadow> floatShadow = [
    BoxShadow(
      color: Color(0x2E0E1525),
      blurRadius: 22,
      offset: Offset(0, 8),
    ),
  ];
}

/// Un acceso directo del inicio (por ejemplo «Casa»).
class PassengerShortcut {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const PassengerShortcut({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

/// Arma los accesos directos: Casa y Trabajo siempre (si no están guardados,
/// abren «Lugares guardados»), seguidos de hasta [maxExtra] lugares más.
List<PassengerShortcut> passengerShortcutsFrom({
  required List<Map<String, dynamic>> saved,
  required ValueChanged<Map<String, dynamic>> onSaved,
  required VoidCallback onManage,
  int maxExtra = 3,
}) {
  Map<String, dynamic>? byLabel(String value) {
    for (final row in saved) {
      if (row['label']?.toString().trim().toLowerCase() == value) return row;
    }
    return null;
  }

  final home = byLabel('casa');
  final work = byLabel('trabajo');
  final result = <PassengerShortcut>[
    PassengerShortcut(
      label: 'Casa',
      icon: Icons.home_outlined,
      onTap: home == null ? onManage : () => onSaved(home),
    ),
    PassengerShortcut(
      label: 'Trabajo',
      icon: Icons.work_outline_rounded,
      onTap: work == null ? onManage : () => onSaved(work),
    ),
  ];
  var extra = 0;
  for (final row in saved) {
    if (extra >= maxExtra) break;
    final label = row['label']?.toString().trim() ?? '';
    final key = label.toLowerCase();
    if (label.isEmpty || key == 'casa' || key == 'trabajo') continue;
    result.add(
      PassengerShortcut(
        label: label,
        icon: Icons.place_outlined,
        onTap: () => onSaved(row),
      ),
    );
    extra++;
  }
  return result;
}

/// Píldora de búsqueda flotante: toda la barra abre el buscador y el botón de
/// la derecha abre el selector con mapa.
class PassengerHomePill extends StatelessWidget {
  final String subtitle;
  final VoidCallback onSearch;
  final VoidCallback onPickOnMap;
  final bool dark;

  const PassengerHomePill({
    super.key,
    required this.subtitle,
    required this.onSearch,
    required this.onPickOnMap,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PassengerHomeStyle.surface(dark),
      borderRadius: BorderRadius.circular(30),
      elevation: 0,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: PassengerHomeStyle.floatShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onSearch,
                borderRadius: BorderRadius.circular(30),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: PassengerHomeStyle.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.search_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '¿A dónde vamos?',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: PassengerHomeStyle.text(dark),
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: PassengerHomeStyle.softText(dark),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, left: 4),
              child: Tooltip(
                message: 'Elegir moviendo el mapa',
                child: InkWell(
                  onTap: onPickOnMap,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: dark
                          ? const Color(0xFF17243A)
                          : const Color(0xFFEEF4FE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.gps_fixed_rounded,
                      color: PassengerHomeStyle.blue,
                      size: 24,
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

/// Fila de accesos directos que flota debajo de la píldora.
class PassengerShortcutChips extends StatelessWidget {
  final List<PassengerShortcut> items;
  final VoidCallback onManage;
  final bool dark;

  const PassengerShortcutChips({
    super.key,
    required this.items,
    required this.onManage,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final item in items) ...[
            _Chip(
              icon: item.icon,
              label: item.label,
              onTap: item.onTap,
              dark: dark,
            ),
            const SizedBox(width: 8),
          ],
          _Chip(
            icon: Icons.star_rounded,
            iconColor: PassengerHomeStyle.amber,
            label: 'Ver todos',
            onTap: onManage,
            dark: dark,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final bool dark;

  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.dark,
    this.iconColor = PassengerHomeStyle.blue,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PassengerHomeStyle.surface(dark).withValues(alpha: .96),
      borderRadius: BorderRadius.circular(22),
      elevation: 3,
      shadowColor: const Color(0x330E1525),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: iconColor),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: PassengerHomeStyle.text(dark),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botones del costado: menú de atajos y mi ubicación.
class PassengerSideRail extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback onLocate;
  final bool locating;
  final bool dark;

  const PassengerSideRail({
    super.key,
    required this.onMenu,
    required this.onLocate,
    this.locating = false,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailButton(
          tooltip: 'Menú',
          icon: Icons.menu_rounded,
          filled: true,
          onTap: onMenu,
          dark: dark,
        ),
        const SizedBox(height: 10),
        _RailButton(
          tooltip: 'Mi ubicación',
          icon: Icons.my_location_rounded,
          busy: locating,
          onTap: onLocate,
          dark: dark,
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool filled;
  final bool busy;
  final VoidCallback onTap;
  final bool dark;

  const _RailButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    required this.dark,
    this.filled = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = filled
        ? PassengerHomeStyle.blue
        : PassengerHomeStyle.surface(dark);
    final foreground = filled ? Colors.white : PassengerHomeStyle.blue;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(18),
        elevation: 5,
        shadowColor: const Color(0x440E1525),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Center(
              child: busy
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: foreground,
                      ),
                    )
                  : Icon(icon, color: foreground, size: 25),
            ),
          ),
        ),
      ),
    );
  }
}
