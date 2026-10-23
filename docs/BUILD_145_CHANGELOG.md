# Registro de cambios — Express Principal 1.6.3+145

## Motivo de la candidata

Build 145 incorpora al único paquete Android oficial `com.express.usuario1` los cambios de deuda por cancelación integrados en `main` mediante PR #283 (`f18ba32daf6ef9466a13f133c22134a839533754`). Build 144 ya se usó en Google Play Internal y corresponde al SHA anterior `6daa510fd3762bb150b8cfa6785b4ce63076b705`; no debe recompilarse ni reutilizarse.

## Cambios funcionales incluidos

- Pasajero y conductor reciben una tarjeta inferior contextual ante un bloqueo por deuda de cancelación.
- La tarjeta identifica el monto y la moneda si están disponibles, explica el siguiente paso y abre Pagos y billetera.
- Oculta el proveedor de pago y los códigos técnicos de PostgREST/SQL. “Ahora no” permite cerrar el aviso sin repetir el error.
- El pasajero ve la tarifa acordada durante el viaje activo.

## Estado de publicación

- Rama principal de código: `main`; fuente candidata posterior a PR #283.
- VersionName: `1.6.3`; versionCode reservado para esta candidata: `145`.
- Destino solicitado: Google Play Internal únicamente. No promover a Producción.
- Emuladores: omitidos por instrucción del propietario; la validación funcional final la realizará manualmente desde Play Internal.
- APK/AAB, SHA de fuente final, hashes, run de GitHub Actions y enlace de Internal: pendientes de completar después de encolar y compilar la candidata oficial.
