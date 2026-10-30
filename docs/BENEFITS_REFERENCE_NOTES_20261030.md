# Beneficios Express — referencias del propietario

Estado: decisiones de producto y alcance de implementación; las campañas de
viajes siguen inactivas hasta conectar sus reglas de liquidación.
Fecha: 2026-10-30.

El propietario solicita un esquema para cupones de primeros viajes, fidelidad y
referidos, y aporta capturas de otro panel como referencia. Después incorpora
retos para conductores. Los valores visibles en las capturas son ejemplos de esa
referencia: no son importes, presupuestos ni condiciones aprobadas para Express.
Las capturas no autorizan copiar importes. El propietario sí definió el flujo
financiero de cupones, premios internos, pagos de plan y deudas de cancelación.

## Cupones y promociones

- Descuento porcentual o monto fijo, máximo de descuento y mínimo de viaje.
- Transporte/Delivery y selección de servicios.
- Audiencia, segmento objetivo, responsable de financiar el descuento.
- Límites totales y por usuario; vigencia y estado.
- Requisito solicitado: primer viaje o primeros viajes. Un uso por usuario no
  sustituye la comprobación de que realmente sea un usuario nuevo en viajes.
- Referencia de pantalla: pestañas Cupones y Reglas de Activación, indicadores
  de cupones activos, canjes y descuento total. El contenido de Reglas de
  Activación se detalla a continuación, tras las nuevas capturas.

## Reglas de activación — recompensas automáticas

- Pantalla de reglas con indicadores de reglas totales, activas y activaciones
  (recompensas otorgadas); filtro y listado por nombre, disparador, recompensa,
  audiencia, activaciones, estado y acciones.
- Formulario: nombre, descripción, tipo de disparador y valor opcional,
  tipo y valor de recompensa, destino, audiencia objetivo, máximo de activaciones
  opcional e interruptor de regla activa.
- Opciones efectivamente visibles: disparador Primer viaje, recompensa Monto
  fijo, destino Billetera y audiencia Clientes. Los selectores cerrados no
  permiten confirmar qué otras opciones existen.
- El campo monetario muestra el símbolo $ sin identificar la moneda. Para
  Express se recomienda mostrar moneda explícita por campaña/zona (por ejemplo,
  Bs/BOB en Trinidad), sin interpretar $ automáticamente como USD.
- No queda demostrado si Primer viaje dispara al solicitar, iniciar, completar
  o pagar. Tampoco si el máximo es global o por usuario. Definirlo expresamente.
- Diferenciar descuento utilizable EN el primer viaje de recompensa otorgada
  DESPUÉS del primer viaje. Acreditar billetera tras completarlo no reduce
  automáticamente lo que el pasajero pagó por ese viaje.
- Los cupones de pasajeros descuentan el importe del viaje. Salvo descuento del
  100%, el pasajero paga el resto en efectivo o QR directamente al conductor.
  Express acredita al conductor el monto descontado en su billetera interna.
  Si el viaje queda 100% gratis, Express acredita el total del viaje al
  conductor. No hay dinero promocional retirable para pasajeros.
- Recomendación de diseño: reglas comunes de eventos, condiciones y recompensas
  para coordinar bienvenida, fidelidad, referidos y retos. Tipos adicionales de
  evento o premio son propuestas, no funciones demostradas por estas capturas.
- Pendiente: momento de activación, límites globales y por persona, presupuesto,
  vencimiento, acumulación de promociones, reversión de premios por reembolsos,
  registro auditable y protección ante eventos duplicados/reintentos.

## Fidelidad de pasajeros

- Cada N viajes pagados, premio para un viaje posterior.
- Tope monetario del viaje premiado.
- Premio adicional al conductor que atiende el viaje: cantidad de viajes sin
  comisión, límite de créditos por conductor/día, inicio el mismo día o siguiente
  y vencimiento según la campaña.
- Máximo de premios por cliente y total; fechas; campaña activa/inactiva.
- Indicadores: participantes, premios otorgados/cobrados y créditos a conductores.
- Filtros visibles: todas, activas, programadas, terminadas e inactivas.
- Decisión financiera: un viaje gratis debe cubrir al conductor con saldo
  interno de Express; las recompensas del pasajero son cupones o viajes gratis,
  no saldo retirable o dinero acreditado a su billetera.

## Referidos

- Recompensa independiente para quien invita y para el invitado.
- Tipo, valor y destino de recompensa; en la referencia aparece Monedero.
- Viajes mínimos para activar el premio, máximo de referidos por usuario,
  moneda y habilitación del programa.
