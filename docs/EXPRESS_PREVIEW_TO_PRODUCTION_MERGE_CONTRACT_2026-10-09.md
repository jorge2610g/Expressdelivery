# Express — contrato verificable Preview → Producción
**Versión de diseño: 2026-10-09. Estado: objetivos propuestos + controles existentes confirmados; NO equivale a certificación de aislamiento.**

## 1. Arquitectura objetivo sin duplicar aplicaciones

```text
                     GITHUB
       Expressdelivery                 Adminexpress
       única lógica Flutter            único panel Flutter
       └─ PR → QA → main              └─ PR → QA → main
                │                              │
      ┌─────────┴──────────┐       ┌───────────┴──────────┐
      │ Web QA / código    │       │ /preview/ QA         │
      │ + APK QA puntual   │       │ mismo código/panel   │
      │ APK/AAB firmado    │       │ / Producción         │
      │ candidato real     │       │ URL raíz             │
      └─────────┬──────────┘       └───────────┬──────────┘
                │                              │
                └─────────────┬────────────────┘
                              │
            BACKEND SUPABASE + autorización de servidor
                 ┌────────────┴────────────┐
                 │                         │
        Preview / solo QA           Producción / datos reales
        cuentas sintéticas          clientes y conductores
        configuración shadow        viajes / pedidos
        sin pagos reales            pagos y wallet real
                 │                         │
               TESTS                RELEASE CONTROLADO
```

Hoy los **dos sitios Admin** se conectan al Supabase físico de Producción
`zgpijrznvaskgcmauwxx`; `/preview/` utiliza un canal lógico, *no*
un proyecto físico separado. El proyecto físico QA
`xbphilqezmwfjfpdbwad` existe, pero no es la conexión actual de
ambos sitios. No cambiar URLs ni claves de golpe ni forzar
reconfiguraciones desde cero. El límite real de datos lo impone el
servidor, **no el color del botón, un parámetro manipulable o un nombre
de URL**.

Los flujos de pasajeros, conductores, Delivery, GPS, mapa, suscripciones,
tarifas y notificaciones comparten implementación Flutter y deben
continuar con *una única fuente de código*. No agregar una segunda app
permanente. Si hace falta certificación Android, compilar temporalmente
para QA, y antes de publicar probar el propio **candidato real firmado**
com.express.usuario1, APK y AAB generados desde el mismo SHA y retenidos
sin recompilar después de aprobar.

## 2. Qué se promociona y qué NUNCA se copia automáticamente

| Capa | Qué puede pasar de QA a producción | Qué NO debe copiarse |
|---|---|---|
| Código Flutter app | PR revisada, SHA exacto, tests y artefacto firmado | versión lógica paralela de Preview |
| Código Admin | las mismas pantallas con configuración/guardias por entorno | mezcla de bundles web con código no aprobado |
| Funciones backend | **nueva versión/migración revisada** y compatible, secuencia de despliegue | sobrescritura directa de funciones activas sin QA |
| Esquema SQL/RLS | migraciones aditivas ordenadas, auditadas y probadas | importar tablas/datos QA ni borrar columnas existentes |
| Países, zonas, polígonos y tarifas QA | propuesta de cambio **por campo**, comparación antes/después y aprobación separada | sobrescribir automáticamente datos reales con `admin_environment_config` |
| Conductores/clientes/viajes/pedidos | NADA: permanecen en su canal | usuarios ficticios, solicitudes QA, GPS o historial |
| Wallet / pagos / suscripciones | configuración aprobada solo con gate financiero independiente | dinero, saldos, tokens, cobros, webhooks o pagos de prueba |
| APK/AAB / Google Play | binarios candidatos **idénticos por hash** a los validados | compilar otro AAB después del QA y declarar que es el mismo |

**Importante:** `git merge` no traslada datos ni configuración de
Supabase. Habilitar una nueva zona/país en Preview no la habilita
automáticamente en Producción; se necesita una operación administrativa
expresa y auditable, con diff de valores, destino exacto y rollback.

## 3. Cadena de evidencia exigible antes de fusionar

Para cada cambio hay que guardar una ficha de entrega:

- ID de PR + descripción de objetivo, alcance y archivos afectados.
- SHA de commit de **PR head**, SHA de **base** y SHA del **checkout probado**
  (Actions puede usar un commit sintético de merge).
- Hash del árbol Git probado y manifiesto de todos los archivos
  agregados/editados/eliminados, clasificación de riesgo y SHA-256 de
  contenido por archivo.
- Listado explícito de migraciones SQL, Edge Functions, cambios de
  configuración y permisos; referencia de backups y plan de rollback.
- Resultados de CI + QA de UI, cliente, conductor y backend; pruebas
  de autorización cruzada y compatibilidad de APK antiguo.
- Aprobación explícita del cambio exacto y de qué se habilita en
  Producción; no autoactivar nuevas funciones importantes.
