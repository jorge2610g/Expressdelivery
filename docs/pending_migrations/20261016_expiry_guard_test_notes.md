# Pruebas de aceptación de ofertas (servidor)

## Ejecutadas (cuenta de conductor de auditoría, Preview, transacción revertida)
- Aceptar una oferta vencida (`selected`, expirada): el servidor responde `Oferta vencida o no disponible`. Resultado: RECHAZADA. Sin cambios persistentes (la transacción se revierte).

## Pendientes (requieren una rama de Supabase con datos aislados)
- Oferta `pending` con `expires_at` nulo: debe rechazarse tras aplicar la propuesta. Hoy se aceptaría (hueco).
- Oferta `pending` con `expires_at` pasado: debe rechazarse (la condición ya existe; sin datos en Preview para probarla).
- Oferta `pending` vigente: debe aceptarse y asignar el viaje (control positivo).
- Dos conductores aceptando la misma solicitud: solo uno obtiene la asignación. El RPC usa `for update` sobre la oferta y la solicitud, y tras la primera aceptación la solicitud pasa a `driver_selected`; el segundo intento debe rechazarse.

No se ejecutaron estas pruebas: crear ofertas o solicitudes requiere autorización adicional, aun en transacciones revertidas.

## Estado de la rama aislada
- Creación de rama de Supabase (`qa-expiry-guard-20261016`): **rechazada** en el paso de confirmación de costo. No existe rama ni datos sintéticos. No se reintentó.
- Alternativa local: Docker está instalado pero el daemon está apagado. Un PostgreSQL local con esquema mínimo sirve para probar el bloqueo `for update` y los escenarios, pero no reproduce RLS ni triggers de producción.

## Nota sobre la prueba de vencimiento ya ejecutada
- Se ejecutó en la base compartida dentro de una transacción revertida (`raise` al final). No quedó ningún cambio persistente. Se registra por transparencia.
