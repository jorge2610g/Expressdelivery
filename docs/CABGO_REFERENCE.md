# CabGo como referencia funcional para Express

> Documento de referencia de producto.
>
> CabGo se usa como inspiración de arquitectura, flujos y módulos. No se debe copiar su marca, identidad visual propietaria ni código fuente.

## Fuentes públicas revisadas

- https://www.cabgo.app/es/resellers
- https://www.cabgo.app/es
- https://www.cabgo.app/es/plataforma
- https://www.cabgo.app/es/plataforma/dashboard
- https://www.cabgo.app/es/plataforma/cabgo-app
- https://www.cabgo.app/es/funcionalidades
- https://www.cabgo.app/es/personalizacion
- https://www.cabgo.app/es/docs/arquitectura/jerarquia-configuraciones

## Idea central a trasladar a Express

Express debe evolucionar hacia una plataforma integral de movilidad y delivery administrada desde un dashboard central, con una app unificada para cliente/pasajero y conductor/repartidor.

La estructura objetivo queda así:

1. Express App
   - Pasajero
   - Cliente de Delivery
   - Conductor
   - Repartidor

2. Express Admin
   - Operación en vivo
   - Configuración
   - Conductores
   - Usuarios
   - Delivery
   - Pagos
   - Seguridad
   - Reportes
   - Builds

3. Backend Express / Supabase
   - Auth
   - Realtime
   - Tarifas
   - Zonas
   - Dispatch
   - Pagos
   - Wallet
   - Notificaciones
   - Seguridad
   - Auditoría

## Funciones de referencia que queremos para Express

### App unificada

- Taxi/Viajes y Delivery en una sola app.
- Pasajero y cliente comparten experiencia.
- Conductor y repartidor comparten experiencia.
- Mapa como pantalla principal.
- Seguimiento GPS en vivo.
- Chat durante servicio.
- Llamada.
- Pagos en efectivo, tarjeta y wallet.
- Calificaciones.
- Historial.
- Notificaciones push.
- Viajes programados.

### Dispatch

- Solicitudes por proximidad.
- Asignación automática.
- Asignación manual desde Admin.
- Modo broadcast.
- Modo progressive dispatch.
- Radio configurable.
- Timeout configurable.
- Filtros por vehículo/servicio/zona.
- Reasignación cuando un conductor rechaza o expira.

### Tarifas

Jerarquía objetivo:

1. Configuración global.
2. Configuración por tipo de servicio.
3. Configuración por zona + servicio.

Parámetros:

- tarifa base;
- precio por km;
- precio por minuto;
- tarifa mínima;
- tarifa fija entre zonas;
- multiplicador por horario;
- multiplicador por día;
- surge pricing;
- comisiones por servicio;
- comisiones por zona;
- propinas;
- service fee.

### Zonas

- Dibujar zonas en mapa.
- Activar/desactivar cobertura.
- Configuración específica por zona.
- Tarifas especiales.
- Métodos de pago permitidos por zona.
- Vehículos/servicios permitidos.
- Radio de operación.

### Conductores

- Registro.
- Documentos.
- Licencia.
- Vehículo.
- Fotos.
- Estado de aprobación.
- Estado online/offline.
- Ubicación en tiempo real.
- Verificación facial futura.
- Alertas de documentos vencidos.
- Historial.
- Calificación.
- Ganancias.
- Wallet.
- Retiros.

### Delivery

Objetivo posterior al flujo básico actual:

- Negocios.
- Catálogo de productos.
- Categorías.
- Extras y variaciones.
- Horarios.
- Tiempo de preparación.
- Pedidos en vivo.
- Repartidor.
- Código de recogida.
- Código de entrega.
- Evidencia fotográfica.
- Propina.
- Estados detallados.
- Asignación automática/manual.
- Reportes por negocio.
- Comisiones por negocio.
- Pickup sin reparto.

### Panel Administrativo Express

Menú objetivo aproximado:

- Dashboard
- Operación en vivo
- Viajes
- Viajes programados
- Delivery
- Conductores
- Usuarios
- Negocios
- Zonas
- Tarifas
- Comisiones
- Pagos
- Billetera
- Promociones
- Referidos
- Notificaciones
- Seguridad / SOS
- Soporte / Tickets
- Reportes
- Configuración
- Apariencia / Branding
- Permisos
- Builds
- Logs / Auditoría

### Dashboard principal

Debe mostrar como mínimo:

