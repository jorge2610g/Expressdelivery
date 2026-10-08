# Bolivia KYC – estudio de costo y decisión de proveedor (8 octubre 2026)

**No retirar Didit ni borrar datos históricos antes de elegir proveedor y verificar el resultado con cédulas bolivianas reales autorizadas en QA.** Deshabilitar un servicio y borrar datos personales son operaciones independientes.

## Cambio confirmado de precio Didit
- Hasta **31 oct 2026**, Didit ofrece **500 verificaciones KYC completas gratis/mes** por organización para su paquete básico (ID, prueba de vida pasiva, comparación facial, IP), sin contar otros módulos que pueden cobrar desde el primer uso.
- Desde **1 nov 2026**, pasa a **USD 10 de crédito mensual** para cualquier verificación; KYC completo **USD 0.33**, aproximadamente **30 verificaciones** con ese crédito si no se usa en otros productos.
- Fuente oficial: https://didit.me/blog/new-pricing-november-2026/ (2 oct 2026), https://help.didit.me/billing-credits/how-pricing-and-credits-work.
- La cuota interna actual Bolivia 30 / mes no es el precio efectivo hasta fin de octubre. **No ampliar cuota sin verificar uso real y workflow de la cuenta Didit de Express.** Del 1 de noviembre en adelante, crédito compartido a nivel cuenta.

## Alternativas de bajo costo (USD por proceso)
| Solución | Precio público | Qué incluye / limita |
|---|---:|---|
| Didit KYC completo | USD 0.33 fuera de gratuidad | Autenticidad del documento, pasiva liveness, rostro-ID, señales de fraude. |
| Google Vision OCR | USD 1.50 / 1000 imágenes después de 1000 unidades mensuales gratis por función | Extrae texto del frente/reverso del carnet; **no prueba autenticidad**. |
| AWS Rekognition CompareFaces | ~USD 0.001 / llamada en tarifa inicial estándar | Compara selfie y retrato del carnet; **no verifica vida**. |
| AWS Rekognition Face Liveness | ~USD 0.015 / comprobación (us-east-1 estándar) | Prueba de vida; requiere integración de captura / SDK. |
| AWS+Google y administrador | ~USD 0.019 por conductor fuera de cuota OCR (2 OCR + face match + liveness) | Precio de APIs, NO es KYC completo: falta antifraude documental, revisión humana y operaciones. |
| Face++ Compare | 500 comparaciones gratuitas/mes anunciadas para cuentas overseas en ene 2026 | Comparación facial sola; sin OCR de CI ni liveness automáticamente, limitaciones en free. |
| Exadel CompreFace | licencia Apache 2.0 sin precio por chequeo | Self-hosting a costo fijo + OCR y prueba de vida separados, seguridad y mantenimiento propios. |

Fuentes originales:
- https://cloud.google.com/vision/pricing
- https://aws.amazon.com/rekognition/pricing/
- https://aws.amazon.com/blogs/machine-learning/id-selfie-improving-digital-identity-verification-using-aws/
- https://www.faceplusplus.com/blog/face-overseas-free-policy-adjustment-notice/
- https://github.com/exadel-inc/CompreFace

## Decisión recomendada
1. **Octubre:** mantener Didit sin borrar mientras se verifica su cuota real de 500 gratuitas y módulos activos; utilizar manual Express en los casos que requieren corrección.
2. **Desde noviembre:** piloto privado de **OCR Vision + AWS CompareFaces + AWS Face Liveness** (solo como asistencia de revisión manual). Nunca aprobar cuentas automáticamente con una mera similitud facial. Revisar calidad y compatibilidad de carnet boliviano anverso/reverso; medir falsas coincidencias, latencia y fraude.
3. **Siempre:** administrador decide fotos individuales, historial reversible, capturas privadas, consentimiento informado, retención limitada, límites anti-reintentos; proveedor intercambiable con feature flag.
4. Presupuesto de pruebas limitado, capturas de QA bajo consentimiento; no activar endpoints facturables sin aprobación de costos y protección de credenciales.

**No hay conector AWS/Google Cloud configurado ni aprobación de envío de documentos a dichos proveedores.** Ninguna tarifa de APIs incluye el costo de revisión humana ni de infraestructura.
