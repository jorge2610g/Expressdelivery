# CabGo como referencia funcional para Express

> Documento vivo de referencia de producto.
>
> CabGo se usa como inspiración de arquitectura, flujos y módulos. No se debe copiar su marca, identidad visual propietaria ni código fuente.
>
> Última auditoría funcional: 2026-10-02.

## Fuentes públicas revisadas

- https://www.cabgo.app/es
- https://www.cabgo.app/es/funcionalidades
- https://www.cabgo.app/es/plataforma
- https://www.cabgo.app/es/plataforma/dashboard
- https://www.cabgo.app/es/plataforma/cabgo-app
- https://www.cabgo.app/es/personalizacion
- https://www.cabgo.app/es/resellers
- https://www.cabgo.app/es/docs/arquitectura/jerarquia-configuraciones

## Objetivo Express

Express debe evolucionar hacia una plataforma integral de movilidad y delivery administrada desde un dashboard central, con una app unificada para:

1. Pasajero.
2. Cliente de Delivery.
3. Conductor.
4. Repartidor.

La arquitectura actual se divide en:

### Express App
- Pasajero.
- Conductor.
- Delivery.
- Mapa.
- GPS.
- Ofertas y tarifa fija.
- Historial.
- Wallet.
- Soporte.
- Calificaciones.
- Seguridad.

### Express Admin
- Dashboard.
- Operación en vivo.
- Viajes.
- Delivery.
- Conductores.
- Usuarios.
- Seguridad / SOS.
- Zonas.
- Tarifas.
- Pagos / Billetera.
- Reportes.
- Configuración.
- Builds.
- Despacho manual.
- Auditoría.
- Soporte / Avisos.
- Servicios.
- Cobertura y seguridad.
- Verificación de identidad.
- Configuración avanzada.
- Entornos de prueba.

### Backend Express / Supabase
- Auth.
- Realtime.
- Tarifas.
- Zonas y polígonos.
- Dispatch.
- Wallet.
- Pagos.
- Notificaciones.
- Push.
- Seguridad.
- Auditoría.
- Builds.
- QA sandbox.
- Reglas operativas configurables.

---

# Estado funcional actual

Leyenda:

- ✅ Completo o ya operativo.
- 🟡 Existe parcialmente o requiere terminar integración.
- ❌ Pendiente.

## App unificada

| Función | Estado | Nota |
|---|---:|---|
| Pasajero + conductor en una sola app | ✅ | Operativo |
| Taxi + Delivery | ✅ | Delivery básico |
| Mapa principal | ✅ | Incluye modo oscuro |
| GPS en vivo | ✅ | Operativo |
| Origen y destino | ✅ | Operativo |
| Autocomplete de ubicación | ✅ | Operativo |
| Ruta | ✅ | Operativo |
| Tarifa fija | ✅ | Operativo |
| Pasajero propone precio | ✅ | Operativo |
| Conductor contraoferta | ✅ | Operativo |
| Viajes programados | ✅ | Operativo |
| Conductores cercanos | ✅ | Operativo |
| Tracking del viaje | ✅ | Operativo |
| Chat durante servicio | ✅ | Operativo |
| Chat de soporte | ✅ | Operativo |
| Llamadas | ✅ | Configurable |
| Push Android | ✅ | Operativo |
| Notificaciones internas | ✅ | Operativo |
| Calificaciones privadas/anónimas | ✅ | Operativo |
| Resumen de calificaciones | ✅ | Operativo |
| Historial | ✅ | Operativo |
| Cancelación con motivo | ✅ | Operativo |
| PIN para iniciar viaje | ✅ | Operativo |
| Aviso de llegada del conductor | ✅ | Operativo |
| Espera de recogida | ✅ | Flujo implementado |
| SOS | ✅ | Operativo |
| Compartir viaje | ✅ | Configurable |
| Contactos de confianza | ✅ | Tabla y flujo existentes |
| Lugares guardados | ✅ | Configurable |
| Wallet | ✅ | Operativo |
| Ganancias conductor | ✅ | Operativo |
| Comisión conductor | ✅ | Liquidación automática |
| Recargas wallet | ✅ | Aprobación administrativa |
| Efectivo | ✅ | Operativo |
| Tarjeta | 🟡 | UI/config disponible; falta gateway real |
| Mercado Pago | 🟡 | Configurable; integración transaccional pendiente |
| PagoRUT / MACH / Tenpo / Santander | 🟡 | Configurables; falta integración real |
| Documentos conductor | ✅ | Registro y administración |
| Verificación facial | 🟡 | Backend/política preparados; proveedor automático pendiente |
| Liveness | 🟡 | Configurable; proveedor pendiente |
| Login Google / Apple | ❌ | Pendiente |
| Multi-parada | ❌ | Pendiente |
| Propinas | ❌ | Pendiente |
| Recibo PDF | ❌ | Pendiente |
| Retiro real de conductor | ❌ | Pendiente |