- SHA FINAL integrado en `main`, reconstruir/verificar inventario y
  comparar con el candidato probado. Si squash/merge cambia SHA,
  comprobar la identidad del *contenido* y repetir gates necesarios.
- Hash SHA-256 de cada artefacto APK y AAB **ya firmado**, ID del job,
  versión/versiónCode, package, certificado de firma, cuenta de QA,
  certificación y registro del release/publish.

El nuevo script `.github/scripts/release_change_manifest.py` prepara
el inventario para PRs y el workflow
`.github/workflows/release-change-inventory.yml` lo ejecuta para **cada PR**
a `main` y lo adjunta como artefacto de Actions. GitHub CI verifica
que el SHA del checkout sea un merge de los SHA exactos de base y cabeza
del PR; si alguno no coincide, bloquea la comprobación. Es **solo trazabilidad estática**:
**no es una garantía de compatibilidad funcional** y no analiza cambios
que un operador haga directamente en el Dashboard de Supabase.

## 4. Gates de seguridad (propuesta para cierre definitivo)

**G0 Respaldo:** tag/branch de ambos repos + versión del deploy web;
backup consistente de la base antes de migraciones/operaciones de
configuración reales; registro de última versión Android publicada.

**G1 Código y diff:** cada PR con scope limitado, inventario de archivos,
revisión de cambios no esperados y cero secretos.

**G2 Compilación:** flutter analyze, flutter test, smoke Web/Admin en
ambos modos; CI independiente para migraciones, permisos y funciones.

**G3 Aislamiento backend (BLOQUEANTE):** cuentas QA no pueden cambiar
ninguna zona, tarifa, documento, pago, wallet o dato de Producción ni
si intentan llamar directamente una RPC obsoleta. Corregir RPC legacy
`SECURITY DEFINER` sin canal y ensayar permisos en la base de QA.
Por ahora **NO SUPERADO**; issue #141, draft PR #144.

**G4 QA de operación:** registro conductor con aprobación manual y
actualización automática de estado; ubicación/caché; login/registro;
pedido o viaje completo; cancelación; push; panel en vivo; radio vs
polígono exclusivos; cambios por moneda/país; caídas de conectividad;
cuentas QA y reales.

**G5 Promoción diferenciada:** código a main desde el SHA revisado,
funciones/SQL con respaldo y migraciones compatibles aprobadas;
configuración geográfica solo por diff aprobado; mantener flags
apagados hasta finalizar QA; QA Android sobre binarios finales firmados.

**G6 Vigilancia/rollback:** detectar errores, impacto por zona/país,
latencia y fallos de auth; desactivar por feature flag; rollback del
sitio a un artefacto anterior; DB usa migraciones de corrección /
restauración planificada, no borrado instantáneo; Android Play exige
nuevo release para deshacer código ya instalado.

**G7 Evidencia final:** firma de release y registro de PR, SHA,
hashes, versión, backup, pruebas, fecha, persona que aprobó y
mecanismo de reversión ejecutable.

## 5. Qué puede garantizarse realmente

- **Identificación 100 % auditable de archivos** del diff de Git
  probado: sí, si se congela PR/base y se conserva el manifiesto con
  los hashes y se comprueba nuevamente tras el merge.
- **Identidad byte a byte del APK/AAB publicado y del aprobado:** sí,
  si se promocionan los mismos archivos firmados sin recompilar y se
  comprueba su SHA-256 con la referencia de distribución.
- **Identidad de configuración efectiva y datos de Producción:** no la
  proporciona Git. Requiere inventario/diff de valores, autorización,
  migraciones controladas y comprobaciones de datos en Supabase.
- **Cero errores o cero interrupciones:** ninguna cifra o garantía de
  100 % sería honesta. Las pruebas reducen el riesgo, no lo eliminan.

## 6. Estado actual y decisión de seguridad

- Expressdelivery: PR #142 (guardia de migraciones + inventario);
  PR #144 (propuesta SQL no aplicada).
- Adminexpress: PR #51 (enrutamiento de editores QA).
- Los tres permanecen en **draft**, sin merge, sin cambios en `main`
  ni despliegues de esta fase a Producción.
- La inspección de solo lectura detectó RPC sin canal que pueden
  escribir configuración real desde administradores autorizados.
  Inventario: `docs/backend_patches/UNSCOPED_ADMIN_CONFIG_WRITERS_2026-10-09.md`.
- La PR de cobertura SQL tiene CI estático verde, pero **NO** pasó
  una prueba real de aislamiento servidor/roles. No desplegarla por
  considerarla segura solo porque las pruebas de texto pasaron.

El compromiso técnico es **identificar exactamente lo que cambiará,
probarlo, tener la opción de no lanzarlo y medir su impacto**. No
confundirlo con una promesa imposible de cero fallos.
