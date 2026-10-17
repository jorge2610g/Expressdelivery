import 'package:flutter/material.dart';

/// Datos que el conductor escribe al enviar una oferta de tarifa.
class DriverOfferInput {
  const DriverOfferInput({required this.fareText, required this.etaText});

  final String fareText;
  final String etaText;
}

/// Diálogo de tarifa y tiempo de llegada.
///
/// Los controladores viven en el State del diálogo y se liberan en dispose(),
/// cuando la ruta ya terminó de cerrarse. Liberarlos justo después de
/// `await showDialog` dejaba los TextField usando controladores descartados.
class DriverOfferDialog extends StatefulWidget {
  const DriverOfferDialog({
    super.key,
    required this.title,
    required this.fareLabel,
    required this.initialFare,
    this.summary,
    this.initialEta = '5',
    this.confirmLabel = 'Enviar',
  });

  final String title;
  final String fareLabel;
  final String initialFare;
  final Widget? summary;
  final String initialEta;
  final String confirmLabel;

  @override
  State<DriverOfferDialog> createState() => _DriverOfferDialogState();
}

class _DriverOfferDialogState extends State<DriverOfferDialog> {
  late final TextEditingController _fare =
      TextEditingController(text: widget.initialFare);
  late final TextEditingController _eta =
      TextEditingController(text: widget.initialEta);

  @override
  void dispose() {
    _fare.dispose();
    _eta.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.summary != null) ...[
            widget.summary!,
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _fare,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: widget.fareLabel),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _eta,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Llegas en (minutos)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            DriverOfferInput(fareText: _fare.text, etaText: _eta.text),
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
