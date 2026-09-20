# Express Delivery

Aplicación multiplataforma desarrollada con Flutter y Supabase.

## Funcionalidades actuales

- Registro e inicio de sesión.
- Perfiles de cliente y repartidor.
- Creación y gestión de pedidos.
- Flujo de estados: pendiente, aceptado, retirado, en camino y entregado.
- Historial automático de estados.
- Cálculo estimado de tarifa en CLP según distancia.
- Cálculo de ruta por carretera.
- Vista de mapa con OpenStreetMap.
- Panel para repartidores.
- Compatible con Android y Web.

## Tarifas

La estimación usa valores configurables en `lib/main.dart`:

- Tarifa base: $1.500 CLP.
- Valor por kilómetro: $800 CLP.

Estos valores son provisionales y pueden cambiarse sin modificar la base de datos.

## Desarrollo local

Instala Flutter y ejecuta:

```bash
flutter pub get
flutter run -d chrome
```

Para preparar Android desde este repositorio:

```bash
flutter create .
flutter pub get
flutter run
```

Para generar el APK:

```bash
flutter build apk --release
```

Para generar la versión web:

```bash
flutter build web --release
```

## Backend

El proyecto utiliza Supabase para autenticación, perfiles, pedidos, estados y políticas de seguridad. Las migraciones están en:

`supabase/migrations/`

## Mapas y rutas

El mapa utiliza Flutter Map con OpenStreetMap y el cálculo de ruta utiliza servicios públicos de geocodificación y routing. Para un despliegue comercial a escala conviene sustituir estos servicios públicos por un proveedor con límites y condiciones de uso adecuados.