- Historial con estados, filtro por tipo de referidor, pendientes, activados y
  tasa de conversión.
- Los referidos para usuarios pasajeros pueden entregar cupones u otros
  beneficios utilizables dentro de la app; el propietario prefiere concentrar el
  programa MLM en referidos de conductores.
- No se implementan niveles indirectos. El saldo de premios para conductores
  se mantiene en la billetera interna y no se puede retirar; puede usarse para
  pagar sus planes.

## Referidos de conductores sobre pagos de plan — decisión del propietario

- Un conductor invita directamente a otro conductor mediante su código.
- El invitador recibe en su billetera interna un porcentaje configurable del
  monto de cada pago de plan que el referido realice correctamente.
- Aplica a pagos de planes en Bolivia. No son cobros recurrentes: cada compra es
  un pago puntual; si el conductor quiere otro período, realiza otro pago.
- La relación de referido permanece de por vida. Cada pago confirmado genera un
  crédito; si el referido no vuelve a pagar, no se genera otro.
- El crédito se calcula sobre el importe del pago de plan confirmado y se abona
  a la billetera interna, no retirable, del conductor invitador.
- Ejemplo de referencia, no valor inicial aprobado: con un pago de plan de Bs 1
  y porcentaje de 1%, el invitador recibe Bs 0,01 por pago confirmado.
- El porcentaje será configurable; no fijar automáticamente el 1% del ejemplo.
- La acreditación debe ser idempotente por pago de plan y conservar país,
  moneda, zona y canal Prueba/Producción.
- No se paga comisión por viajes ni por niveles indirectos. Express no cobra
  comisión por los viajes; sus ingresos son pagos de planes de conductores y
  pagos reales por deudas de cancelación.
- Un pago de viaje por efectivo o QR va directamente al conductor. Express no
  recauda la tarifa ni cobra comisión por el viaje. Los pagos QR de deudas de
  cancelación sí se pagan a Express.
- Una deuda de cancelación pendiente bloquea al pasajero para pedir viajes y al
  conductor para aceptar trabajo hasta que salde el monto por efectivo o QR.
  Admin también puede gestionar deudas manualmente.

## Retos para conductores — capturas añadidas

- Nombre y descripción del reto.
- Meta de número de viajes y período; la captura del formulario muestra Semanal,
  y la lista también muestra un reto de período Personalizado. No se conocen las
  demás opciones del selector.
- Fecha de inicio y fecha de fin opcional.
- Tipo de recompensa y monto; la opción visible es Bono en efectivo. No se
  conocen los demás tipos disponibles.
- Alcance de toda la app o una zona concreta. Según el texto de la referencia,
  un reto zonal solo es visible y admite inscripción de conductores de esa zona.
- Reto exclusivo: el conductor no puede inscribirse a otros retos.
- Compatibilidad opcional: selección explícita de otros retos combinables.
- Tabla: nombre, meta, período, recompensa, inscritos del período, completados,
  estado y acciones.
- Indicadores: retos totales/activos, inscripciones del período/en progreso,
  completados y tasa de éxito. Filtro de estado visible en la lista.
- La referencia muestra un ejemplo de 10 viajes y Bs 100. No se aprueba ese
  incentivo para Express por haber aparecido en una captura.

## Definiciones pendientes antes de activar campañas de viaje

- Qué viajes cuentan: completados y pagados/verificados; exclusión o tratamiento
  de cancelaciones, reembolsos, servicios promocionales y actividad irregular.
- Inscripción manual o automática; contar solo viajes posteriores a la inscripción
  o desde el inicio del período; repetición de metas y límite de premios.
- Fechas, zona horaria y reinicio de períodos.
- Qué ocurre si un conductor cambia de zona y reglas exactas de exclusividad y
  compatibilidad, incluida la acumulación de beneficios de otros programas.
- Montos y elegibilidad por campaña, presupuesto, vigencia, límites y acumulación.
- Destino y reglas de acreditación de premios y cupones asociados a viajes.
- Congelar las condiciones de premios e inscripciones existentes al editar una
  campaña; historial y acreditación única ante reintentos.
- Mantener autorización de Admin por rol/zona/módulo y aislamiento por cuenta de
  Prueba/Producción; la interfaz no sustituye controles del servidor.

Estas reglas pendientes y las recomendaciones previas requieren definición con
el propietario. Las capturas muestran interfaz, no prueban funcionamiento del
backend de la referencia ni que esos módulos ya existan en Express.
