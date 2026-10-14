# Arquitectura única: una app, una web, Preview o Producción según la cuenta

> **Vigencia:** desde 2026-10-14. Esta guía prevalece sobre cualquier regla anterior de Express o Adminexpress que hable de dos páginas, dos APK, `ADMIN_ENV`, `PREVIEW_AUTHORIZED`, `PRODUCTION_AUTHORIZED` o ramas `preview/<slug>` permanentes.

## 1. Productos y artefactos

| Producto | Artefacto oficial | Repositorio | Estado al 2026-10-14 |
| --- | --- | --- | --- |
| Express Principal (Taxi, Envíos, Delivery cliente, conductor Taxi y Envíos) | Un APK/AAB `com.express.usuario1` y una web `https://expressviajes.online/` | `jorge2610g/Expressdelivery` | En uso. Candidato Android 1.6.1+140 firmado; QA física y publicación no confirmadas. |
| Express Admin | Una web `https://admin.expressviajes.online/` | `jorge2610g/Adminexpress` | En uso. Falta retirar código de dos entornos (§6). |
| Express Restaurante | Web y APK (por definir) | `jorge2610g/Express_Restaurante` | Definición documental; app no implementada. |
| Express Repartidor | APK | `jorge2610g/Express_Repartidor` | Repositorio inicial; app Flutter no migrada ni compilada. |

"Una sola app" significa **un solo artefacto por producto**. Los cuatro productos no se unen en uno; cada uno aplica la misma regla de entorno.

## 2. Regla central

- Preview y Producción son **contextos de datos**. La **cuenta autenticada** decide cuál usa. No lo decide la URL, un selector manual, un build ni un APK.
- Mismo código, misma web y mismo APK para ambos entornos.
- No existen: páginas `/preview/`, APK `com.express.usuario.preview` o `.qa`, `ADMIN_ENV`, ramas `preview/<slug>` permanentes ni `PREVIEW_AUTHORIZED` como mecanismo de publicación.

## 3. Qué se aísla y qué se comparte

**Aislado por cuenta (Preview):**
- Conductores de prueba: perfil, documentos, vehículos, estado en línea y ofertas.
- La zona de prueba asignada a esas cuentas.
- Solicitudes de taxi, envíos y pedidos creadas por cuentas de prueba: solo se asignan a conductores de prueba dentro de la zona de prueba. Nunca llegan a usuarios de Producción ni a conductores de Producción.

**Compartido (igual que Producción):**
- Pagos, billetera, suscripciones, tarifas, catálogo de servicios, comercios, usuarios y configuración global. Se muestran igual que en Producción.

**Escritura en datos compartidos: pendiente de confirmación del propietario.** Mientras no se confirme:
- Una cuenta Preview no modifica configuración compartida.
- Cualquier cambio de configuración compartida requiere orden expresa del propietario.
- Pagos, billetera y suscripciones además requieren el gate financiero independiente del contrato de 2026-10-09 (`docs/EXPRESS_PREVIEW_TO_PRODUCTION_MERGE_CONTRACT_2026-10-09.md`).

**Siempre, en cualquier entorno de prueba:** sin cobros reales, sin Mercado Pago real y sin notificaciones reales a usuarios.

## 4. Flujo de trabajo y de QA

1. Se desarrolla un solo código.
2. Se valida: análisis, pruebas, revisión de permisos y de aislamiento por cuenta.
3. Se publica una vez en la web canónica del producto. En Express, cada cambio en `lib/`, `web/` o `assets/` que llega a `main` publica la web (`.github/workflows/deploy-web.yml`).
4. El propietario prueba en la web con su cuenta Preview. Producción usa el mismo código al mismo tiempo.
5. Si algo falla, se corrige y se vuelve a publicar el mismo código. No se mantiene una versión solo para Preview.
6. Lo nativo de Android (permisos, notificaciones push, llamadas nativas, mapas y pagos nativos) se prueba después en el APK. Se genera un único APK/AAB oficial solo cuando el propietario lo pide. La promoción usa el mismo APK, sin recompilar (`docs/SINGLE_APP_WEB_FIRST_2026-10-08.md`).
7. Lo que no depende de Android se prueba y se despliega solo por la web.

