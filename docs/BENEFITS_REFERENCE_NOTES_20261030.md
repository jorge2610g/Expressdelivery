# Beneficios Express — referencias del propietario

Estado: notas para diseño y definición funcional, no implementación ni activación.
Fecha: 2026-10-30.

El propietario solicita un esquema para cupones de primeros viajes, fidelidad y
referidos, y aporta capturas de otro panel como referencia. Después incorpora
retos para conductores. Los valores visibles en las capturas son ejemplos de esa
referencia: no son importes, presupuestos ni condiciones aprobadas para Express.
No se ha autorizado en estas notas la creación de campañas o movimientos reales.

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
- Pendiente de decisión: financiación y liquidación del viaje premiado. La
  compensación monetaria y los viajes sin comisión se discutieron como opciones;
  no hay un modelo financiero aprobado. No asumir que un incentivo futuro
  equivale a compensar íntegramente el viaje gratis.

## Referidos

- Recompensa independiente para quien invita y para el invitado.
- Tipo, valor y destino de recompensa; en la referencia aparece Monedero.
- Viajes mínimos para activar el premio, máximo de referidos por usuario,
  moneda y habilitación del programa.
- Historial con estados, filtro por tipo de referidor, pendientes, activados y
  tasa de conversión.
- La referencia tiene una pestaña Grupos MLM, cuyo contenido se documenta abajo.
  No se ha aprobado su implementación ni un sistema de varios niveles.
- Separar saldo promocional y saldo retirable fue una recomendación, no una
  decisión del propietario todavía.

## Grupos MLM — nueva captura aportada

- Título visible: comisión recurrente por referidos.
- Un conductor invita directamente a otro mediante su código. Además del bono
  único del programa, quien invita queda como líder y recibe un porcentaje de la
  comisión de empresa por cada viaje completado por el conductor referido.
- La recompensa sale de la parte de la empresa, no de un descuento adicional
  al conductor referido.
- Configuración visible: programa activo, porcentaje del líder calculado sobre
  la comisión de empresa, duración en meses o beneficio de por vida.
- El texto de ayuda indica un máximo del 50% para el porcentaje del líder.
  La captura no demuestra que ese límite se valide en el servidor.
- Ejemplo de la ayuda: comisión de empresa del 20%, participación del líder del
  25% de esa comisión: el líder recibe el equivalente al 5% del viaje. El campo
  visible muestra 1; esos valores y el interruptor de por vida son datos de la
  referencia, no decisiones aprobadas para Express.
- Aunque se denomina MLM, esta pantalla solo describe un vínculo directo entre
  líder y conductor referido. No demuestra pagos por niveles adicionales ni
  recompensas por referidos indirectos.
- Pendiente de definición: base realmente cobrada de la comisión, viajes exentos
  de comisión, reembolsos, conciliación de efectivo, coexistencia con retos y
  descuentos, límites, expiración, cambio de líder y acreditación única.
- Recomendación por evaluar: un solo nivel directo y vigencia limitada para el
  lanzamiento, con historial auditable de la comisión financiada por Express.

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

## Definiciones pendientes antes de implementar

- Qué viajes cuentan: completados y pagados/verificados; exclusión o tratamiento
  de cancelaciones, reembolsos, servicios promocionales y actividad irregular.
- Inscripción manual o automática; contar solo viajes posteriores a la inscripción
  o desde el inicio del período; repetición de metas y límite de premios.
- Fechas, zona horaria y reinicio de períodos.
- Qué ocurre si un conductor cambia de zona y reglas exactas de exclusividad y
  compatibilidad, incluida la acumulación de beneficios de otros programas.
- Financiación, presupuesto, destino y momento de acreditación de los premios.
- Congelar las condiciones de premios e inscripciones existentes al editar una
  campaña; historial y acreditación única ante reintentos.
- Mantener autorización de Admin por rol/zona/módulo y aislamiento por cuenta de
  Prueba/Producción; la interfaz no sustituye controles del servidor.

Estas reglas pendientes y las recomendaciones previas requieren definición con
el propietario. Las capturas muestran interfaz, no prueban funcionamiento del
backend de la referencia ni que esos módulos ya existan en Express.
