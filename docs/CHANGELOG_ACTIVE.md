# Express — Changelog activo de desarrollo

Este archivo resume las versiones recientes que cambiaron la arquitectura o el comportamiento de la aplicación.

> Para arquitectura, backend, roadmap y handoff completo, leer primero:
> `docs/START_HERE_EXPRESS.md`

---

## v1.3.7 · build 32

Objetivo: evitar rutas inválidas y mejorar interacción del mapa en pantallas pequeñas.

Cambios:

- el destino no puede ser igual al origen;
- se considera inválido un destino a menos de ~25 m del punto de recogida;
- la validación se hace tanto en el selector como antes de crear el servicio;
- si se intenta usar la misma ubicación, se muestra un mensaje claro y no se crea la solicitud;
- al abrir el selector de destino ya no se selecciona automáticamente el mismo punto del origen;
- el mapa se centra alrededor del origen para que el usuario elija otro destino;
- área de agarre del pin ampliada a 108 px;
- todo el entorno visible del pin responde al gesto de arrastre;
- si al arrastrar el pin termina sobre el origen, vuelve al punto anterior;
- panel inferior de Pasajero y Conductor limitado al 60 % de altura;
- nuevos puntos de snap: 23 %, 42 % y 60 %;
- se evita que el panel cubra controles superiores.

---

## Próxima release: v1.3.6 · build 31

Objetivo: mejorar selección de ubicación y eliminar el parpadeo de verificación inicial.

Cambios:

- pin de ubicación arrastrable;
- mientras se arrastra el pin, el mapa no se desplaza;
- tocar el mapa también cambia el punto;
- reverse geocoding al mover el pin;
- autocompletado de direcciones mientras se escribe;
- hasta 6 sugerencias;
- búsquedas sesgadas hacia la zona actual para mejorar resultados locales;
- seleccionar una sugerencia centra el mapa y actualiza la dirección;
- la misma experiencia se usa en origen y destino;
- verificación de servicio silenciosa durante los primeros 450 ms;
- solo se muestra “Verificando tu servicio…” cuando la consulta realmente tarda;
- refresh periódico mantiene el último estado válido y no vuelve a mostrar carga intermedia;
- cuenta de conductor de prueba aprobada directamente en backend para QA del flujo real.

---

## v1.3.5 · build 30

Objetivo: corregir cancelación, acelerar Inicio y hacer útil Mis servicios.

Cambios:

- agregado `ride_requests.updated_at`;
- trigger `touch_ride_request_updated_at`;
- corregido error:
  - `42703 column "updated_at" of relation "ride_requests" does not exist`;
- validación de `cancel_ride_request`;
- nuevo RPC `passenger_home_state()`;
- carga del estado del pasajero en una sola llamada;
- pantalla inicial “Verificando tu servicio…”;
- ocultar estados incorrectos antes de conocer la situación real;
- cierre/filtrado de solicitudes de viaje expiradas;
- ofertas pendientes de solicitudes expiradas pasan a declined;
- los conductores dejan de ver búsquedas vencidas;
- tarjetas de Mis servicios preparadas para abrir detalle;
- detalle de servicio:
  - estado;
  - origen;
  - destino;
  - tarifa;
  - método de pago;
  - categoría;
  - fecha;
  - programación;
  - conductor/repartidor;
  - vehículo;
  - rating.

---

## v1.3.4 · build 29

Objetivo: resolver actualizaciones web que detectaban una versión nueva pero seguían cargando JavaScript viejo.

Cambios:

- botón Actualizar ahora recibe versión de destino;
- cache-busting por URL;
- limpieza de caches;
- eliminación/desregistro de service workers anteriores;
- ejecutable Flutter Web con nombre único por versión;
- workflow deja de depender solo de `main.dart.js`;
- bootstrap versionado;
- `version.json` sigue siendo fuente de versión publicada.

---

## v1.3.3 · build 28

Objetivo: completar funciones alrededor de un servicio activo.

Cambios:

- tarjeta de servicio activo mejorada;
- persona asignada;
- vehículo;
- rating;
- Mapa;
- Chat;
- Llamar;
- cancelación con motivo;
- controles del conductor:
  - Ir al pasajero;
  - Llegué;
  - Iniciar viaje;
  - Completar;
- controles Delivery:
  - Paquete recogido;
  - Salir a entregar;
  - Marcar entregado;
- Viajes programados;
- `scheduled_for`;
- Billetera Express;
- wallet accounts;
- wallet transactions;
- settlement de pagos wallet;
- accesos directos a Lugares guardados;
- acceso directo a Seguridad/SOS.

---

## v1.3.2 · build 27

Objetivo: eliminar el parpadeo de “Buscando conductores…”.

Cambios:

- conservar último estado válido durante refresh;
- no sustituir temporalmente búsqueda real por estado vacío;
- misma idea aplicada a modo Conductor.

Después se mejoró todavía más con `passenger_home_state()` en build 30.

---

## v1.3.1 · build 26

Objetivo: pulir la experiencia map-first.

Cambios:

- botón ☰ convertido en menú real;
- accesos a Historial, Pagos y Perfil;
- menú separado para Conductor;
- cargas de Historial/Pagos con estructura visible;
- ruta vial por OSRM en vez de solo línea recta;
- fallback a línea directa si routing no responde.

---

## v1.3.0 · build 25

Objetivo: cambio mayor de experiencia visual.

Cambios:

- mapa como Inicio;
- panel inferior deslizable;
- experiencia Pasajero;
- experiencia Conductor;
- Viaje / Delivery;
- origen;
- destino;
- categorías:
  - Express;
  - Comfort;
  - XL;
  - Moto;
- tarifa propuesta;
- método de pago;
- lugares guardados;
- búsqueda de conductor;
- ofertas;
- solicitudes para conductor;
- online/offline;
- tracking.

---

## v1.2.9 · build 24

Objetivo: detector automático de actualización.

Cambios:

- `version.json`;
- polling de versión publicada;
- banner:
  - Actualización disponible;
  - número de versión;
  - Actualizar ahora;
- badge de versión actual permanece visible.

Posteriormente el mecanismo de recarga fue endurecido en v1.3.4.

---

## v1.2.8 · build 23

Objetivo: reparar carga de perfil autenticado.

Cambios:

- `ensure_my_profile`;
- autorreparación de perfil;
- pantalla de error útil;
- botón Reintentar;
- correcciones RLS;
- eliminación de recursión entre policies.

Error importante corregido alrededor de esta etapa:

`42P17 infinite recursion detected in policy for relation "delivery_requests"`

---

## Versiones anteriores

Antes de esta etapa existían:

- flujo Delivery original;
- login básico;
- previews separados;
- esquema inicial `profiles/orders`;
- primeras migraciones 001-003.

Esos archivos siguen presentes en parte por compatibilidad/historia, pero **no deben asumirse como representación de la experiencia actual**.

---

## Regla de changelog

Cuando una build cambie:

- arquitectura;
- backend;
- RLS;
- flujo principal;
- versión;
- deployment;
- pagos;
- seguridad;

agregar aquí un resumen breve y actualizar también `START_HERE_EXPRESS.md` si cambia la forma de continuar el proyecto.
