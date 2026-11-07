# Migraciones cerradas (no aplicar)

Estas migraciones están en el repositorio por historial, pero **no se aplican**. No corresponden a la secuencia vigente.

| Migración | Motivo del cierre | Fecha |
|---|---|---|
| `20261007193000_production_traceability_hard_gate.sql` | Pertenece a una secuencia anterior de build de Google Play (138, 139...). Aplicarla reiniciaría el contador a 137/138, cuando hoy el contador está en 161 y la siguiente build es la 162. La trazabilidad vigente es la de las builds de Prueba interna y producción actuales. | 2026-11-07 |

Las migraciones aplicadas en producción no se editan ni se borran; por eso el archivo sigue en el repositorio.
