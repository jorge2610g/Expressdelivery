import 'package:flutter/material.dart';

/// Pide al conductor el PIN de abordaje de 4 dígitos que muestra el pasajero.
/// Devuelve el PIN validado o `null` si el conductor cancela.
Future<String?> showExpressBoardingPinDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ExpressBoardingPinDialog(),
  );
}

/// El controlador vive en el State del diálogo y se libera en dispose(), cuando
/// la ruta ya cerró. Liberarlo justo después de `await showDialog` dejaba el
/// TextField usando un controlador descartado.
class ExpressBoardingPinDialog extends StatefulWidget {
  const ExpressBoardingPinDialog({super.key});

  @override
  State<ExpressBoardingPinDialog> createState() =>
      _ExpressBoardingPinDialogState();
}

class _ExpressBoardingPinDialogState extends State<ExpressBoardingPinDialog> {
  static final RegExp _pinPattern = RegExp(r'^\d{4}$');

  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _controller.text.trim();
    if (!_pinPattern.hasMatch(pin)) {
      // Antes el botón ignoraba en silencio un PIN incompleto.
      setState(() => _error = 'El PIN debe tener 4 dígitos.');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PIN de abordaje'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 4,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          letterSpacing: 8,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          // Marcadores que no son dígitos: "0000" se leía como PIN ya escrito.
          hintText: '· · · ·',
          helperText: 'Pide al pasajero su PIN de 4 dígitos.',
          helperMaxLines: 2,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Iniciar viaje'),
        ),
      ],
    );
  }
}
