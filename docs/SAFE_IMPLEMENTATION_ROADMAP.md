## Guardia adicional de SQL (propuesta en PR, 2026-10-09)

GitHub Actions `Validate Account Runtime Routing` ejecutará
`.github/scripts/guard_migration_safety.py` en PRs que toquen migraciones.
El script compara contra el SHA base y detiene cambios a archivos de migración
existentes y operaciones SQL potencialmente destructivas evidentes. Esta
comprobación estática es deliberadamente conservadora: **no aplica migraciones**,
no verifica automáticamente todos los efectos indirectos, no reemplaza pruebas
aisladas ni autoriza publicación a Producción.

Las migraciones aditivas siguen necesitando revisión de locks, índices,
seguridad RLS, costo de consultas, compatibilidad entre APK instaladas
y backout plan. Si se necesita romper compatibilidad, hacerlo primero en
la base de pruebas aislada y documentar una secuencia expand/migrate/contract
con aprobación explícita. **Sin cambios en base real por esta mejora de CI.**

---

# ROADMAP SEGURO — Express

> Flujo obligatorio para implementar mejoras sin romper lo que ya funciona.
>
> Inicio de esta metodología: 2026-10-02.

## Copia de seguridad inicial

Antes de empezar este roadmap se creó una copia exacta del estado estable:

- Expressdelivery: `backup/2026-10-02-roadmap-baseline`
- Adminexpress: `backup/2026-10-02-roadmap-baseline`

Estas ramas NO se usan para desarrollar. Solo sirven para recuperación.

---

# Regla principal

**Nunca trabajar varias funciones grandes al mismo tiempo.**

Cada módulo debe pasar por estas 8 puertas:

1. RESPALDAR
2. CREAR
3. PROBAR EN CÓDIGO
4. PROBAR EN PREVIEW / QA
5. APROBACIÓN MANUAL
6. LANZAR
7. MONITOREAR
8. CERRAR O REVERTIR

Si una puerta falla, no se avanza a la siguiente.

---

# Flujo obligatorio por tarea

## PASO 0 — RESPALDAR

Antes de tocar código:

- Guardar SHA estable de Expressdelivery.
- Guardar SHA estable de Adminexpress si participa.
- Crear rama:
  - `backup/YYYY-MM-DD/<tarea>-pre`
- Verificar últimas migraciones Supabase.
- Registrar versión Preview actual.
- Registrar versión Android producción actual.
- Registrar último deploy web/admin.
- Confirmar que QA actual esté verde o documentar fallos ya existentes.

### Regla de base de datos

Toda migración nueva debe ser:

- versionada en `supabase/migrations/`;
- incremental;
- compatible hacia atrás cuando sea posible;
- probada primero de forma transaccional;
- acompañada de rollback lógico o procedimiento de recuperación.

Nunca borrar columnas/tablas de producción en la primera entrega de una función.

---

## PASO 1 — CREAR

Crear una rama aislada:

`feature/<numero>-<nombre>`

Reglas:

- no desarrollar directamente sobre `main`;
- una función grande por rama;
- usar feature flags cuando la función pueda afectar tráfico real;
- valores nuevos deben quedar desactivados por defecto si todavía no están aprobados;
- QA y producción deben seguir aislados.

### Regla obligatoria App ↔ Admin

Toda función nueva que introduzca valores editables, estados administrables,
reglas, precios, límites, planes, textos operativos, permisos o activación debe
implementarse en el mismo ciclo en:

1. Backend / Supabase como fuente de verdad.
2. App Pasajero/Conductor cuando corresponda.
3. Adminexpress para crear, editar, activar, desactivar, asignar y auditar.
4. QA/Preview para validar ambos lados juntos.

No se considera completa una funcionalidad configurable si existe solo en la
app o solo en Adminexpress.

Excepción: elementos puramente visuales o internos sin configuración de
negocio.

### Regla de caché y rendimiento

Clasificar cada dato antes de implementarlo:

**Puede cachearse localmente:**
- configuración pública/runtime;
- catálogo de servicios;
- zonas públicas;
- textos y catálogos;
- preferencias visuales;
- datos semiestáticos que toleren algunos minutos de desfase.

**Solo caché corta en memoria:**
- perfil del usuario/conductor;
- vehículo;
- datos personales no financieros.

**Siempre backend/realtime:**
- viajes activos;
- ofertas;
- disponibilidad crítica;
- suscripción vigente;
- wallet/saldo;
- pagos;
- SOS;
- estados de cobro;
- permisos/seguridad;
- información que determine acceso o dinero.

Toda caché debe tener TTL, invalidación después de editar y fallback seguro al
backend. Nunca debe impedir que una actualización del administrador termine
sincronizándose.

---

## PASO 2 — PROBAR EN CÓDIGO

Antes de Preview:

- `flutter analyze`;
- compilación web;
- pruebas SQL/RPC;
- revisión RLS;
- validación de Supabase Advisors si cambia seguridad;
- comprobar rutas pasajero/conductor;
- comprobar que no se mezclen QA y producción;
- comprobar que funciones antiguas sigan operativas.

### Pruebas mínimas de regresión

- Login.
- Pasajero.
- Conductor.
- Crear viaje.
- Ver solicitud.
- Ofertar.
- Seleccionar oferta.
- Iniciar viaje.
- Completar.
- Cancelar.
- Push.
- Wallet.
- Ganancias.
- Historial.
- Perfil.
- Ayuda.
- Modo oscuro.
- Delivery existente.
- Adminexpress.
- Sandbox QA.

