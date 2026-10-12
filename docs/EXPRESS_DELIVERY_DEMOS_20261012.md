# Restaurantes Express · Demos aislados por entorno (12 oct 2026)

## Qué queda preparado
- **Admin Express → Restaurantes → Restaurantes demo:** crear uno o paquete completo de 3 tipos (Express Burger DEMO, La Pizza Express DEMO, Sabores Caseros DEMO), reintentable sin duplicar catálogo ni borrar ediciones.
- Plantillas: seis productos por restaurante, tres secciones de menú, extras configurables para el primer producto, horarios de muestra, CLP o BOB según ciudad; beneficios Express Plus deshabilitados de inicio.
- **Iquique y Trinidad**: se crearon de inicio 3 demos Preview + 3 demos Producción por ciudad (12 restaurantes; 72 productos). Cada creador del entorno correspondiente quedó como propietario inicial para probar el portal, sin crear contraseñas.
- Producción: los demos se mantienen con `production_visible=false` y `preview_visible=false`; no figuran en la app de clientes, no se pueden hacer pedidos ni cotizar vía checkout, y tampoco permite cambiar esa visibilidad desde las RPC de administración. **Delivery Producción permanece desactivado**.
- Preview: sólo se muestran en Preview y admiten pruebas de catálogo. Los usuarios de restaurante deben pertenecer al mismo entorno.
- Portal web: `/restaurantes/` con login, pantalla de pedidos, catálogo y liquidaciones. Publicarlo requiere completar QA y desplegar la web; la creación de los datos en Supabase no implica su publicación.
- Admin: los demos de Producción están listados en una sección de QA interna incluso aunque su visibilidad pública sea falsa. El botón «Asignar usuario» sólo acepta una cuenta ya registrada en el mismo entorno.

## Pruebas
1. Entra a Admin Express con administrador Preview y elige Iquique o Trinidad → **Restaurantes**.
2. Busca «Restaurantes demo» y verifica 3 restaurantes y 6 productos por cada uno.
3. Toca «Crear restaurante demo → Paquete completo» dos veces: no cambia la cantidad ni se pierden cambios.
4. Abre «Ver productos» y edita uno; debe persistir tras recargar.
5. Inicia sesión en Portal Restaurantes con la cuenta administradora del entorno o asigna un usuario de prueba de ese entorno con su correo registrado.
6. Realiza un pedido de **Preview** (nunca usando las cuentas productivas) y recorre aceptación, chat, comprobante, aprobación de pago, recogida y entrega.
7. Con admin Producción verifica que el listado de demos existe en «Restaurantes demo», aunque siguen ocultos en el catálogo público y no admiten checkout.
8. Comprueba que no es posible asignar usuarios de otro entorno, hacer visible un demo de Producción ni cotizarlo.

## Límites que no debemos ocultar
- Los registros iniciales son datos de prueba y **no incluyen pedidos, balances ni transferencias inventadas**.
- El portal permite registro por correo, pero **no crea un usuario Preview automáticamente**: usa una cuenta Preview registrada/aislada o el admin Preview ya asignado. La asignación por correo no crea contraseñas.
- Producción no permite pedidos demo mientras Delivery esté desactivado. Para ensayar todo el circuito con transacciones ficticias de Producción haría falta una ruta de auditoría adicional, con actores y cobros segregados.
- No se ha autorizado activar Delivery general ni utilizar Mercado Pago real para pruebas.
- Restaurantes Demo no cambia Taxi, usuarios reales ni tarifas de Taxi.

## Código
- Base de datos: `supabase/migrations/20261012224000_marketplace_safe_demo_restaurants.sql`,
  `supabase/migrations/20261012225500_marketplace_demo_user_access.sql`.
- Admin: `lib/admin_marketplace_demos.dart` en `jorge2610g/Adminexpress`, integrado en `lib/admin_marketplace.dart`.
