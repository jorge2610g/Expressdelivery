# Express — Changelog activo de desarrollo

Este archivo resume las versiones recientes que cambiaron la arquitectura o el comportamiento de la aplicación.

> Para arquitectura, backend, roadmap y handoff completo, leer primero:
> `docs/START_HERE_EXPRESS.md`

---

## v1.5.9 · build 46

Objetivo: separar el flujo de destino en tres etapas como la referencia de video: buscar destino, verificar ruta y recién después mostrar precios/opciones.

Cambios:

- al elegir destino desaparecen saludo, “¿A dónde vas?”, buscador, lugares guardados y recientes;
- nueva etapa “Confirma tu ruta” con origen y destino editables;
- origen y destino pueden corregirse antes de continuar;
- la etapa de verificación muestra distancia y tiempo, pero no precio;
- la cotización de tarifa se solicita después de confirmar la ruta;
- después de confirmar se muestra “Elige tu viaje” con categorías, precio, horario y pago;
- botón “Revisar ruta” permite volver a la verificación sin perder los puntos;
- editar origen o destino invalida automáticamente la confirmación anterior;
- tarjetas de origen/destino adaptadas al modo oscuro.

---

## v1.5.8 · build 45

Objetivo: replicar la interacción de selección de ubicación observada en la referencia de video.

Cambios:

- el pin deja de arrastrarse de forma independiente;
- el pin queda fijo en el centro mientras el usuario mueve el mapa;
- al comenzar el movimiento, el pin se eleva visualmente;
- al detenerse el mapa, el pin cae con rebote sobre el punto central;
- la coordenada seleccionada se toma del centro real del mapa;
- reverse geocoding se ejecuta sólo después de que el mapa se detiene;
- las respuestas de geocodificación antiguas ya no pueden sobrescribir la selección más reciente;
- el botón de confirmación queda deshabilitado mientras el mapa se mueve o se resuelve la dirección;
- tocar otro punto del mapa centra ese punto debajo del pin;
- el selector de ubicación usa OpenStreetMap con filtro local en modo oscuro, sin API key.

---

## v1.5.7 · build 44

Objetivo: corregir el mapa oscuro después del cambio de CARTO que empezó a exigir API key en sus basemaps.

Cambios:

- retirado CARTO del Home para evitar el mosaico “API KEY REQUIRED”;
- OpenStreetMap queda como proveedor base sin clave;
- en modo oscuro se aplica un filtro local a los mosaicos para conservar apariencia oscura;
- eliminada la atribución CARTO porque ya no se usa ese proveedor;
- corregida la clave de limpieza de caché web;
- actualización de versión web.

---

## v1.5.6 · build 43

Objetivo: separar la navegación fija Viaje/Delivery del panel deslizable y permitir que el contenido del Home suba completo antes de desplazarse internamente.

Cambios:

- barra inferior Viaje Express / Delivery movida fuera del panel y dejada fija;
- el panel principal conserva su posición base y ahora puede expandirse hasta el 92 % de la vista;
- el gesto hacia arriba prioriza expandir la pestaña antes de desplazar su contenido;
- Viajes recientes vuelve a mostrar hasta 4 accesos compactos;
- tarjetas de viajes recientes adaptadas a modo claro y oscuro;
- actualización de versión y clave de caché web.

---

## v1.5.5 · build 42

Objetivo: corregir el Home del pasajero según comparación directa con la referencia visual.

Cambios:

- calificación pendiente retirada del Home;
- Centro Express movido al menú;
- botones flotantes globales retirados;
- Viajes recientes simplificado;
- buscador principal más visible;
- panel base ajustado;
- modo oscuro real para el Home;
- mapa oscuro cuando el dispositivo usa tema oscuro;
- botones superiores adaptados;
- badge de versión reducido.

---

## v1.5.4 · build 41

Objetivo: compactar el inicio del pasajero y estabilizar su panel principal.

Cambios:

- panel base fijo al 56%;
- el panel ya no puede bajar por debajo de su posición principal;
- expansión sólo hacia arriba;
- menos padding vertical;
- saludo y título compactados;
- buscador más compacto;
- Casa y Trabajo reducidos;
- Viajes recientes compacto;
- selector Viaje Express / Delivery en una sola fila;
- toda la información principal visible sin arrastrar.

---

## v1.5.3 · build 40

Objetivo: simplificar el inicio de Express Rider usando la referencia visual enviada.

Cambios:

- mapa más limpio con solo menú y botón de centrar ubicación;
- se elimina el selector visible Pasajero/Conductor del encabezado;
- panel inicial centrado en “¿A dónde vas?”;
- buscador principal grande y único;
- origen oculto del inicio porque usa la ubicación actual por defecto;
- Casa y Trabajo como accesos directos;
- enlace “Ver todos” para lugares guardados;
- bloque de viajes recientes;
- selector simple Viaje Express / Delivery al pie del panel;
- categorías, pago, tarifa y horario aparecen únicamente después de elegir destino;
- navegación inferior global oculta mientras se está en Inicio para evitar duplicidad;
- Historial, Pagos y Perfil siguen disponibles desde el menú y recuperan navegación al abrirse.

