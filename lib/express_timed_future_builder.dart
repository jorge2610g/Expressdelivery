import 'dart:async';

import 'package:flutter/material.dart';

/// Carga con límite de tiempo y botón "Reintentar".
///
/// Envuelve un FutureBuilder: el builder recibe el mismo AsyncSnapshot de
/// siempre. Si la carga se cuelga o falla, muestra un mensaje y "Reintentar",
/// que crea un Future nuevo con [load]. Mientras recarga con datos previos,
/// mantiene lo último mostrado y marca "Actualizando…". Con [entityKey] que
/// cambia, descarta esos datos previos.
class ExpressTimedFutureBuilder<T> extends StatefulWidget {
  const ExpressTimedFutureBuilder({
    super.key,
    required this.load,
    required this.builder,
    this.future,
    this.timeout = const Duration(seconds: 10),
    this.entityKey,
  });

  /// Crea una carga nueva. La usa "Reintentar" y la primera carga si no
  /// se pasa [future].
  final Future<T> Function() load;

  /// Carga ya iniciada por quien llama. Evita una segunda consulta al abrir.
  final Future<T>? future;

  final AsyncWidgetBuilder<T> builder;
  final Duration timeout;

  /// Identidad de lo que se muestra (viaje, conductor, solicitud...). Si
  /// cambia, no se reutilizan datos de la entidad anterior.
  final Object? entityKey;

  @override
  State<ExpressTimedFutureBuilder<T>> createState() =>
      _ExpressTimedFutureBuilderState<T>();
}

class _ExpressTimedFutureBuilderState<T>
    extends State<ExpressTimedFutureBuilder<T>> {
  late Future<T> _future;
  late Object? _entityKey;
  int _generation = 0;
  int _loadId = 0;
  bool _pending = true;

  @override
  void initState() {
    super.initState();
    _entityKey = widget.entityKey;
    _future = _start(widget.future ?? widget.load());
  }

  Future<T> _start(Future<T> source) {
    final id = ++_loadId;
    _pending = true;
    final limited = source.timeout(widget.timeout);
    // Solo la carga más reciente puede liberar el estado "en curso".
    limited.whenComplete(() {
      if (mounted && id == _loadId) _pending = false;
    }).ignore();
    return limited;
  }

  @override
  void didUpdateWidget(covariant ExpressTimedFutureBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entityKey != _entityKey) {
      // Otra entidad: no se reutilizan datos previos.
      _entityKey = widget.entityKey;
      _generation++;
      _future = _start(widget.future ?? widget.load());
      return;
    }
    // Igual que FutureBuilder: un Future nuevo (refresco) reinicia la carga y
    // conserva lo último mostrado mientras llega ("Actualizando…").
    final next = widget.future;
    if (next != null && !identical(next, oldWidget.future)) {
      _future = _start(next);
    }
  }

  void _retry() {
    // Evita cargas duplicadas: si ya hay una en curso, no hace nada.
    if (_pending) return;
    // Un FutureBuilder nuevo: el reintento no arrastra el error anterior.
    setState(() {
      _generation++;
      _future = _start(widget.load());
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      key: ValueKey(_generation),
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError &&
            snapshot.connectionState != ConnectionState.waiting) {
          return _ErrorView(
            timedOut: snapshot.error is TimeoutException,
            onRetry: _retry,
          );
        }
        // Mientras reintenta tras un error, no se muestra el error anterior.
        final effective = snapshot.hasError
            ? AsyncSnapshot<T>.waiting()
            : snapshot;
        final child = widget.builder(context, effective);
        final refreshing = snapshot.connectionState == ConnectionState.waiting &&
            snapshot.hasData;
        if (!refreshing) return child;
        return Stack(
          children: [
            child,
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
            const Positioned(
              top: 6,
              right: 12,
              child: _UpdatingLabel(),
            ),
          ],
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.timedOut, required this.onRetry});

  final bool timedOut;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              timedOut ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              timedOut
                  ? 'La conexión está tardando demasiado.'
                  : 'No se pudo cargar la información.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdatingLabel extends StatelessWidget {
  const _UpdatingLabel();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xCC000000),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'Actualizando…',
          style: TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}