---

# Dispatch

## Ya existe

- ✅ Solicitudes por proximidad.
- ✅ Radio configurable.
- ✅ Timeout configurable.
- ✅ Máximo de solicitudes visibles.
- ✅ Filtro por servicio.
- ✅ Filtro por zona.
- ✅ Filtro por vehículo.
- ✅ Asignación manual desde Admin.
- ✅ Broadcast configurable.
- ✅ Modo progressive visible/configurable en Admin.
- ✅ Modo manual visible/configurable en Admin.
- ✅ Sandbox QA aislado de producción.
- ✅ Bloqueo de despacho cruzado QA ↔ producción.

## Falta cerrar

- 🟡 Progressive dispatch real de extremo a extremo.
- 🟡 Expansión automática de radio por etapas.
- 🟡 Reasignación automática completa cuando nadie acepta.
- 🟡 Métricas específicas de eficiencia de dispatch.
- ❌ Estrategias por prioridad/demanda/hora.

---

# Tarifas

## Ya existe

Jerarquía actual:

1. Global.
2. Por servicio.
3. Zona + servicio.

Parámetros actuales:

- ✅ Tarifa base.
- ✅ Precio por km.
- ✅ Precio por minuto.
- ✅ Tarifa mínima.
- ✅ Multiplicador surge.
- ✅ Comisión %.
- ✅ Activar/desactivar regla.
- ✅ Motor de cotización desde backend.
- ✅ Configuración desde Admin.

## Falta ampliar

- 🟡 Surge automático por horario/día/demanda.
- ❌ Tarifas fijas entre zonas.
- ❌ Service fee separado.
- ❌ Propinas.
- ❌ Reglas promocionales/cupons.

---

# Zonas y seguridad geográfica

## Ya existe

- ✅ Zonas de operación.
- ✅ Polígonos de cobertura.
- ✅ Activar/desactivar zonas.
- ✅ Zonas rojas.
- ✅ Zonas de precaución.
- ✅ Zonas seguras.
- ✅ Aplicar por pasajero/conductor.
- ✅ Severidad.
- ✅ Mensajes por zona.
- ✅ Política geográfica runtime desde Supabase.

## Falta ampliar

- ❌ Métodos de pago por zona.
- ❌ Vehículos permitidos por zona.
- ❌ Horarios por zona.
- ❌ Tarifas fijas entre zonas.

---

# Conductores

## Ya existe

- ✅ Registro.
- ✅ Perfil conductor.
- ✅ Vehículo.
- ✅ Licencia/documentos.
- ✅ Aprobación.
- ✅ Rechazo.
- ✅ Suspensión/estado de cuenta.
- ✅ Online / offline / busy.
- ✅ Ubicación.
- ✅ Calificación.
- ✅ Viajes completados.
- ✅ Ganancias.
- ✅ Wallet.
- ✅ Historial.
- ✅ Control desde Admin.
- ✅ Verificación de identidad preparada.
- ✅ Face match configurable.
- ✅ Liveness configurable.

