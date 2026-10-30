# Express 1.6.4+156 — Beneficios

## Entrega verificada

- La web de Express está desplegada como 1.6.4+156 y pasó Web First QA y la publicación de Pages.
- La candidata Android oficial `com.express.usuario1` se compiló como APK+AAB firmadas desde el mismo SHA; ambas se registraron con hashes e identidad verificados.
- Google Play aceptó el AAB en la pista Internal y `build_jobs` quedó `ready`.
- QA en dispositivo queda pendiente para que el propietario instale la candidata desde Pruebas internas. Producción de Play sigue en el build 152; esta publicación no promueve la app a Producción.
- La migración de Beneficios está aplicada en Producción, mantiene separado Preview y no activa campañas automáticamente.

## Cambios incluidos

- Configuración de cupones, reglas de activación, fidelidad, referidos y retos.
- Comisión MLM de conductor como porcentaje configurable de cada pago de plan aprobado; acredita a la billetera interna no retirable.
- Liquidación de beneficios en viajes: comisión de Express en cero y descuentos/premios promocionales acreditados a la billetera no retirable del conductor.
- Campañas sin activar automáticamente.

## Validación

- Suite Flutter de Express: 469 pruebas aprobadas.
- Web First QA y despliegue web: aprobados.
- Build Android oficial, verificación de paquete/firma y carga de AAB en Google Play Internal: aprobados.
- QA manual en dispositivo: pendiente; no se afirma que se haya realizado.
