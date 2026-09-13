# Evaluación de interfaz — 2026-09-12

Continuación con revisión de toda la app, nuevo icono y evaluación del agente:
[Revisión integral — 2026-09-13](AppExperienceReview.md).

Revisión de las vistas SwiftUI reales en simuladores iPhone 17 Pro e iPhone SE
(3.ª generación), iOS 26.5. Los datos son ficticios y el transporte es local:
no se utiliza el micrófono, OpenAI ni Telnyx. Esta revisión valida presentación e
interacciones locales, no la calidad de la conversación ni la interrupción de audio real.

## Decisiones y correcciones

- Una sugerencia se **selecciona** y luego se confirma con **Enviar respuesta**.
  Ninguna opción viene seleccionada. Evita envíos accidentales al explorar la lista.
- Tarjetas verticales con texto completo, selección marcada con icono y borde,
  altura mínima de 56 pt y área táctil amplia. Una y diez opciones usan el mismo patrón.
- La pregunta tiene prioridad; el original se puede desplegar. La respuesta libre
  aparece directamente cuando no hay sugerencias, o mediante **Escribir otra respuesta**.
- La respuesta y la nueva instrucción son modos distintos. Cambiar de modo conserva
  el borrador; solo **Interrumpir y enviar** sustituye la pregunta pendiente.
- Envío fijo en la parte inferior, deshabilitado para texto vacío y mientras se
  procesa el envío. El cierre es una acción roja, separada de la respuesta.
- El editor se desplaza cuando el teclado termina de aparecer; se corrigió una
  superposición entre editor y pie de acciones detectada durante la revisión.
- Agente, interlocutor y usuario tienen etiquetas, iconos y fondos distintos.
  La transcripción conserva su idioma original y admite selección de texto.
- La entrada de instrucciones es compacta y el cierre sigue accesible. Con tamaños
  de accesibilidad la cabecera pasa al contenido desplazable para liberar espacio.
- El modal hereda explícitamente Dynamic Type. La prueba usa `accessibility3`;
  el contenido extenso se lee desplazándolo, sin reducir el tamaño elegido.

## Matriz ejecutada

| Caso | Resultado observado | Evidencia |
| --- | --- | --- |
| Una opción, español, pantalla pequeña | Pregunta, opción y envío visibles; sin preselección. Selección y habilitación de envío comprobadas también en 17 Pro. | [Captura](visual-review/small-one.png) |
| Diez opciones | Lista desplazable; décima opción seleccionable; el envío sigue accesible y no se realiza al seleccionar. | [Décima seleccionada](visual-review/ask-ten-selected.png) |
| Pregunta y opciones largas, inglés | Texto completo mediante desplazamiento, selección de segunda opción comprobada. | [Pregunta con letra grande](visual-review/small-long-accessibility.png), [opción larga](visual-review/small-long-options.png) |
| Sin sugerencias, respuesta libre | Campo multilínea, escritura y envío habilitado; editor visible encima del teclado. | [Teclado](visual-review/ask-text-keyboard.png) |
| Instrucción desde `ask_user` | Cambio de modo, escritura, envío local y regreso a conversación con «Tu instrucción». | [Editor con teclado](visual-review/instruction-keyboard.png) |
| Transcripción extensa y tres participantes | Últimos mensajes legibles, roles distinguibles, campo de instrucciones y cierre visibles. | [Conversación](visual-review/transcript.png) |
| Transcribiendo y error de un turno, letra grande en SE | Estados completos, sin reemplazar la conversación por un error global; cabecera ya no ocupa media pantalla. | [Accesibilidad](visual-review/transcript-accessibility.png) |
| Modal durante transcripción continua | Selección, cambio a instrucciones y escritura respondieron con 50 deltas/s. | Escenario `ask-streaming`, 3.000 deltas durante 60 s |

La última parte de la revisión táctil quedó limitada por el bloqueo de macOS.
Quedan por repetir la navegación manual del historial y **Últimos mensajes**,
el estado de envío retenido, VoiceOver con voz, teclado más tamaño máximo de
accesibilidad y la rotación. No se presenta esta matriz como cobertura exhaustiva
de todos los dispositivos o configuraciones.

## Bloqueo táctil reportado en iPhone

El usuario confirmó que al primer `ask_user` la pantalla dejó de responder a los
toques. Los logs de la ejecución mostraron `onChange(of: Array<Transcript>) action
tried to update multiple times per frame` antes de `ask_user requested`. No se
obtuvo un crash de AIPhoneAgent en la consulta filtrada del dispositivo conectado.
No había una sesión bloqueada activa de la que extraer una pila de ejecución.

Se sustituyó el seguimiento disparado por cada cambio de la lista por **una sola
tarea**, con intervalos de 200 ms. Se pausa mientras la pregunta está abierta y
cuando el usuario desplaza el historial. Una segunda pasada acotada permite
estabilizar la altura de los textos multilínea después de insertarlos; no se
inicia una nueva tarea por token. Se conservan hasta 100 entradas en memoria.

La prueba de estrés local no bloqueó los controles del modal. Esto corrige el
patrón de actualizaciones observado, pero **no demuestra todavía que el bloqueo
del iPhone con WebRTC haya quedado resuelto**. La confirmación requiere repetir
la conversación real en ese dispositivo. Si vuelve a ocurrir, pausar la ejecución
en Xcode mientras está bloqueada y recoger la pila del hilo principal, junto con
el último evento, permitirá distinguir un problema de layout de uno de audio.

## Verificación técnica

- Suite de regresión: **51 pruebas aprobadas, 0 fallos, 0 omitidas**, en iPhone 17
  Pro simulado. El último ajuste posterior solo afecta al layout de accesibilidad
  y al seguimiento visual; se volvió a compilar para simulador y para iPhone.
- Build final Debug para simulador: correcto.
- Build final **Release para iPhone, sin firma**: correcto. La galería solo existe
  bajo `#if DEBUG` y no se activa en Release.
- No se ha instalado esta revisión en el iPhone físico ni se ha realizado una
  conversación real con esta versión.

## Repetir la revisión sin API

En Xcode, esquema AIPhoneAgent, configuración Debug, añade los argumentos de
lanzamiento `--visual-review ask-one`. No se activa en el flujo normal de la app.

Escenarios: `ask-one`, `ask-ten`, `ask-text`, `ask-long`, `ask-sending` (retiene el
resultado tras pulsar enviar), `ask-streaming`, `voice`, `voice-long`, `voice-states`.
Añade `--review-language en` para inglés y `--review-accessibility` para
`accessibility3`. Español y tamaño normal son los valores predeterminados.

Los escenarios usan `RealtimeTestView` y `AskUserView` reales con un servicio
falso. Permiten validar layout sin esperar que el modelo formule una pregunta
específica. Quita los argumentos para volver al POC habitual.