## Falta ampliar

- ❌ Alertas automáticas de vencimiento de documentos.
- ❌ Proveedor biométrico real.
- ❌ Retiro bancario.
- ❌ Bonos/promociones automáticas.
- ❌ Programa de referidos conductor.

---

# Delivery

## Ya existe

- ✅ Delivery punto A → B.
- ✅ Cliente.
- ✅ Repartidor.
- ✅ Crear solicitud.
- ✅ Tarifa.
- ✅ Pago.
- ✅ Tracking.
- ✅ Estados.
- ✅ Cancelación.
- ✅ Historial.
- ✅ Chat.
- ✅ Asignación manual.
- ✅ Claim de repartidor.
- ✅ Aislamiento QA.

## Falta para alcanzar un marketplace completo

- ❌ Negocios.
- ❌ Restaurantes/comercios.
- ❌ Catálogo.
- ❌ Categorías.
- ❌ Productos.
- ❌ Extras y variaciones.
- ❌ Carrito.
- ❌ Horarios de negocio.
- ❌ Tiempo de preparación.
- ❌ Pedidos en vivo por negocio.
- ❌ Código de recogida.
- ❌ Código de entrega.
- ❌ Evidencia fotográfica.
- ❌ Propina.
- ❌ Pickup sin repartidor.
- ❌ Comisiones por negocio.
- ❌ Reportes por negocio.

---

# Panel Administrativo Express

## Menú actual

- ✅ Dashboard.
- ✅ Operación en vivo.
- ✅ Viajes.
- ✅ Delivery.
- ✅ Conductores.
- ✅ Usuarios.
- ✅ Seguridad / SOS.
- ✅ Zonas.
- ✅ Tarifas.
- ✅ Pagos / Billetera.
- ✅ Reportes.
- ✅ Configuración.
- ✅ Builds.
- ✅ Despacho manual.
- ✅ Auditoría.
- ✅ Soporte / Avisos.
- ✅ Servicios.
- ✅ Cobertura y seguridad.
- ✅ Verificación de identidad.
- ✅ Configuración avanzada.
- ✅ Entornos de prueba.

## Falta agregar

- ❌ Negocios.
- ❌ Promociones.
- ❌ Referidos.
- ❌ Publicidad.
- ❌ Permisos granulares.
- ❌ Branding editable.
- ❌ Plantillas de comunicación.
- ❌ Portal B2B.
- ❌ Facturación.
- ❌ Reportes avanzados/exportables.

---

# Dashboard

## Ya existe

- ✅ Viajes activos.
- ✅ Viajes hoy.
- ✅ Conductores.
- ✅ Conductores online.
- ✅ Solicitudes buscando.
- ✅ Delivery.
- ✅ SOS.
- ✅ Mapa operativo.
- ✅ Actividad en vivo.

## Falta mejorar

- ❌ Ingresos/comisiones en gráficas.
- ❌ Cancelaciones por período.
- ❌ Tasa de aceptación.
- ❌ Tiempo promedio de asignación.
- ❌ Tiempo promedio de llegada.
- ❌ Heatmaps.
- ❌ Comparativas semanales/mensuales.

---

# Operación en vivo

## Ya existe

- ✅ Conductores/repartidores.
- ✅ Estado.
- ✅ Ubicación.
- ✅ Viajes activos.
- ✅ Delivery activo.
- ✅ SOS.
- ✅ Filtros.
- ✅ Asignación manual.

## Falta ampliar

- ❌ Modificar origen/destino desde Admin.
- ❌ Reasignar viaje ya tomado desde Admin.
- ❌ Cambiar método de pago durante servicio.
- ❌ Notas administrativas por viaje.
- ❌ Historial GPS detallado.

---

# Seguridad

## Ya existe