---

## PASO 3 — PREVIEW / QA

Toda función debe probarse primero en:

- Express Preview;
- cuentas QA aisladas;
- Adminexpress si corresponde.

No se debe generar APK/AAB de producción solo por hacer pruebas.

Checklist:

- QA automático verde.
- Preview compila.
- Función nueva visible solo donde corresponde.
- Usuarios reales no reciben tráfico de prueba.
- No aparecen errores en logs.
- No hay duplicación de push.
- No hay regresiones visuales.
- Tema claro y oscuro.
- Android real.

---

## PASO 4 — APROBACIÓN MANUAL

La tarea queda en estado:

`READY FOR APPROVAL`

No se lanza producción hasta recibir aprobación explícita.

Registrar:

- commit exacto aprobado;
- capturas/pruebas realizadas;
- errores conocidos;
- migraciones incluidas;
- método de rollback.

---

## PASO 5 — LANZAR

Orden recomendado:

1. Migraciones compatibles.
2. Edge Functions / backend.
3. Web.
4. Adminexpress.
5. Preview estable.
6. Android producción solo cuando se solicite.
7. AAB/Play Console solo cuando corresponda.

Nunca mezclar un release de funcionalidad con cambios de branding, dependencias o refactors grandes si pueden separarse.

---

## PASO 6 — MONITOREAR

Después de producción:

### Primeros 15 minutos
- errores críticos;
- login;
- creación de viaje;
- matching;
- push;
- pagos;
- logs.

### Primera hora
- errores nuevos;
- tiempos de respuesta;
- cancelaciones anómalas;
- solicitudes atascadas;
- errores Supabase.

### Primeras 24 horas
- métricas;
- reportes;
- quejas;
- regresiones;
- consumo backend.

---

## PASO 7 — ROLLBACK

Si existe un fallo crítico:

1. detener rollout;
2. desactivar feature flag si existe;
3. volver al commit estable;
4. usar rama `backup/...-pre`;
5. revertir backend de manera compatible;
6. no borrar datos creados por usuarios sin análisis;
7. documentar causa;
8. crear fix aislado;
9. volver a Preview.

---

## PASO 8 — CERRAR

Una tarea solo se cierra cuando:

- QA verde;
- aprobación manual;
- producción estable;
- documentación actualizada;
- CABGO_REFERENCE actualizado si cambia la comparación;
- backup post-release registrado.

Crear rama estable opcional:

`backup/YYYY-MM-DD/<tarea>-post`

---

# ORDEN DE IMPLEMENTACIÓN

## FASE 1A — Progressive dispatch y reasignación

Objetivo:

- hacer real el modo progressive;
- ampliar radio por etapas;
- reasignar automáticamente;
- métricas de dispatch.

No tocar pagos en esta fase.

---

## FASE 1B — Pagos, retiros, espera y recibos

Objetivo:

- gateway real;
- retiros conductor;
- cobro de espera configurable;
- recibo PDF;
- conciliación base.

No tocar marketplace Delivery en esta fase.

---

## FASE 1C — Identidad, ETA y trazabilidad

Objetivo:

- proveedor facial;
- liveness;
- vencimiento documentos;
- ETA mejorado;
- histórico GPS.

---

## FASE 2 — Delivery marketplace

Dividir internamente:

1. Negocios.
2. Catálogo.
3. Productos.
4. Carrito.
5. Extras.
6. Horarios.
7. Preparación.
8. Asignación repartidor.
9. Código pickup.
10. Código entrega.
11. Evidencia.
12. Propina.
13. Comisión negocio.
14. Reportes negocio.

No liberar todo de golpe.

---

## FASE 3 — Crecimiento

Orden:

1. Cupones.
2. Referidos.
3. Lealtad.
4. Bonos.
5. Promociones.
6. Publicidad.

---

## FASE 4 — Admin avanzado

Orden:

1. Roles.
2. Permisos.
3. Exportaciones.
4. Reportes avanzados.
5. Branding editable.
6. Plantillas.

---

## FASE 5 — B2B / White-label / iOS

Orden:

1. Empresa B2B.
2. Centros de costo.
3. Empleados.
4. Facturación consolidada.
5. Base multi-tenant.
6. White-label.
7. iOS/TestFlight.

---

# Política de seguridad de releases

## Prohibido

- hacer cambios grandes directamente en producción;
- reemplazar migraciones ya aplicadas;
- borrar tablas como forma de rollback;
- compilar APK de producción sin solicitud;
- mezclar cuentas QA con usuarios reales;
- lanzar una función sin rollback definido;
- cerrar una tarea solo porque compila.

## Obligatorio

- backup pre;
- rama feature;
- QA;
- Preview;
- aprobación;
- release identificable por commit;
- monitoreo;
- backup post.

---

# Estado

- [x] Comparativa CabGo actualizada.
- [x] Backup baseline Expressdelivery.
- [x] Backup baseline Adminexpress.
- [x] Roadmap seguro creado.
- [ ] Fase 1A.
- [ ] Fase 1B.
- [ ] Fase 1C.
- [ ] Fase 2.
- [ ] Fase 3.
- [ ] Fase 4.
- [ ] Fase 5.
