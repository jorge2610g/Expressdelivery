# Formato de entrega obligatorio para la IA programadora

Toda entrega (primera o corrección) debe responder con **esta estructura exacta**,
en el PR (descripción o comentario). Así el propietario y el arquitecto (Claude)
pueden leerla y revisarla sin preguntar nada más.

```
## ENTREGA — <ID de la spec> — ronda <N>
Commit revisado: <SHA completo>   Rama: <rama>   PR: <número>

### 1. Resumen (máx. 5 líneas)

### 2. Archivos cambiados
| Archivo | Qué cambió | Por qué |

### 3. Cumplimiento de criterios de aceptación
| Criterio | Estado (PASS / FAIL / PENDIENTE-MANUAL) | Evidencia concreta |
(Prohibido marcar PASS sin evidencia reproducible. Lo que no se pudo medir
se marca PENDIENTE-MANUAL y se explica cómo medirlo.)

### 4. Resultados de pruebas
- Comando(s) ejecutados y salida resumida (`flutter analyze lib`, `flutter test`).
- Si se usó CI: id del run, rama, y hash (blob) de cada archivo de código/test
  para demostrar que el código validado es el mismo que se entrega.

### 5. Conteos / mediciones antes y después (con fuente)

### 6. Riesgos conocidos y compatibilidad (APK instalados, Preview/Producción)

### 7. Rollback

### 8. Pendientes para el propietario (pruebas manuales, con pasos)

### 9. Preguntas o decisiones para el arquitecto (si no hay: "ninguna")
```

## Reglas de la entrega
1. Entrega solo lo que pide la spec. Cambios extra se proponen en la sección 9, no se hacen.
2. Cada corrección pedida en una revisión se responde punto por punto
   (`B1: corregido en <SHA>, evidencia …`).
3. Nunca declares "listo" sin las secciones 3 y 4 completas.
4. Si cambias código después de que pasó CI, repite CI y actualiza ids y hashes.
5. No toques Producción (migraciones, funciones, datos). No fusiones tu PR.

## Formato de la revisión (lo que devuelve Claude)
Cada revisión se guarda en `docs/reviews/REVIEW-<PR>-<tema>.md` y contiene:
veredicto (APROBADO / CAMBIOS REQUERIDOS), qué verificó Claude por su cuenta,
hallazgos bloqueantes (B1, B2…) con evidencia y escenario real, no bloqueantes
(N1…), instrucciones exactas de corrección sin código, pruebas exigidas y
**un bloque "PROMPT PARA LA IA PROGRAMADORA"** listo para pegar, que no requiere
ningún contexto adicional.
