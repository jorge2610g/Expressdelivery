# Ventana flotante de ofertas para conductor

> Estado: **PENDIENTE DE IMPLEMENTAR**
> Objetivo de versión: **Preview 1.6.0+155**
> Fecha de decisión: 2026-10-06
> Repos relacionados: `jorge2610g/Expressdelivery` y `jorge2610g/Adminexpress`

## 1. Objetivo de producto

Cuando el conductor esté **conectado/disponible** y Express esté en segundo plano, una nueva solicitud real de viaje puede mostrarse como una **ventana flotante de oferta sobre otras aplicaciones**, similar a la experiencia de apps de movilidad.

La experiencia deseada NO es una notificación visual tradicional como interfaz principal.

Flujo esperado:

```text
Conductor online
  -> Express en segundo plano
  -> llega oferta real y vigente
  -> aparece tarjeta flotante Express
  -> Aceptar: abrir Express y entrar al flujo del viaje
  -> Rechazar: cerrar tarjeta flotante
  -> Expirar: cerrar tarjeta flotante
  -> Oferta cancelada/asignada a otro: cerrar tarjeta flotante
```

## 2. Consentimiento obligatorio del conductor

La función debe ser opcional y visible en la experiencia del conductor.

Nombre de UI recomendado:

**Ventana flotante de ofertas**

Estado inicial recomendado:
- desactivado hasta que el conductor decida activarlo.

Al activarlo por primera vez:
1. explicar claramente que permite mostrar nuevas solicitudes de viaje sobre otras aplicaciones mientras el conductor está conectado;
2. llevar al usuario a la pantalla Android para conceder **Mostrar sobre otras aplicaciones**;
3. verificar el permiso al regresar;
4. no considerar la función activa si Android no concedió el permiso.

El administrador NO puede conceder ni saltarse el permiso del sistema.

El permiso es por dispositivo y puede ser revocado por el usuario desde Android en cualquier momento.

## 3. Permiso Android

Implementación Android prevista:
- `android.permission.SYSTEM_ALERT_WINDOW`;
- comprobación con la API Android equivalente a `Settings.canDrawOverlays`;
- solicitud mediante la pantalla oficial `ACTION_MANAGE_OVERLAY_PERMISSION` para el package de Express.

No intentar habilitar el permiso automáticamente.

No disfrazar ofertas de viaje como llamadas o alarmas para obtener `USE_FULL_SCREEN_INTENT`.

## 4. Control doble

La feature solo puede funcionar si se cumplen TODAS estas condiciones:

1. AdminExpress permite globalmente la función para el entorno actual.
2. El conductor activó **Ventana flotante de ofertas** en su dispositivo.
3. Android concedió **Mostrar sobre otras aplicaciones**.
4. El conductor está online/disponible.
5. Existe una oferta real, vigente y asignable al conductor.
6. Express está en segundo plano.

Si cualquiera falla, NO mostrar overlay.

El backend/configuración de Admin puede desactivar la feature globalmente, pero jamás puede conceder el permiso Android.

## 5. Switch AdminExpress

Requisito de Admin:

**Permitir ventanas flotantes de ofertas**

Debe existir por entorno:
- Prueba/Preview;
- Producción.

Prueba no debe escribir Producción.

Clave sugerida de configuración compartida:
- `driver_floating_offer_enabled`

Si el switch Admin está OFF:
- la app no debe mostrar overlays;
- el ajuste local del conductor debe aparecer deshabilitado u oculto de forma clara;
- no borrar el permiso Android concedido: simplemente no usarlo.

## 6. Diseño de la tarjeta flotante

La tarjeta debe identificarse claramente como **Express**.

Contenido mínimo:
- tipo de servicio;
- precio/oferta vigente;
- origen;
- destino cuando esté permitido por el flujo;
- distancia/tiempo relevante si ya existe en la oferta;
- contador real restante;
- botón **Aceptar**;
- botón **Rechazar**.

No mostrar información distinta a la que el conductor tendría dentro de la oferta normal de Express.

El contador debe provenir del vencimiento real de la solicitud, no reiniciarse al aparecer el overlay.

## 7. Cierre automático

La ventana flotante debe desaparecer inmediatamente cuando:
- el conductor rechaza;
- el contador llega a cero;
- la solicitud deja de estar vigente;
- otro conductor toma la solicitud;
- el pasajero cancela;
- el conductor queda offline;
- Admin deshabilita la función;
- la app vuelve al foreground y la oferta pasa a la UI normal.

No dejar overlays huérfanos.

## 8. Aceptar

Al aceptar desde la ventana:
1. ejecutar la misma lógica autorizada de aceptación que usa Express;
2. confirmar en backend que la oferta sigue disponible;
3. si se acepta correctamente, cerrar el overlay;
4. traer Express al frente;
5. abrir directamente el flujo del viaje activo.

No crear una ruta alternativa que evite validaciones del backend.

## 9. Transporte en segundo plano

El mecanismo que avise a la app de una nueva oferta puede usar infraestructura de mensajería/datos en segundo plano, pero la interfaz solicitada es la tarjeta flotante, no una push tradicional visible.

La implementación debe respetar las restricciones de ejecución en segundo plano de Android y disponer de fallback seguro cuando el sistema no permita levantar el overlay.

No prometer overlay si el usuario:
- hizo **Forzar detención** de Express;
- revocó permisos;
- el sistema impide ejecución en background.

## 10. Seguridad y políticas

Usar el overlay únicamente para solicitudes reales de movilidad dirigidas a un conductor conectado.

No usarlo para:
- publicidad;
- promociones;
- mensajes genéricos;
- engañar al usuario imitando UI del sistema;
- cubrir controles sensibles de otras apps.

La tarjeta debe decir claramente Express y poder desaparecer por rechazo/expiración.

## 11. QA obligatorio

Validar al menos:

1. Admin ON + usuario ON + permiso ON + app foreground -> usar UI normal, no duplicar overlay.
2. Admin ON + usuario ON + permiso ON + app background -> overlay visible.
3. Rechazar -> overlay desaparece y no abre Express.
4. Expirar -> overlay desaparece solo.
5. Aceptar -> backend acepta, overlay desaparece y Express abre viaje.
6. Admin OFF -> nunca overlay.
7. Usuario OFF -> nunca overlay.
8. Permiso revocado -> nunca overlay y UI informa estado.
9. Conductor offline -> nunca overlay.
10. Oferta cancelada/asignada -> overlay desaparece.
11. Preview y Producción respetan su configuración separada.
12. No aparecen dos ofertas superpuestas ni overlay + popup interno duplicado.

## 12. Estado de implementación

**NO IMPLEMENTADO todavía.**

Este documento registra la decisión funcional para que otra IA no confunda requisito con código terminado.

Antes de declarar listo:
- implementar app;
- implementar flag Admin/backend;
- QA Android real;
- revisar Play Store;
- actualizar `docs/CHANGELOG_ACTIVE.md`;
- actualizar handoff maestro;
- registrar versión/build/SHA exactos.
