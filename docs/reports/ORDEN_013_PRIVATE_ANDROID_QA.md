# ORDEN 013 — Compilación QA privada (procedimiento, permisos y riesgos)

- Objetivo: poder compilar `ed4f1281` (PR #250) como APK QA **sin fusionar a `main`**, **sin Google Play**, **sin Release público** y **sin tocar workflows de Producción ni Supabase**.
- Estado: **investigación y propuesta. No se ha compilado nada. No se ha creado ningún Release, artefacto ni job. No se ha modificado Supabase ni ningún workflow existente.**
- Base de esta rama: `origin/main` = `95e22e27`.

## 1. Lo que impide compilar `ed4f1281` hoy (verificado en código)

El único camino de firma oficial está en `supabase/functions/android-build-worker/index.ts` y en `.github/workflows/build-android.yml`:

| Control | Dónde | Efecto para `ed4f1281` |
|---|---|---|
| Token OIDC solo desde `refs/heads/main` | `verifyGithub` (worker) | Un job desde la rama PR recibe rechazo. |
| Workflow permitido solo `build-android.yml@refs/heads/main` | `verifyGithub` (worker) | Cualquier workflow nuevo queda fuera sin cambiar el worker. |
| Acción `signing` devuelve el keystore oficial | worker, acción `signing` | Solo accesible con el token anterior. |
| Job aprobado por el propietario (`job_id`) y frase `AUTORIZO APK QA` | `build-android.yml` | Requisito que se mantiene. |
| Guardia de trazabilidad frente a `main` | `build-android.yml` | Bloquea cualquier diferencia de `lib/`, `assets/`, `pubspec` entre candidato y `main`. |
| Publicación con `gh release create` | `build-android.yml` | Crea Release del repositorio: **no admisible** para QA privada. |
| Tipos de artefacto `preview-apk*` rechazados | migración `20261014224000` | Un tipo nuevo requiere migración: **fuera de alcance** de esta orden. |

Conclusión: **no existe una ruta sin cambios** para firmar `ed4f1281` con la clave oficial. Cualquier alternativa necesita una decisión del propietario.

## 2. Lo que `build-android.yml` hace si no encuentra clave

Si la configuración de firma del worker devuelve `mode = create`, el paso de firma genera un keystore nuevo con `keytool -genkeypair` (líneas ~556-566). **Ese APK no es compatible con la app instalada de Google Play.** Una variante QA debe fallar si el modo no es `existing` con la clave oficial. Es un riesgo que hay que cerrar en cualquier variante nueva.

## 3. Compatibilidad de firma con la app instalada

- Google Play usa **Play App Signing**: el usuario final tiene la app firmada con la **clave de firma de la app** de Google, no con la clave de subida (*upload key*).
- Un APK firmado con la clave de subida **no actualiza** la app instalada desde Play: Android muestra «conflicto de paquete» o exige desinstalar.
- Desinstalar borra datos locales, sesión y permisos. **Prohibido** según la orden.
- Por tanto, la APK QA solo puede instalarse sobre la app de Play si está firmada con **la misma clave que Play** (que, en este proyecto, no está disponible en el repositorio).

Comprobación obligatoria antes de instalar (sin desinstalar):

1. Obtener el certificado SHA-256 de la app instalada desde un dispositivo de prueba, o desde la consola de Play («Integridad de la app» → certificado de firma de la app).
2. Obtener el SHA-256 del certificado de la APK candidata con `apksigner verify --print-certs`.
3. Solo si coinciden, instalar sobre la app existente. Si no coinciden: **instalar en un teléfono o perfil Android distinto** (ver §6).

## 4. Requisitos de permisos (los pide el propietario)

| Permiso | Quién | Para qué |
|---|---|---|
| Aprobar el job o la ejecución | Propietario | Confirma SHA y versión (1.6.2 / 140). |
| Crear entorno de GitHub `android-qa-private` con **regla de rama `main` únicamente** y revisor requerido | Propietario | Impide que una rama no confiable acceda a secretos de firma. |
| Secretos del entorno: keystore (base64), alias y contraseñas | Propietario | Firma oficial sin exponerla en código ni en ramas. |
| Autorizar cambio del worker (si se elige la ruta B) | Propietario | Añade una rama de QA privada al worker. Requiere despliegue de función, fuera de esta orden. |
| Autorizar fusión de la PR que añada el workflow de QA a `main` | Propietario | Necesario para que GitHub permita `workflow_dispatch` (solo desde la rama por defecto). |

Este agente **no** tiene ni debe pedir: claves de firma, contraseñas de keystore, tokens de Play ni credenciales de Supabase.

## 5. Opciones propuestas

### Opción 1 (recomendada): workflow de QA privado en `main` con entorno protegido

- Un workflow nuevo `android-qa-private.yml` (no modifica `build-android.yml`).
- `workflow_dispatch` con entradas: `source_sha` (40 hex), `confirm` = `AUTORIZO APK QA PRIVADA`, `expected_version` = `1.6.2+140`.
- Job con `environment: android-qa-private` (protegido: solo rama `main`, revisor = propietario).
- Permisos mínimos: `contents: read`. **Sin** `gh release`, sin `id-token`, sin acceso al worker.
- Verificaciones: el SHA del checkout = `source_sha`; `pubspec.yaml` = `expected_version`; firma debe venir de la clave oficial (`mode = existing`); `apksigner` debe mostrar el certificado esperado (SHA-256 almacenado como variable de entorno no secreta).
- Salida: **artefacto de Actions privado de retención corta (7 días)**. Atención: en un repositorio público cualquier usuario con acceso de lectura puede descargar artefactos de Actions. Por eso el artefacto solo es aceptable **si el repositorio es privado**. Si es público, la APK debe entregarse por un canal privado del propietario (no por GitHub).
- Requiere que el paso de compilación Flutter/Android reproduzca los mismos pasos que `build-android.yml` (generación de `android/`, branding, manifiesto). **Duplicar esos pasos es un riesgo de deriva**; la alternativa limpia es extraerlos a una acción compuesta usada por ambos workflows, lo que modifica `build-android.yml` y requiere autorización explícita.

### Opción 2: ruta B del informe ORDEN 012 (tipo QA en worker y migración)

Más invasiva: cambia el worker (función Supabase), la migración de tipos y la guardia. **No recomendada** mientras la Opción 1 no esté aprobada.

### Opción 3: merge de PR #250 a `main` y compilación oficial

Es la ruta más simple técnicamente, pero **queda fuera de esta orden** (no fusionar).

## 6. Instalación y teléfonos

- **Caso A, firma coincide con la app de Play:** instalar sobre la app existente. Verificar que la sesión, permisos y datos se conservan.
- **Caso B, firma no coincide (esperable con la clave de subida):** instalar en un **teléfono de prueba distinto** o en un **perfil secundario de Android** (Settings → Users → Add user / Work profile). Ambos aíslan la app; no hay que desinstalar la de producción.
- En ambos casos: usar cuentas de prueba (pasajero A, conductor B, pasajero C), nunca cuentas o zonas de Producción Taxi.
- Anotar modelo, versión de Android, SHA-256 de la APK y de la app instalada en el informe de prueba.

## 7. Aislamiento de usuarios, conductores y zonas

- Las cuentas y zonas de prueba deben ser las del entorno QA ya definido por el propietario. Esta orden no crea ni modifica cuentas.
- No se reutiliza la configuración de la app de Producción en el dispositivo QA; cuando el perfil es secundario, la sesión queda separada.
- No se activan funciones financieras (PR #222, #190), ni cobros ni premios reales.

## 8. Riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Firma con clave nueva generada por el workflow (`mode = create`) | APK no instalable sobre Play; confusión de QA | Fallar la compilación si el modo no es `existing`. |
| Clave oficial en rama no confiable | Compromiso de firma | Entorno con regla `main` únicamente y revisor; el workflow nace en `main`. |
| Artefacto público | APK accesible a terceros | Repositorio privado o canal privado; retención corta. |
| Release público | Distribución no autorizada | Prohibido; no se usa `gh release`. |
| Desinstalar la app de Play | Pérdida de datos y sesión | Prohibido; ver §3 y §6. |
| Deriva entre workflow QA y `build-android.yml` | QA no representa la APK real | Acción compuesta compartida (requiere autorización). |
| Cambio de fuente en `main` entre aprobación y compilación | APK no corresponde al SHA aprobado | Verificar `source_sha` y SHA del checkout; guardar hashes. |

## 9. Lo que se necesita del propietario para empezar

1. Elegir la opción (1, 2 o 3).
2. Confirmar si el repositorio es privado o público (determina dónde puede vivir la APK).
3. Crear el entorno `android-qa-private` con regla `main` y secretos (o autorizar al agente a documentar los nombres exactos sin valores).
4. Confirmar que la app de Play usa Play App Signing y facilitar el SHA-256 del certificado de firma **de la app** (no la clave de subida).
5. Autorizar la fusión de la PR que añada el workflow a `main`, si se elige la Opción 1.
6. Decir **«genera APK»** solo cuando todo lo anterior esté listo. La frase de autorización del workflow es `AUTORIZO APK QA PRIVADA`.

## 10. Restricciones respetadas

- Sin APK, sin AAB, sin Release, sin fusión a `main`, sin despliegue.
- Sin cambios en Supabase, migraciones ni worker.
- Sin cambios en `build-android.yml` ni en otros workflows de Producción.
- Sin claves de firma, contraseñas ni tokens en el repositorio o en esta rama.
