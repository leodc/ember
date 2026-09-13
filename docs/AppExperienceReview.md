# Revisión integral de Ember — 2026-09-13

**Cierre del milestone — 2026-09-13:** el usuario lo da por validado y completado.
Los resultados y límites técnicos descritos abajo documentan lo observado durante
la revisión; no representan bloqueos de aceptación pendientes. Siguiente paso:
milestone 5, puente de audio Telnyx–Realtime.

Se revisó el recorrido desde inicio hasta cierre, la identidad visual, los textos
en español e inglés, las preguntas al usuario, la conversación y el comportamiento
con recepción. Los cambios están implementados en las vistas SwiftUI reales.
Ember continúa siendo un POC: el ensayo Realtime y la llamada Telnyx siguen
separados. Esta revisión no implementa el puente de audio del milestone 5.

## Experiencia del usuario

| Área | Cambio y propósito |
| --- | --- |
| Inicio | Una acción principal para preparar la cita; se retiran tarjetas sin funcionalidad. Se explican las dos formas de probar Ember. |
| Preparación | Objetivo e idioma bastan para ensayar. El número es opcional para ensayo y obligatorio, validado también en el controlador, para llamar. Disponibilidad en texto libre o selector de fecha/franja; permite expresar varios días. |
| Revisión | Datos, nombre de reserva, permisos y disponibilidad juntos. «Ensayar con Ember» explica que el usuario interpreta a recepción. La tarjeta de llamada real explica que habla el usuario. |
| Perfil | Nombre de presentación y nombre de reserva primero; otros datos opcionales desplegables. Guardar y Cancelar explícitos; los cambios en edición no se pierden por un deslizamiento accidental. |
| Ensayo | Instrucciones claras antes de activar el micrófono. Historial con roles visibles, entrada de instrucciones y estado final que recuerda que la app no ha reservado una cita. |
| `ask_user` | Opciones verticales, ninguna preseleccionada, selección y envío separados. Texto libre directo cuando no hay opciones. El envío tiene indicador y texto propios; cambiar a instrucciones conserva el borrador. |
| Llamada | Icono más compacto, número legible, estado con símbolo y color, cierre accesible y mensaje de error separado del estado breve. |
| Identidad | Fondo marfil, texto carbón, acentos naranja y tarjetas suaves. Acción principal oscura con texto blanco; estados positivos y errores usan colores más oscuros. Nuevo icono común a la app y a sus pantallas. |

Se mantienen el texto multilínea, las áreas de interacción amplias y el contenido
desplazable con Dynamic Type. El pie de acciones es opaco: se eliminó el texto
que se entreveía por debajo. En tamaños de accesibilidad la pantalla necesita
más desplazamiento; no se reduce la letra elegida por el usuario.

## Evidencia visual

Capturas nativas de iPhone SE (3.ª generación) e iPhone 17 Pro con iOS 26.5,
con perfil ficticio Alex Rivera y transporte local. No se hicieron llamadas reales.

| Pantalla / estado | Evidencia |
| --- | --- |
| Inicio, español, SE | [Inicio](experience-review/home.png) |
| Preparación, español, SE | [Formulario](experience-review/form.png) |
| Revisión, español, SE | [Datos](experience-review/review.png) |
| Perfil, español, SE | [Perfil](experience-review/settings.png) |
| Disponibilidad, español | [Calendario y franja](experience-review/availability.png) |
| Llamada conectada, transporte ficticio, SE | [Llamada](experience-review/phone-call.png) |
| Antes del ensayo, español, SE | [Preparación del ensayo](experience-review/rehearsal-ready.png) |
| Revisión, inglés, 17 Pro | [Revisión en inglés](experience-review/review-en.png) |
| Inicio, inglés, `accessibility3`, 17 Pro | [Letra grande](experience-review/home-accessibility-en.png) |
| Envío de respuesta retenido, español | [Enviando](experience-review/ask-sending.png) |
| Ensayo terminado y resultado | [Cierre](experience-review/rehearsal-ended.png) |
| Error de llamada | [Error](experience-review/phone-error.png) |
| Error de ensayo y recuperación | [Ensayo interrumpido](experience-review/rehearsal-error.png) |
| Formulario vacío y ayuda para continuar | [Sin datos](experience-review/form-empty.png) |

