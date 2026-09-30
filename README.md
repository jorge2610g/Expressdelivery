# Express Delivery

Aplicación Flutter + Supabase de **Pasajero + Conductor + Delivery**.

Este repositorio ya no contiene el panel administrativo. El administrador vive de forma independiente en:

- `jorge2610g/Adminexpress`
- web: `https://jorge2610g.github.io/Adminexpress/`

## Responsabilidad de este repositorio

`Expressdelivery` contiene únicamente la aplicación de operación que usan pasajeros, conductores y repartidores:

- autenticación;
- mapa/GPS;
- viajes;
- delivery;
- ofertas;
- vehículos;
- seguimiento;
- historial;
- pagos declarativos/billetera;
- seguridad/SOS;
- notificaciones internas;
- detección de actualizaciones Android;
- build web;
- build Android APK/AAB.

El panel Admin, Dashboard, usuarios, conductores, tarifas, App Builder y herramientas de administración se mantienen en `Adminexpress`.

## Entradas activas

Web:

```text
lib/web_preview.dart
```

Android:

```text
lib/mobile_main.dart
```

No existe una entrada administrativa en este repositorio.

## Version actual

- Express v1.5.20 · build 60
- `pubspec.yaml`: `1.5.20+60`

## Preview web

`https://jorge2610g.github.io/Expressdelivery/`

GitHub Pages compila exclusivamente `lib/web_preview.dart`.

## Android cloud build

El workflow:

```text
.github/workflows/build-android.yml
```

genera en GitHub Actions:

- APK release;
- AAB release;
- firma Android de producción;
- GitHub Release con enlaces permanentes;
- estado del build en Supabase.

El App Builder que crea y publica estos trabajos está en `Adminexpress`.

**Regla actual:** los pushes de código NO generan APK/AAB. Android solo se compila cuando existe una solicitud creada desde Adminexpress. El workflow periódico únicamente revisa si hay trabajos en cola.

## Backend

Supabase project ref:

```text
zgpijrznvaskgcmauwxx
```

Ambos repositorios usan el mismo backend. No eliminar RPCs/tablas administrativas de Supabase solamente porque el código Admin fue separado: `Adminexpress` todavía las usa.

## Cancelación de viajes

El backend cancela la solicitud mediante `cancel_ride_request`. La UI mantiene una lista local de IDs cancelados y usa `cachedData` como fuente visual de verdad para impedir que un Future viejo vuelva a mostrar una solicitud ya cancelada.

Esto es importante porque Flutter `FutureBuilder` puede conservar temporalmente los datos de la Future anterior al cambiar de consulta.

## Limpieza 2026-09-30

Se retiraron del repositorio:

- `lib/admin_panel.dart`;
- `lib/admin_control_sections.dart`;
- antigua entrada `lib/main.dart`;
- modelos/servicios del prototipo antiguo de órdenes;
- previews antiguos de login, viajes, delivery y experiencia.

No volver a copiar Admin dentro de Express. Toda función administrativa nueva debe implementarse en `Adminexpress`.

## Continuidad

Antes de modificar arquitectura, backend o releases leer:

- `docs/START_HERE_EXPRESS.md`
- `docs/CHANGELOG_ACTIVE.md`

No guardar tokens, service-role keys, contraseñas ni keystores en el repositorio.