- ✅ SOS.
- ✅ Eventos de emergencia.
- ✅ Contactos de confianza.
- ✅ Estado de cuenta.
- ✅ Documentos.
- ✅ Verificación de identidad.
- ✅ Face match configurable.
- ✅ Liveness configurable.
- ✅ Auditoría de cambios.
- ✅ Zonas de seguridad.
- ✅ QA sandbox.

## Falta

- ❌ Proveedor facial real.
- ❌ OCR real de documento.
- ❌ Revisión automática de vencimientos.
- ❌ Risk scoring.
- ❌ Detección automática de cuentas duplicadas.

---

# Comunicación

## Ya existe

- ✅ Push Android.
- ✅ Notificaciones internas.
- ✅ Chat durante servicio.
- ✅ Chat de soporte.
- ✅ Avisos masivos desde Admin.
- ✅ Deep links parciales.
- ✅ Teléfono y WhatsApp de soporte configurables.

## Falta

- ❌ WhatsApp Business API.
- ❌ Solicitar viaje por WhatsApp.
- ❌ Bot de WhatsApp.
- ❌ Plantillas por evento.
- ❌ Email transaccional completo.
- ❌ SMS fallback.

---

# Pagos y wallet

## Ya existe

- ✅ Efectivo.
- ✅ Wallet.
- ✅ Movimientos wallet.
- ✅ Comisión separada.
- ✅ Deuda de comisión en efectivo.
- ✅ Ganancia neta.
- ✅ Recargas.
- ✅ Aprobación/rechazo de recargas.
- ✅ Resumen Admin.
- ✅ Mercado Pago / PagoRUT / Santander / MACH / Tenpo configurables.

## Falta

- ❌ Gateway real tarjeta.
- ❌ Integraciones reales de todos los proveedores configurados.
- ❌ Retiros.
- ❌ Conciliación automática.
- ❌ Facturación/boleta.
- ❌ Reembolsos automáticos completos.

---

# Reportes

## Ya existe

- ✅ Resumen operativo.
- ✅ Viajes.
- ✅ Viajes completados.
- ✅ Viajes cancelados.
- ✅ Delivery.
- ✅ Delivery completado.
- ✅ Volumen cobrado.
- ✅ Usuarios nuevos.
- ✅ Emergencias.
- ✅ Filtro temporal.

## Falta

- ❌ Exportar Excel.
- ❌ Exportar CSV.
- ❌ PDF.
- ❌ Reportes de conductores.
- ❌ Comisiones detalladas.
- ❌ Wallet detallado.
- ❌ Reportes de negocio.
- ❌ Gráficas avanzadas.

---

# Build Center

## Ya existe

- ✅ APK.
- ✅ AAB.
- ✅ Firma.
- ✅ GitHub Actions.
- ✅ Historial.
- ✅ Estado.
- ✅ Progreso.
- ✅ Fecha.
- ✅ Versión.
- ✅ Build number.
- ✅ Changelog.
- ✅ Commit.
- ✅ Descargar APK.
- ✅ Descargar AAB.
- ✅ Publicar actualización.
- ✅ Actualización obligatoria.
- ✅ Shorebird Preview.
- ✅ Base Preview independiente.
- ✅ QA automático.

## Falta

- ❌ iOS.
- ❌ TestFlight.
- ❌ Pipeline Play Console completamente automatizado.

---

# White-label / configuración

## Ya existe

- ✅ Moneda.
- ✅ País.
- ✅ Zona horaria.
- ✅ Módulos Taxi/Delivery.
- ✅ Métodos de pago.
- ✅ Dispatch.
- ✅ Radio.
- ✅ Timeout.
- ✅ Servicios.
- ✅ Tarifas.
- ✅ Seguridad.
- ✅ Calificaciones.
- ✅ Mantenimiento.
- ✅ Versión mínima.

## Falta

- ❌ Nombre de marca editable.
- ❌ Logo editable desde Admin.
- ❌ Colores.
- ❌ Icono.
- ❌ Splash.
- ❌ Dominio.
- ❌ Idiomas.
- ❌ Multi-tenant real.
- ❌ White-label completo.