La [revisión de preguntas y transcripción del 12 de septiembre](VisualReview.md)
conserva evidencia de una opción, diez opciones (incluida la décima seleccionada),
texto libre con teclado, instrucciones con teclado, textos largos y transcripción
continua a 50 deltas/s. Sus resultados táctiles corresponden a esa revisión.

Durante la revisión final el Mac quedó bloqueado y el control de interfaz no pudo
continuar. Las capturas se pudieron obtener mediante las herramientas de desarrollo.
No se atribuyen a esta ronda nuevas pruebas táctiles completas, navegación con
VoiceOver, rotación ni todos los tamaños de letra con teclado. La reproducción con
voz real del bloqueo reportado en el iPhone sigue pendiente; el cambio de seguimiento
de la transcripción y el estrés local son mitigaciones, no una confirmación física.

## Experiencia de quien atiende

El prompt ahora pide una presentación breve y honesta como asistente de IA,
respuestas cortas y una pregunta cada vez. Debe escuchar correcciones sin volver a
empezar, aclarar datos inaudibles, respetar las esperas y no repetir el perfil.
Antes de consultar al usuario explica de forma natural con quién está comprobando
el dato. No promete cuánto tardará ni exige que recepción espere indefinidamente.
Si no aceptan llamadas de IA o piden terminar, debe despedirse sin insistir ni
simular una transferencia. Las instrucciones escritas no se leen en voz alta.

La evaluación detectó dos defectos concretos que se corrigieron:

1. Algunas preguntas de medicamentos ofrecían una respuesta incompleta como
   «Sí, toma este/estos medicamentos:». El prompt exige ahora `suggestedAnswers: []`
   para nombres de medicamentos, síntomas y datos personales abiertos. La última
   repetición de los dos casos afectados devolvió preguntas libres completas.
2. El modelo podía llamar a `end_session` sin haber resumido el resultado; la app
   pedía entonces únicamente una despedida. La respuesta final ahora recibe el
   motivo validado y resume servicio/horario solo si recepción los confirmó.
   Si queda pendiente, lo dice. Un motivo de cierre no prueba que exista reserva.

La fase final usa las mismas instrucciones en la app y en el evaluador. Mantiene
el cierre después de terminar el audio y permite que una instrucción del usuario
interrumpa la despedida antes de desconectar.

### Evaluación real del modelo

Se ejecutó `gpt-realtime-2.1` mediante WebSocket con el prompt y las herramientas
de producción, datos ficticios e **entrada/salida de texto**. Las respuestas se
revisaron manualmente; no son una puntuación automática ni una garantía estadística.

| Escenario | Observación |
| --- | --- |
| Saludo | Presentación como IA, identidad del usuario y objetivo. |
| Medicamentos desconocidos | Consulta al usuario, sin inventar hechos. La última repetición ofrece texto libre. |
| Otro día y hora | Consulta la alternativa concreta, incluida la llegada anticipada, sin aceptarla por su cuenta. |
| Recepción no puede esperar | Reconoce que sigue esperando al usuario y pregunta si dejan pendiente o retoman más tarde. |
| Rechazo de IA y petición de terminar | `recipient_requested_end` y despedida breve, sin insistir. |
| Corrección de horario | Adopta la hora corregida y la llegada anticipada; continúa con el dato que falta. |
| Fecha inaudible | Pide aclaración, no inventa la fecha. |
| Reserva confirmada | Pide confirmación definitiva y, una vez recibida, cierra con recapitulación y agradecimiento. |

Evidencia completa: [ocho escenarios iniciales](experience-review/agent-eval.json),
[cinco escenarios tras ajustar el cierre](experience-review/agent-eval-closing.json),
[repetición final de medicamentos y espera](experience-review/agent-eval-refined.json).
Los informes guardan las respuestas y el consumo reportado por el proveedor.
La evaluación inicial y la intermedia conservan los defectos encontrados; deben
leerse junto con la repetición final, no como resultados del prompt definitivo.

