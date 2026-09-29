# Express

Plataforma Flutter + Supabase para **Viajes + Delivery** con experiencia Pasajero, Conductor y panel administrativo web.

## Antes de tocar el proyecto

La documentación de continuidad está aquí:

### [docs/START_HERE_EXPRESS.md](docs/START_HERE_EXPRESS.md)

Ese archivo contiene:

- arquitectura actual;
- proyecto correcto de Supabase;
- funciones implementadas;
- flujo Pasajero/Conductor/Delivery;
- backend LIVE;
- RLS y errores ya corregidos;
- sistema de versiones y actualización;
- GitHub Pages;
- panel Admin;
- Billetera Express;
- Viajes programados;
- roadmap;
- Build Center APK/AAB pendiente;
- checklist de QA;
- reglas para continuar el proyecto con otra IA.

**Si eres una IA nueva o estás retomando Express después de tiempo, lee ese documento completo antes de modificar código o base de datos.**

## Repositorio y preview

- Repo: `jorge2610g/Expressdelivery`
- Preview: `https://jorge2610g.github.io/Expressdelivery/`
- Supabase Express: project ref `zgpijrznvaskgcmauwxx`

No incluir service-role keys, GitHub tokens, keystores ni otros secretos en el cliente o en documentación pública.

## Entrada web actual

GitHub Pages compila:

```text
lib/web_preview.dart
```

No asumir que `lib/main.dart` o los archivos `*_preview.dart` antiguos representan la experiencia más nueva.

## Desarrollo local

```bash
flutter pub get
flutter run -d chrome -t lib/web_preview.dart
```

Build web:

```bash
flutter build web --release -t lib/web_preview.dart --base-href /Expressdelivery/
```

## Deployment

El workflow está en:

```text
.github/workflows/deploy-web.yml
```

Se despliega automáticamente a GitHub Pages al hacer push a `main`.

El workflow usa `cancel-in-progress: true`; si hay varios commits seguidos, los workflows anteriores pueden aparecer como cancelados. Siempre verificar el workflow del **commit más reciente**.

## Backend

Las migraciones históricas están en:

```text
supabase/migrations/
```

### Advertencia

La base LIVE actual contiene más cambios que los archivos `001-003`.

Antes de reconstruir Supabase o crear otro entorno, leer la sección de migraciones en:

`docs/START_HERE_EXPRESS.md`

y sincronizar el schema LIVE correctamente.

## Estado general

Express ya incluye, entre otras funciones:

- autenticación;
- Pasajero y Conductor;
- mapa principal;
- GPS;
- ruta vial;
- Viajes;
- Delivery;
- ofertas;
- seguimiento;
- chat;
- llamada;
- cancelaciones;
- Viajes programados;
- Billetera Express;
- historial;
- detalles de servicio;
- notificaciones internas;
- SOS/contactos de confianza;
- aprobación de conductores;
- panel Admin básico;
- detector de nueva versión web.

El panel administrativo completo y el Build Center para APK/AAB siguen en roadmap.

---

Para el estado exacto y los próximos pasos: **[START_HERE_EXPRESS.md](docs/START_HERE_EXPRESS.md)**.
