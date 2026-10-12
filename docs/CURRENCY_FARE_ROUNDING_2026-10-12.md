# Redondeo autoritativo de tarifas · 2026-10-12

## Objetivo
La misma tarifa debe verse en Pasajero, Conductor, ofertas, historial e indicador de ganancias brutas. El cálculo y la persistencia ocurren en Supabase (no solo en `toStringAsFixed` de Flutter). El panel Adminexpress central permite elegir por moneda y entorno:
- `0.01`: centavos;
- `0.50`: múltiplos de 50 centavos (ejemplo BOB 8,59 → BOB 8,50);
- `1.00`: importes enteros (CLP recomendado).

## Arquitectura
- Migración: `20261012153000_currency_fare_rounding.sql`.
- Tabla privada `fare_rounding_currency_policies` con clave `(channel,currency)` y RLS; sin permisos directos Data API.
- RPC admin `admin_fare_rounding_get/set` con entorno de la cuenta; escritura exclusiva `super_admin`. El control de UI está en `jorge2610g/Adminexpress/lib/admin_fare_rounding.dart` dentro de Tarifas.
- `quote_service_fare_for_location` y `dynamic_pricing_quote` devuelven redondeados `amount`, `recommended_fare`, `minimum_allowed_fare`, `base_amount` y `minimum_fare`; `fare_rounding_increment` permite inspección.
- El trigger `enforce_ride_recommended_fare_floor` valida contra el piso redondeado y guarda la tarifa realmente cobrada, incluso para tarifa fija.
- Solicitudes de viajes y Delivery guardan el incremento vigente; ofertas de conductores, tarifas finales de viajes y tarifas propuestas de entregas lo respetan. El RPC de ingresos brutos ya suma `trips.final_fare` y `delivery_requests.proposed_fare`.
- Cambiar configuración afecta únicamente nuevas solicitudes. Los viajes históricos no se actualizan. Preview y Producción usan la misma app web y reglas de negocio, pero configuraciones separadas por `channel` y cuentas aisladas por `account_runtime_bindings`.

## Activación prudente
Por compatibilidad todas las monedas mantienen inicialmente el incremento predeterminado `0.01`. Probar primero con cuenta Preview en la **misma web**. Configurar BOB → `0.50` en el panel de esa cuenta, luego repetir con Producción cuando QA sea satisfactoria. No activar por SQL sin consentimiento operacional ni modificar tarifas anteriores.

## QA necesario
1. Cambiar BOB en Preview a `0.50` y cotejar API de cotización 8,59→8,50, 8,76→9,00; CLP sin cambio.
2. Crear viaje Preview en zona Bolivia con pasajero y conductor. Confirmar que el importe cotizado, solicitado, ofertado, aceptado, `trips.final_fare` y cápsula Ganancias del día coinciden en bruto.
3. Verificar tarifa fija de aeropuerto/terminal y tarifa escalonada por distancia. Probar una tarifa dinámica (Preview) y que el piso sigue autoritativo.
4. Empezar una solicitud, cambiar modo de redondeo y confirmar que no se modifica el importe ya establecido para esa solicitud; siguiente solicitud sí usa el nuevo incremento.
5. Verificar Delivery y servicios de otras monedas; no redondear el total de una compra de supermercado si no se trata de una tarifa de viaje/entrega.
6. Confirmar que un usuario Preview no puede editar política Production, que un monitor de zona no puede cambiarla y que un anónimo no puede ejecutar los RPC de administrador.
7. Revisar integridad de transacciones, comisión/ganancia neta (si aplica), notificaciones, historial y cash. No generar un APK Android; la web y el código Dart compartido se validan por CI.

## Límites
La ganancia bruta coincide con la tarifa guardada. Comisiones, impuestos o deducciones pueden producir un neto distinto y deben seguirse etiquetando como neto, nunca disfrazarse como monto cobrado al pasajero.