## 5. Documentación

- `AGENTS.md` y esta guía mandan. Un documento anterior con reglas contrarias lleva un aviso de **superado** que apunta aquí. Los históricos no se borran.
- Cada cambio funcional deja entrada en `docs/CHANGELOG_ACTIVE.md`.

## 6. Cómo retomar las apps pendientes

- **Restaurante:** implementar la tabla de requisitos del README del repositorio (pedidos, detalle, catálogo, inventario y horarios, promociones, liquidaciones). Usar el mismo backend con aislamiento por negocio, zona y cuenta. Siguiente paso propuesto: acceso y lista de pedidos en web.
- **Repartidor:** migrar la app Flutter desde el código extraído. Solo recibe pedidos comerciales, nunca taxi ni envíos entre personas. Push y despacho con sus compuertas de seguridad propias. Siguiente paso propuesto: login y lista de pedidos en web.
- **Admin:** retirar el código que todavía usa `ADMIN_ENV`, `_previewScopedModules` y rutas de dos entornos, y dejar solo el aislamiento por cuenta. Siguiente paso propuesto: quitar esos guards y probarlo con una cuenta Preview.
- **Express Principal:** revisar los PR abiertos (#222, #228, #232, #233, #234, #236) y completar la QA física del APK 1.6.1+140 antes de publicarlo.

## 7. Contradicciones corregidas

| Regla antigua | Regla vigente | Dónde se corrigió |
| --- | --- | --- |
| Dos páginas: `/` producción y `/preview/` | Una web por producto | Cabecera de `AGENTS.md`; aviso en documentos antiguos |
| APK Preview y APK paralelo | Un APK oficial, solo si se pide | Cabecera de `AGENTS.md`; `SINGLE_APP_WEB_FIRST_2026-10-08.md` |
| Ramas `preview/<slug>` permanentes | El mismo commit se valida con cuenta Preview | Aviso en `PREVIEW_PRODUCTION_PARITY_RULE.md` (Adminexpress) |
| Filtrar para la cuenta de prueba zonas, tarifas, viajes, pedidos, comercios, conductores, premios, documentos, liquidaciones, permisos y operaciones (`AGENTS.md` de Adminexpress, línea 19) | Solo conductores, zona de prueba y solicitudes de prueba se aíslan | §3 de esta guía |
| Preview bloquea pagos (changelog de Adminexpress, 2026-10-09) | Pagos se muestran igual que en Producción; escritura pendiente de confirmación | §3 de esta guía |

## 8. Decisiones pendientes del propietario

1. ¿La cuenta Preview puede escribir configuración compartida (pagos, suscripciones, tarifas) o solo verla?
2. ¿En qué rama se publica esta documentación: la designada (`claude/express-admin-audit-cp07ml`, lejos de `main`) o una rama nueva desde `main` para revisarla y fusionarla?

## 9. Copias de seguridad (obligatorio)

- Antes de cualquier cambio de código o documentación se crea una copia de seguridad en **cada repositorio afectado**: una rama `backup/<tema>-<fecha>` que apunta al commit actual, subida al remoto.
- Repositorios: `jorge2610g/Expressdelivery` (app Express y web Express) y `jorge2610g/Adminexpress` (web Admin). Restaurante y Repartidor se respaldan igual cuando se modifiquen.
- Copias vigentes al 2026-10-14:
  - Express: `backup/main-20261014` (producción, `94d035b`), `backup/pre-arquitectura-unica-20261014` (antes de esta guía, `d328b7d`) y `backup/pre-regla-copias-20261014` (antes de esta sección, `b3ac317`).
  - Admin: `backup/main-20261014` (producción, `ea3dae4`).
- Para restaurar: crear una rama de trabajo desde la copia (`git switch -c restaurar/<tema> origin/backup/<tema>-<fecha>`) y verificarla. No se reescribe una rama compartida (`--force`) sin orden expresa del propietario.
