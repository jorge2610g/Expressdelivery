# Contrato obligatorio Express: un panel, una APK

**Decisión del propietario: 2026-10-12.** Este documento prevalece sobre instrucciones antiguas de separar builds o sitios Preview.

## Arquitectura única

- Administrador único: [Adminexpress](https://admin.expressviajes.online/), repositorio `jorge2610g/Adminexpress`.
- App Flutter Android única: `jorge2610g/Expressdelivery`, paquete oficial `com.express.usuario1`, entrada `lib/mobile_main.dart`.
- Un backend compartido; Preview/Prueba y Producción son **contextos de datos, no aplicaciones**.
- El servidor asigna el entorno mediante la identidad autenticada y sus permisos; nunca se selecciona por URL, APK, dispositivo, prefijo de package, bandera compilada o botón.
- La web de pasajero y el portal de restaurantes son **funciones del producto Express**, no páginas administrativas Preview independientes; no confundirlas con el panel.

## Prohibiciones

1. No crear ni publicar una web Admin Preview, espejo QA ni un segundo enlace de Adminexpress.
2. No generar APK `Express Preview`, `com.express.usuario.preview`, `com.express.usuario.qa` ni otro package temporal como alternativa al APK oficial.
3. No reintroducir GitHub Actions, Shorebird o pipelines que distribuyan esas variantes.
4. No borrar ni debilitar la separación de cuentas, zonas, conductores, viajes, pedidos, pagos, liquidaciones, RLS o funciones de autorización.
5. No activar funciones nuevas para usuarios reales sin feature flags y permisos backend revisados.

## Cómo probar

- Publicar el **mismo** bundle web en `admin.expressviajes.online` tras sus validaciones, y entrar con una cuenta de Prueba para ver su información aislada.
- Probar Android con el **APK firmado del candidato real**, usando una cuenta de Prueba y el package `com.express.usuario1`. Si se aprueba, promover ese mismo artefacto, sin recrearlo.
- Usar ramas y PR de código solamente como herramientas de revisión, no como otro servicio expuesto.
- Realizar QA técnico y verificaciones de aislamiento antes del despliegue. El panel de taxi y las cuentas de Producción siguen protegidos.

## Ambigüedad prohibida

Cuando el propietario diga «Preview», «versión prueba» o «pruébalo», NO interpretar la frase como permiso para una segunda APK o una segunda web. Solo una revocación **explícita** de esta norma podría cambiar la arquitectura.