- viajes activos;
- solicitudes buscando;
- conductores online;
- conductores ocupados;
- conductores offline;
- viajes completados hoy;
- cancelaciones;
- ingresos;
- comisiones;
- delivery activos;
- emergencias;
- mapa en tiempo real;
- actividad reciente.

### Mapa operativo

Desde Admin:

- conductores/repartidores en vivo;
- estado;
- tipo de vehículo;
- servicio activo;
- ubicación;
- viaje/pedido relacionado;
- opción de asignación manual;
- acceso al detalle del servicio.

### Seguridad

- SOS.
- Contactos de confianza.
- Eventos de emergencia.
- Documentos del conductor.
- Estado de cuenta.
- Motivo obligatorio al suspender/bloquear.
- Auditoría de cambios.
- Verificación facial futura.

### Comunicación

- Push FCM/APNs.
- Deep link hacia servicio.
- Chat en viaje.
- WhatsApp Business futuro.
- Plantillas por evento.

### Reportes

- Operativos.
- Financieros.
- Conductores.
- Usuarios.
- Viajes.
- Delivery.
- Cancelaciones.
- Comisiones.
- Wallet.
- Exportar Excel/CSV.
- Recibo PDF por servicio.

### White-label / configuración

Aunque Express inicialmente es una sola marca, conviene construir configuración centralizada:

- nombre;
- logo;
- colores;
- icono;
- splash;
- dominio;
- moneda;
- zona horaria;
- idiomas;
- módulos activados;
- métodos de pago;
- tipos de vehículo.

Esto deja la arquitectura preparada para crecimiento futuro.

### App Builder

Inspirado en el concepto de pipeline automático:

Admin → Build Center → GitHub Actions → Flutter build → APK/AAB → artifact/release → descarga

Debe incluir:

- versión;
- build number;
- changelog;
- estado;
- progreso;
- fecha;
- commit;
- Descargar APK;
- Descargar AAB;
- historial de builds.

## Comparación rápida con Express actual

### Ya existe o está avanzado

- Flutter + Supabase.
- App unificada.
- Pasajero.
- Conductor.
- Delivery básico.
- Mapa.
- GPS.
- Origen/destino.
- Autocomplete de ubicación.
- Ruta.
- Oferta de precio.
- Viajes programados.
- Chat.
- Llamada.
- Tracking.
- Wallet.
- Historial.
- Cancelación.
- SOS.
- Notificaciones internas.
- Admin básico.
- Aprobación de conductores.
- Versionado web.
- Actualización web.
- GitHub Actions.

### Falta o requiere ampliación

- Dispatch automático completo.
- Realtime en lugar de polling donde corresponda.
- Zonas.
- Motor de tarifas configurable.
- Surge.
- Tarifas entre zonas.
- Comisiones configurables.
- Mapa operativo del Admin.
- Asignación manual.
- Documentos/verificación de conductor.
- Push real.
- Rating completo.
- Recibos PDF.
- Reportes/exportación.
- Pasarela de tarjeta real.
- Retiros de conductor.
- Negocios de Delivery.
- Catálogo/carrito.
- Códigos pickup/entrega.
- Evidencias fotográficas.
- WhatsApp.
- Roles/permisos granulares.
- Build Center APK/AAB.
- Auditoría completa.

## Orden recomendado de implementación

### Fase 1 — núcleo de movilidad

1. Terminar QA pasajero ↔ conductor.
2. Realtime.
3. Dispatch.
4. Tarifas.
5. Zonas.
6. Admin operación en vivo.
7. Push.
8. Rating.
9. Pagos.

### Fase 2 — panel completo

1. Dashboard.
2. Conductores.
3. Usuarios.
4. Viajes.
5. Mapa.
6. Configuración.
7. Comisiones.
8. Wallet.
9. Reportes.
10. Seguridad.

### Fase 3 — Delivery completo

1. Negocios.
2. Catálogo.
3. Carrito.
4. Preparación.
5. Pickup codes.
6. Evidencias.
7. Repartidor.
8. Reportes de negocio.

### Fase 4 — Build Center y distribución

1. Android.
2. APK.
3. AAB.
4. Firma.
5. GitHub Actions.
6. Descarga desde Admin.
7. iOS/TestFlight.

## Regla para futuras sesiones

Cuando el usuario diga “como CabGo”, interpretar que desea replicar el concepto o función dentro de Express, adaptándolo al stack actual Flutter + Supabase y al diseño propio de Express.

Antes de implementar un módulo nuevo, comprobar si ya existe parcialmente en Express para evitar duplicar backend o UI.