---

# Promociones y crecimiento

Todavía pendiente:

- ❌ Cupones.
- ❌ Código promocional.
- ❌ Referidos.
- ❌ Programa de lealtad.
- ❌ Bonos conductor.
- ❌ Cashback.
- ❌ Publicidad.
- ❌ CTR/campañas.
- ❌ Segmentación de usuarios.

---

# Empresas / B2B

Pendiente:

- ❌ Cuenta empresarial.
- ❌ Empleados.
- ❌ Centros de costo.
- ❌ Límites por empleado.
- ❌ Viajes corporativos.
- ❌ Facturación consolidada.
- ❌ Portal empresa.
- ❌ Reportes corporativos.

---

# Roles y permisos

## Actual

- ✅ Admin.
- ✅ Usuario.
- ✅ Conductor.
- ✅ Auditor QA aislado.

## Falta

- ❌ Superadmin.
- ❌ Operador.
- ❌ Finanzas.
- ❌ Soporte.
- ❌ Seguridad.
- ❌ Despachador.
- ❌ Auditor solo lectura.
- ❌ Permisos granulares por módulo/acción.

---

# Diferencias principales frente a CabGo

## Express ya está fuerte en

- Movilidad/taxi.
- App unificada.
- Fijo + ofertas.
- Tracking.
- Seguridad.
- Wallet.
- Comisiones.
- Calificaciones privadas.
- Zonas y polígonos.
- Tarifas jerárquicas.
- Admin operativo.
- Build Center.
- QA sandbox.
- Auditoría.
- Configuración runtime.

## CabGo sigue más avanzado en

- Delivery marketplace.
- Negocios.
- B2B.
- Promociones.
- Referidos.
- Publicidad.
- WhatsApp Business.
- Facturación/recibos.
- Exportación avanzada.
- White-label.
- Multi-tenant.
- Permisos granulares.
- iOS.
- Automatización comercial.

---

# Prioridad recomendada

## Fase 1 — cerrar movilidad al 100%

1. Progressive dispatch real.
2. Reasignación automática.
3. ETA mejorado.
4. Cobro/penalización de espera.
5. Gateway de pagos real.
6. Retiros conductor.
7. Face/liveness real.
8. Recibo PDF.
9. Exportación CSV/Excel.

## Fase 2 — Delivery completo

1. Negocios.
2. Catálogo.
3. Categorías.
4. Productos.
5. Extras/variaciones.
6. Carrito.
7. Horarios.
8. Preparación.
9. Pickup code.
10. Delivery code.
11. Evidencia fotográfica.
12. Propina.
13. Comisiones por negocio.
14. Reportes de negocio.

## Fase 3 — crecimiento

1. Cupones.
2. Referidos.
3. Lealtad.
4. Bonos.
5. Publicidad.
6. Campañas.
7. Segmentación.

## Fase 4 — Administración avanzada

1. Roles.
2. Permisos granulares.
3. Branding editable.
4. Plantillas.
5. Reportes avanzados.
6. Exportaciones.
7. Facturación.

## Fase 5 — B2B y white-label

1. Empresas.
2. Centros de costo.
3. Viajes corporativos.
4. Facturación consolidada.
5. Multi-tenant.
6. White-label.
7. Dominios.
8. iOS/TestFlight.

---

# Regla para futuras sesiones

Cuando el usuario diga **“como CabGo”**:

1. Revisar primero si la función ya existe total o parcialmente en Express.
2. No duplicar backend, tablas ni UI.
3. Reutilizar la arquitectura Flutter + Supabase existente.
4. Mantener diseño, marca y experiencia propia de Express.
5. Implementar solo la brecha real.
6. Actualizar este documento después de cerrar un módulo importante.

Este archivo debe mantenerse como documento vivo y no como lista histórica estática.
