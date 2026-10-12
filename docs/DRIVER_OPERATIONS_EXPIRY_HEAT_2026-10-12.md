# Express · vehículo, fotos, vencimientos, GPS, ganancias y calor — 2026-10-12

## Arquitectura y respaldos
- Web única en `https://expressviajes.online`. Entorno determinado exclusivamente por la cuenta (`account_runtime_bindings`). No usar un dominio de Preview adicional ni publicar APK/AAB.
- Rama `feat/driver-vehicle-gps-earnings-heat-20261012`, PR #173; respaldo `backup/before-vehicle-expiry-map-heatmap-20261012` anterior a los cambios.
- Migraciones versionadas: `20261012043000` retrato privado, `20261012053000` barrera de vencimiento, `20261012053100` actualización de RPC, `20261012055000` mapa por zona, `20261012055500` job horario.
- Backend compartido: **`driver_expiration_channel_settings.preview=true`** y **`production=false`**. No habilitar Producción sin QA Preview satisfactorio y análisis de clientes Android antiguos.
- El bucket `driver-onboarding` sigue privado. Pasajeros autorizados por ofertas/viajes del mismo entorno reciben URL firmada con caducidad de 5 minutos; no URL pública permanente.

## Funcionalidad
1. El tipo de vehículo se elige explícitamente de los tipos habilitados en el catálogo de servicios de la zona; se conservan marca/modelo/placa/año y fotos. Cambiar el servicio no asigna automáticamente una moto.
2. El formulario permite introducir vencimiento en licencia/seguros/revisión, con indicador hasta 30 días antes; la fecha se almacena como fin de vigencia en la hora local del país. Las correcciones que cambian el vencimiento de un documento ya aprobado necesitan nuevas fotos y revisión. Los documentos aprobados antiguos sin fecha se preservan.
3. El backend impide conectarse con fecha vencida y fuerza desconexión ante ubicación nueva, solo para Preview en este despliegue. `pg_cron` ejecuta un barrido horario con hitos 30,14,7,3,1,0,-1 días y registro anti-duplicados; el conductor activo puede finalizar un viaje ya iniciado, pero no recibir nuevos.
4. El pasajero ve el retrato real del conductor en ofertas y en viaje cuando su cuenta está autorizada. La foto de identidad sigue en Storage privado.
5. Mapa del conductor: ubicación GPS en movimiento con reciente automático; botón manual de centrado; al entrar, lectura de límites del polígono o radio de zona y ajuste de cámara. La navegación de un viaje conserva su encuadre de ruta.
6. Mapa principal del pasajero: no permite arrastre/rotación manual; se actualiza con GPS local sin consultas backend adicionales por punto. La elección de origen/destino permanece en su selector específico.
7. Ganancias del día: cápsula redonda en lugar de «Conductor ↔», con opción mostrar/ocultar, número de viajes completados y desglose por moneda. Contador reinicia según hora local del teléfono a medianoche; el historial no se borra. El valor suma tarifas finales de viajes completados (importe bruto; no equivale a saldo neto tras comisiones).
8. Calor: un RPC por ~90 segundos cuando está en línea agrega solicitudes de la misma zona y mismo canal por celdas (~440m); nunca expone coordenadas exactas del pasajero. Sin demanda real o sin tarifa dinámica habilitada, no dibuja calor. Los multiplicadores son los registrados en las solicitudes; NO se incrementan tarifas desde el mapa.

## Limitaciones deliberadas y pendientes de QA
- Las reglas dinámicas actuales dejan `max_multiplier=1.5` en Preview; Producción tiene precios dinámicos apagados. Los x2–x5 requieren configuración y simulación de tarifa desde panel con aprobación posterior: **no se inventa x5 ni se altera el cobro**.
- El indicador de ganancias usa `final_fare` (importe total del viaje), no retenciones ni saldo neto. Separa CLP/BOB sin sumarlas. Usa fecha local del dispositivo; revisar si se necesita hora explícita de la zona ante viajes internacionales.
- No se modifican reglas de GPS de la app nativa sin versión Android y prueba aparte.
- Documentos configurables pueden activar `expiration_required`; queda **desactivado por defecto** mientras existan clientes Android antiguos que no envían fechas. Las fechas conocidas vencidas sí se controlan en Preview.
- Programación `pg_cron` instalada y habilitada, limitada al entorno Preview inicialmente.
- Falta prueba manual E2E con admin Preview, conductor Preview y pasajero Preview; luego habilitar Producción mediante configuración, sin tocar los datos reales de pruebas.

## Prueba E2E Preview
1. Crear un conductor Preview en «Iquique Prueba», registrar tipo vehículo explícito, datos y fotos.
2. Aprobar frente/reverso y retrato; comprobar que el pasajero Preview autorizado ve foto real en oferta y viaje.
3. Cargar licencia con vencimiento futuro, aprobar; editar foto renovada y nueva fecha, comprobar que vuelve a revisión.
4. En un documento Preview de prueba con fecha pasada, verificar que al conectarse se rechaza sin afectar Producción.
5. Mover GPS sin viajes: cámara sigue al conductor; recentrar; salir y volver de viaje. Abrir pasajero y confirmar mapa fijo con GPS actualizado.
6. Generar solicitudes Preview con precio dinámico habilitado y ver celdas x1.5 si hay suficientes solicitudes en el mismo sector; sin demanda la capa desaparece.
7. Completar y cobrar viaje Preview: cápsula diaria actualiza total y cantidad; ocultar/mostrar. Abrir Ganancias.
8. Revisar en GitHub Pages el `version.json` del SHA fusionado y ejecución verde.