---

## v1.5.2 · build 39

Objetivo: estabilizar el selector de ubicación y el panel principal del pasajero.

Cambios:

- el pin se renderiza siempre como marcador real del mapa;
- el área táctil de arrastre queda separada del marcador visual;
- destino inicia en la ubicación actual/origen aunque coincida;
- la validación de origen=destino ocurre únicamente al confirmar;
- tocar, buscar o arrastrar ya no dispara la advertencia antes de guardar;
- panel Viaje/Delivery con altura inicial fija;
- panel con posiciones de snap más estables y menos extremas.

---

## v1.5.1 · build 38

Objetivo: corregir el arrastre manual del pin de ubicación.

Cambios:

- pin separado del sistema de gestos del mapa;
- área táctil ampliada;
- arrastre real del pin;
- mapa bloqueado sólo mientras se arrastra el pin;
- actualización de dirección al soltar;
- feedback visual durante el movimiento;
- toque sobre mapa conservado como alternativa.

---

## v1.5.0 · build 37

Objetivo: mejorar funciones y experiencia de Express Rider y Express Conductor.

Cambios:

- cálculo de ruta con distancia y duración;
- tarifa sugerida desde las reglas configuradas;
- distancia/duración guardadas en solicitudes;
- Conductor ve distancia al origen, distancia total, ETA aproximada y pago;
- tarjetas de solicitud rediseñadas;
- calificación pendiente visible después de completar servicios;
- calificación con estrellas y comentario;
- historial Rider sin duplicados;
- filtros de historial y viajes programados;
- ganancias del conductor por período;
- total, promedio y desglose Viajes/Delivery;
- notificaciones con fecha/hora;
- marcar todas las notificaciones como leídas.

---

## v1.4.3 · build 36

Objetivo: pulido visual y responsive del Express Admin.

Cambios:

- tema visual exclusivo del Admin;
- inputs, botones, chips, menús y diálogos normalizados;
- transición a drawer en pantallas medianas para evitar headers apretados;
- app bar móvil más limpia;
- Conductores y Usuarios compactados;
- acciones de conductor agrupadas;
- Despacho responsive;
- Zonas y Tarifas con filas administrativas más limpias;
- headers con botones adaptables a móvil;
- App Builder responsive en 1, 2 o 3 columnas;
- aviso de actualización reducido y flotante;
- badge de versión menos invasivo.

---

## v1.4.2 · build 35

Objetivo: alinear visualmente Express Admin con la referencia mostrada en video.

Cambios:

- sidebar claro con grupos de navegación;
- tarjeta de empresa actual;
- selección activa en azul suave;
- header administrativo compacto;
- botón Nuevo viaje;
- accesos de actualización, bug, notificaciones, idioma y cuenta;
- Dashboard reorganizado con KPIs principales;
- Acciones rápidas;
- Estado del sistema;
- componentes visuales reutilizables;
- listas más compactas;
- búsqueda local en listas;
- filtros por estado;
- badges de estado;
- Configuración con pestañas horizontales;
- App Builder en tarjetas Android / iOS / Código Fuente;
- historial de builds visualmente renovado;
- responsive mantenido.

---

## v1.4.1 · build 34

Objetivo: corregir el acceso al Panel Administrador.

Cambios:

- ruta Admin estable mediante `?admin=1`;
- se mantiene compatibilidad con `#admin`;
- también se acepta `?mode=admin`;
- las cuentas con permiso administrativo muestran un botón `Panel administrador` dentro de la app;
- el acceso al Admin ya no depende únicamente de que el navegador conserve el fragmento de URL.

---

## v1.4.0 · build 33

Objetivo: convertir Express Admin en un centro de operaciones real inspirado funcionalmente en la arquitectura revisada de CabGo.

Cambios:

- nuevo Dashboard administrativo;
- KPIs de conductores online, búsquedas, viajes, delivery, cancelaciones, SOS y cobros;
- mapa operativo;
- actividad reciente;
- vistas reales de Viajes y Delivery;
- administración de Conductores y Usuarios;
- resolución de SOS;
- Zonas de operación;
- jerarquía de tarifas Global → Servicio → Zona+Servicio;
- tarifa base, km, minuto, mínimo, surge y comisión;
- Pagos/Billetera y resumen financiero;
- Reportes por período;
- configuración global de módulos y métodos de pago;
- dispatch broadcast, progressive y manual;
- despacho manual con validación de conductor disponible;
- auditoría de acciones sensibles;
- estructura segura del Build Center sin exponer tokens de GitHub.

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
