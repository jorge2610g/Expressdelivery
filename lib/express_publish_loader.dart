import 'package:flutter/material.dart';

/// Carga temporal al publicar una solicitud del pasajero.
///
/// Solo existe durante la llamada que publica la solicitud. Un velo transparente
/// absorbe todos los toques para que no se pueda tocar el mapa ni los controles
/// hasta que el servidor confirme. Cuando la publicación termina, el cuadro y el
/// velo se retiran y la búsqueda normal toma el control.
class ExpressPublishLoader extends StatelessWidget {
  const ExpressPublishLoader({super.key, this.dark = false});

  /// Lo calcula quien muestra el cuadro: el overlay no consulta el tema al retirarse.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final surface = dark ? const Color(0xFF171717) : Colors.white;
    final text = dark ? Colors.white : const Color(0xFF0B1F3A);
    final muted = dark ? const Color(0xFFB0B6C2) : const Color(0xFF5B6B7F);

    // El overlay raíz no tiene Material ni tema: el estilo se fija aquí y el
    // escalado de fuente del sistema se limita para que el texto no se corte.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Velo transparente: absorbe cualquier toque mientras se publica.
            const Positioned.fill(
              child: AbsorbPointer(child: SizedBox.expand()),
            ),
            SafeArea(
              child: Center(
                child: Container(
                  width: 280,
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(strokeWidth: 4),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Buscando conductores…',
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: TextStyle(
                          color: text,
                          fontSize: 18,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Estamos publicando tu solicitud.',
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: TextStyle(
                          color: muted,
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w400,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
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

/// Ejecuta [action] mostrando [ExpressPublishLoader] en el overlay raíz.
///
/// El cuadro se retira siempre (éxito, error o cierre de pantalla) para que no
/// quede bloqueada la pantalla. Los errores se re-lanzan al llamador.
Future<T> runExpressPublishing<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final dark = MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark;
  OverlayEntry? entry;
  if (overlay != null) {
    entry = OverlayEntry(builder: (_) => ExpressPublishLoader(dark: dark));
    overlay.insert(entry);
  }
  try {
    return await action();
  } finally {
    entry?.remove();
  }
}
