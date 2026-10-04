# Snapshot previo — Express Delivery V2

Fecha: 2026-10-03 (America/Santiago)

Este archivo documenta el estado conocido **antes** de crear el bloque V2.

## Git

### Express app

- repo: `jorge2610g/Expressdelivery`
- SHA congelado: `9f506b027a320d18e0d6d0a22c97db1588f862ae`
- backup:
  `backup/pre-express-delivery-v2-2026-10-03`

Ese SHA correspondía al candidato Express Delivery V1 ya publicado en Preview
como Shorebird Preview 1.5.82+126 Patch 12.

### AdminExpress

- repo: `jorge2610g/Adminexpress`
- SHA de main congelado:
  `5443da47f4d046898009344ffb040376cbc5685a`
- backup:
  `backup/pre-express-delivery-v2-2026-10-03`

El candidato previo de naming/Delivery completo estaba además en
`feature/express-delivery-complete-flow`.

## Supabase

Proyecto correcto:

`zgpijrznvaskgcmauwxx`

Estado previo relevante:

- Marketplace global: Preview ON, Producción OFF.
- Iquique: Preview ON, Producción OFF, CL / CLP.
- Trinidad: Preview ON, Producción OFF, BO / BOB.
- 6 categorías Marketplace.
- 4 comercios Preview.
- 10 productos.
- migraciones aplicadas hasta 084.
- migraciones 085–088 NO aplicadas al tomar este snapshot.

## Política de restauración

Si el candidato V2 debe descartarse antes de aplicar DB:

1. restaurar los backups de Git;
2. borrar/ignorar ramas feature V2;
3. no ejecutar 085–088.

No se debe cambiar moneda, país, wallet ni datos históricos para “revertir”
V2 porque V2 no modifica esos datos en el backend mientras siga sin aplicarse.

## Nota

Las pruebas SQL de V2 usan transacciones con ROLLBACK. Los pedidos/cupones/PIN
sintéticos usados durante QA no persisten.
