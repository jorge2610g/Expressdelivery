> **HISTÓRICO — NO VIGENTE (2026-10-11).** Este documento describía la app paralela Preview o releases anteriores. La referencia vigente es `docs/FLUJO_UNICO_2026-10-11.md` (una app `com.express.usuario1`, un build, una trazabilidad).

# Express 1.5.95 · build 140

Candidato estable Android.

- Código de aplicación aprobado para compilar: `72a67c2287bc66180e3df63ee820545adb875095`
- Preview y Producción deben compilar exactamente ese SHA.
- Paquete Preview: `com.express.usuario.preview`
- Paquete Producción: `com.express.usuario1`
- Firebase Android se resuelve mediante el build worker protegido por GitHub OIDC.
- El APK/AAB se bloquea si Firebase, firma o `ic_stat_express` no están disponibles.