Esto verifica contenido y decisiones observadas. Quedan por medir con audio real
la naturalidad en japonés, latencia, solapamiento de voces, ruido, espera musical,
interrupción inmediata y percepción de quien atiende. Algunas respuestas del modelo
siguen siendo más largas que el objetivo de una o dos frases. No se declara
validación de extremo a extremo por teléfono.

La revisión se apoyó en las recomendaciones de concisión y turnos de la
[guía oficial de prompting de voz](https://developers.openai.com/api/docs/guides/voice-prompting)
y en los eventos/modalidades de la
[guía de conversaciones Realtime](https://developers.openai.com/api/docs/guides/realtime-conversations).

### Repetir la evaluación

Solo se ejecuta de forma explícita; usa la configuración local sin imprimir claves
y consume API. No forma parte de las pruebas unitarias.

```sh
swiftc AIPhoneAgent/Models/CallDefinition.swift AIPhoneAgent/Models/RealtimeConfiguration.swift Tests/Tools/RealtimeExperienceEval.swift -o /tmp/ember-experience-eval
/tmp/ember-experience-eval --run-live
# Opcional: repetir casos concretos; escribe agent-eval-refined.json.
/tmp/ember-experience-eval --run-live --cases=unknown-medication,cannot-wait
```

## Icono

Generado con la herramienta integrada de ImageGen. Marca de conversación naranja
con una llama en negativo sobre carbón; sin letras ni máscara exterior redondeada.
Integrado en el catálogo de recursos y en la configuración Debug/Release.

- [Icono final de aplicación, 1024 × 1024, opaco](../AIPhoneAgent/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png).
- [Recurso usado dentro de la app](../AIPhoneAgent/Resources/Assets.xcassets/EmberIcon.imageset/EmberIcon.png).

Prompt utilizado:

> Use case: logo-brand. Asset type: final iOS app icon for Ember, a warm, calm voice assistant that helps people arrange appointments. Create one square 1024x1024 opaque app icon. Full-bleed deep warm charcoal background (#29262B), with a single bold sculptural orange speech-bubble emblem incorporating a small flame as negative space. Warm tangerine to ember orange, subtle soft dimensional highlights, precise silhouette, generous margin (emblem centered within 65% of canvas), friendly and premium. The speech bubble and flame should read as one simple unmistakable mark at tiny sizes. No text, no letters, no border, no device mockup, no rounded outer corners (iOS supplies the mask), no extra symbols, no transparency. Quiet, beautifully balanced, production app asset.

## Galería local

Argumentos Debug: `--visual-review ESCENARIO`, opcional `--review-language en`
y `--review-accessibility`. Los valores predeterminados son español y letra normal.

Escenarios nuevos: `app-home`, `app-form`, `app-form-empty`, `app-review`,
`app-settings`, `app-availability`, `app-call`, `app-call-ended`, `app-call-error`,
`voice-ready`, `voice-ended`, `voice-error`. También se mantienen `ask-one`,
`ask-ten`, `ask-text`, `ask-long`, `ask-sending`, `ask-streaming`, `voice`,
`voice-long` y `voice-states`. La galería no modifica el perfil personal guardado.
Quitar los argumentos devuelve la app a su funcionamiento habitual.

## Verificación técnica

- 54 pruebas de regresión aprobadas, 0 fallos y 0 omitidas. Incluyen impedir marcar
  un número inválido aunque se pueda ensayar, y aplicar el motivo validado a la despedida.
- Compilación final Debug para simulador: correcta. Release para iPhone sin firma:
  correcta. El último ajuste posterior a las regresiones solo simplifica la
  presentación del error del ensayo y se recompiló en ambas configuraciones.
- `git diff --check`: sin errores. No hay advertencias de compilación del código
  Swift propio; Xcode omite la extracción de App Intents porque no se utiliza.
- Icono comprobado: 1024 × 1024 y sin canal alfa.
- No se ha instalado esta versión en el iPhone físico ni se ha efectuado una llamada real.
