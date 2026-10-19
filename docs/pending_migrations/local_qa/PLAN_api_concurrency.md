# Fase 2: plan de concurrencia por API de Supabase (NO EJECUTADO)

Requiere **autorización explícita**: crea solicitudes y ofertas en la base compartida. No ejecutar sin confirmación.

## Objetivo
Verificar que dos conductores de auditoría con ofertas sobre la misma solicitud no producen dos asignaciones cuando el pasajero confirma ambas a la vez a través de PostgREST/RPC.

## Precondiciones
- Dos conductores de auditoría activos en el grupo de prueba (ya existe uno; el segundo debe confirmarse).
- Una solicitud de prueba de Preview creada desde la UI del pasajero de auditoría.
- Dos ofertas pendientes de esos conductores, creadas desde su app (no por SQL directo).
- Tokens de sesión reales de la cuenta de pasajero de auditoría (nunca en el repositorio).

## Procedimiento
1. Lanzar dos llamadas RPC `select_ride_offer_v2` en paralelo (una por oferta) con el mismo token de pasajero.
2. Repetir N veces con solicitudes frescas.
3. Verificar tras cada repetición: 1 viaje, 1 oferta `selected`, 1 `declined`, solicitud `driver_selected`, historial = 1.

## Criterio de aprobación
Exactamente una respuesta OK por repetición y cero inconsistencias. Si no se puede ejecutar, se reporta como NO EJECUTADO.

## Limpieza
Registrar identificadores creados; no borrar filas compartidas sin autorización.
