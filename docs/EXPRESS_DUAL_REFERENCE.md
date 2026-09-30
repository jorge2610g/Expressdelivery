# EXPRESS DUAL — REFERENCIA VISUAL Y FUNCIONAL

Referencia elegida por producto: mockup oscuro **Express Dual** con una sola app para pasajeros, conductores y entregas.

## Principios

- una cuenta;
- dos modos principales: **Cliente** y **Conductor**;
- cambio de rol sin instalar otra app;
- mapa como pantalla principal;
- interfaz oscura premium con azul eléctrico;
- Viajes + Moto + Delivery;
- precio fijo o tarifa propuesta por el pasajero;
- contraofertas del conductor;
- seguridad, pagos, wallet, historial y soporte en la misma app.

## Flujo Cliente

1. Splash Express Dual.
2. Onboarding.
3. Login / registro unificado.
4. Selección o cambio de modo Cliente / Conductor.
5. Inicio con mapa.
6. Servicios rápidos: Express, Moto, Delivery, Programar.
7. Destino y confirmación de ruta.
8. Categoría del vehículo.
9. **Precio fijo**.
10. **Haz tu oferta**.
11. Búsqueda con radar y vehículos cercanos.
12. Ofertas / contraofertas de conductores.
13. Conductor asignado.
14. Seguimiento en vivo.
15. Chat / llamada / compartir / SOS.
16. Cancelación.
17. Llegada y comprobante.
18. Calificación.
19. Viaje programado.
20. Delivery.
21. Métodos de pago.
22. Wallet.
23. Historial.
24. Lugares guardados.
25. Notificaciones.
26. Soporte.
27. Perfil.

## Flujo Conductor

1. Cambio a Modo Conductor.
2. Estado online / offline.
3. Vehículo activo (Auto / Moto / XL según registro).
4. Solicitudes cercanas.
5. Solicitud de precio fijo: **Aceptar tarifa**.
6. Solicitud negociable: **Contraofertar**.
7. Navegación al pasajero.
8. Llegué / espera.
9. Iniciar viaje.
10. Viaje en progreso.
11. Completar servicio.
12. Delivery.
13. Ganancias.
14. Historial de servicios.
15. Calificación.
16. Seguridad / SOS.
17. Soporte.
18. Perfil y documentos.

## Implementado en la primera fase visual

- nuevo sistema visual oscuro `express_dual_theme.dart`;
- Express Dual aplicado a Web y Android;
- login/registro oscuro y unificado;
- selector Cliente / Conductor visible sobre el mapa;
- mapa oscuro en pasajero y conductor;
- paneles inferiores oscuros;
- servicios rápidos Express / Moto / Delivery / Programar;
- Precio fijo / Haz tu oferta;
- `ride_requests.pricing_mode`;
- conductor diferencia tarifa fija de solicitud negociable;
- tarifa fija: conductor acepta el monto;
- oferta: conductor puede contraofertar;
- marca Express Dual en componentes principales;
- se conservan las funciones reales existentes de GPS, Supabase, búsqueda, ofertas, chat, tracking, pagos, historial y seguridad.

## Regla de implementación

La referencia visual no es una demo separada. Los cambios deben aplicarse a la experiencia real conectada a Supabase.

No generar APK/AAB automáticamente. La validación se hace primero en Web. Android solo se compila cuando el administrador lo solicita desde Adminexpress.
