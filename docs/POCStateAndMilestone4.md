# Estado vigente del POC — milestone 4 completado

Consolidado el **2026-09-12**, actualizado el **2026-09-13** tras la revisión de experiencia.
El usuario da por validado y completado el milestone 4 el 2026-09-13.
El siguiente paso es el milestone 5, puente de audio. La aceptación no amplía
la cobertura técnica observada, conservada en el informe de revisión.
Leer junto con las decisiones vigentes del [README](../README.md). Este documento
resume el estado actual; las notas cronológicas de milestone 3 conservan su valor
histórico, pero sus pendientes antiguos no sustituyen este estado consolidado.

## Estado de los milestones

| Milestone | Estado |
| --- | --- |
| 1 — Shell iOS | Implementado |
| 2 — Telnyx saliente | Validado por el usuario: audio bidireccional y cierre |
| 3 — Realtime independiente | Conversación validada por el usuario, con las ampliaciones descritas aquí |
| 4 — `ask_user` | Validado y completado por el usuario el 2026-09-13 |
| 5 — Puente de audio | Pendiente, viabilidad experimental no demostrada |
| 6 — Flujo completo durante llamada | Pendiente del puente y su validación integral |

Hay **dos pruebas separadas**: «Llamada telefónica · Hablas tú» usa Telnyx con micrófono humano;
«Ensayar con Ember» abre Realtime sin marcar ningún teléfono. El agente aún no
conversa con el receptor de una llamada Telnyx.

El usuario validó voz, selección de idioma, identidad y una conversación que
respeta el objetivo sin terminar por una pregunta pertinente desconocida. Reportó
mejora del audio tras ajustar la detección. El autoscroll se añadió después de su
última validación. La [revisión visual local](VisualReview.md) incorpora opciones
con envío explícito, editores separados y seguimiento agrupado de la transcripción.
La confirmación del bloqueo táctil con voz real en iPhone sigue pendiente. No se da
por ejecutada toda combinación de fallos, Bluetooth, red y cierre por ese reporte.

Estado actual: **54 pruebas aprobadas, 0 fallos**, compilaciones Debug para simulador
y Release para iPhone sin firma correctas. Ver [revisión integral](AppExperienceReview.md). Incluye las 29 regresiones previas. Las pruebas automáticas verifican código
y transporte/servicios falsos; no demuestran por sí solas el comportamiento del modelo.

## Configuración del producto

### Tres conceptos de idioma independientes

| Dato | Dónde se cambia | Uso y persistencia |
| --- | --- | --- |
| Idioma de la app | Configuración | Español/inglés, persistente; interfaz, errores propios y preguntas de `ask_user` |
| Idioma del agente | Formulario y pantalla de prueba de voz | Español/japonés/inglés u otro idioma escrito; se mantiene en la definición de llamada en memoria |
| Idiomas del usuario | Configuración → Tu identidad | Hecho del perfil, persistente; no cambia ninguno de los dos selectores anteriores |

El idioma del agente se elige antes de iniciar la sesión. Durante una sesión el
selector queda desactivado; para cambiarlo se finaliza y se inicia otra. No se ha
implementado persistencia de las definiciones de llamada entre reinicios.

### Definición de llamada

- Nombre/contacto: **destinatario**, no identidad del usuario.
- Número: validación y normalización japonesa a E.164 para marcar con Telnyx.
- Objetivo de la cita.
- Idioma del agente.
- Disponibilidad: calendario y horas, almacenada como texto en la definición.
- Instrucciones adicionales, restricciones y permisos.
- Copia del perfil del usuario tomada al iniciar la prueba Realtime.

Una disponibilidad vacía no significa permiso para cualquier horario, salvo
instrucción explícita del usuario. No hay integración con calendarios externos.

### Identidad del usuario

Editable en **Configuración → Tu identidad**, guardada con **Listo**.

| Campo | Valor inicial solicitado |
| --- | --- |
| Nombre | Leonel David |
| Apellidos | Castañeda Mendoza |
| Nombre preferido | Leo |
| Sexo | Hombre |
| Edad | 36 años |
| Idiomas | Inglés y español |
| Ocupación | Programador |
| Nacionalidad | Mexicano |
| Dirección | Dirección postal facilitada por el usuario, conservada en `UserIdentity.initial` |

La fuente exacta de los valores iniciales está en
[UserIdentity](../AIPhoneAgent/Models/CallDefinition.swift). No duplicar la dirección
completa en cada nota de trabajo.

El perfil se guarda localmente en `UserDefaults` bajo `userIdentity.v1`. Los
valores iniciales se aplican cuando no hay perfil guardado. Los perfiles anteriores
sin `sex` incorporan «Hombre» sin perder ediciones. Un campo borrado queda vacío;
no se repuebla con el valor inicial. La edad se actualiza manualmente, no se deduce
una fecha de nacimiento. Los cambios se aplican a las sesiones nuevas.

El contexto del agente distingue usuario y destinatario. Utiliza «Leo» para una
presentación informal y nombre + apellidos cuando la reserva requiere nombre
completo. Los valores se serializan como datos JSON; solo deben comunicarse cuando
sean pertinentes al objetivo y lo permitan las instrucciones. No se inventan
síntomas, medicamentos, documentos, seguros ni permisos a partir de la identidad.
El perfil se envía a OpenAI al iniciar la prueba y no se incluye en los logs.

## Comportamiento conversacional que debe conservarse

### Objetivo y datos desconocidos

El agente conversa sobre el objetivo y sus detalles necesarios. Puede saludar,
agradecer y despedirse. Redirige preguntas completamente ajenas sin contestarlas,
y no acepta que la recepción cambie su función a asistente general.

Las preguntas de recepción sobre qué diente duele, síntomas o medicamentos son
**pertinentes**. Si el dato está disponible y autorizado, responde. Si falta,
lo reconoce con naturalidad, sin frases sobre sus políticas o «lo que puede gestionar».

Con `ask_user`, pide un momento en el idioma del agente y pregunta al usuario en
el idioma de la app. Espera una respuesta real desde el modal antes de usarla.
Si el usuario no sabe, negocia con recepción dejar el dato o la solicitud pendiente,
sin inventarlo ni cerrar unilateralmente. No añade la respuesta al perfil.

### Confirmación de cita

1. Comprobar servicio, fecha/hora inequívocas, ubicación cuando corresponda,
   disponibilidad y restricciones; incluir llegada anticipada/duración si se conocen.
2. Aceptar verbalmente el horario compatible, sin pedir aprobación redundante.
   Si la clínica ofrece una alternativa fuera de disponibilidad, aclarar fecha/hora
   y consultar con `ask_user`. Una aceptación explícita autoriza esa alternativa
   durante la sesión; un rechazo lleva a buscar otras opciones. Una consulta anterior
   sobre medicamentos no impide abrir otra para este nuevo permiso.
3. Preguntar por instrucciones o requisitos para el usuario y esperar la respuesta;
   no repetir lo que ya haya sido explicado completamente.
4. Comprobar compatibilidad. No prometer documentos, preparación, costes o servicios
   que requieran información o autorización no disponible.
5. Si todo encaja, pedir formalizar la reserva con el nombre del usuario y repetir
   los detalles. Esperar el reconocimiento de la recepción.
6. Resumir la cita y sus instrucciones, y proceder al cierre cuando no quede nada
   relevante pendiente.

Horario aceptado, reserva provisional y cita confirmada son estados distintos.
El silencio o la aceptación del propio agente no prueban que exista una reserva.
Esto es diálogo de ensayo: no hay escritura en un sistema externo de reservas ni
modelo estructurado/persistente del resultado de la cita.

### Cierre automático y manual

Ya existe una herramienta real, `end_session`, con un único argumento obligatorio
`reason`. Sus valores admitidos son:

| Motivo | Condición |
| --- | --- |
| `objective_completed` | Cita confirmada, instrucciones resueltas, sin preguntas pertinentes pendientes |
| `recipient_requested_end` | La recepción pide terminar o se despide explícitamente |
| `user_requested_end` | El usuario pide terminar mediante una instrucción escrita en la app |
| `pending_closure_agreed` | Ambas partes acuerdan terminar dejando la solicitud pendiente |

La falta de un dato, una pausa o una pregunta ajena no bastan para cerrar.
El usuario puede enviar [instrucciones durante la sesión](LiveUserInstructions.md),
incluso para interrumpir una despedida antes de que se libere la conexión.
Argumentos inválidos reciben un resultado de rechazo y la conversación continúa.
La app valida el motivo declarado; su correspondencia con la conversación sigue
siendo una decisión del modelo, no una comprobación semántica determinista.

Secuencia vigente (2026-09-13): `end_session` → resultado de herramienta → respuesta
final con resultado confirmado o pendiente, agradecimiento y despedida → generación
completada + audio del servidor
vaciado para ese `response_id` → margen de 750 ms → evento `endedByAgent` → liberar
Realtime. Durante la despedida se desactivan micrófono y VAD. No se toma el final
del texto ni el vaciado de una respuesta anterior como señal para cortar.

La respuesta final utiliza el motivo validado y solo hechos confirmados por recepción;
si el resultado ya se explicó, evita repetirlo. Ver [revisión de experiencia](AppExperienceReview.md).

Hay timeout de despedida y cierre manual, y se liberan recursos al salir/pasar a
segundo plano. El cierre no demuestra que la reserva esté confirmada. En el
milestone 5 el coordinador podrá usar `endedByAgent` para colgar Telnyx; no hacerlo
ahora ni acoplar las dos pruebas antes de construir el puente.

## Parámetros técnicos actuales

| Parámetro | Valor |
| --- | --- |
| Transporte OpenAI | WebRTC nativo; audio directo iPhone–OpenAI |
| Creación | SDP + sesión multipart a `/v1/realtime/calls` |
| Canal de eventos | `oai-events` |
| Modelo por defecto | `gpt-realtime-2.1`; configurable con `OPENAI_REALTIME_MODEL` |
| Voz | `marin` |
| Modalidad de respuesta | Audio, con transcripción del agente |
| Detección de turnos | `server_vad`, `create_response=true`, `interrupt_response=true` |
| Umbral VAD | `0.7` |
| Audio previo | `300 ms` |
| Silencio para finalizar turno | `650 ms` |
| Reducción de ruido | `far_field` |
| Audio iOS | `playAndRecord`, `voiceChat`, altavoz por defecto y Bluetooth HFP |
| Timeout de conexión | `40 s`, después del permiso de micrófono |
| Timeout de despedida | `30 s` |
| Margen tras vaciado de audio | `750 ms`; requiere comprobación auditiva según ruta/red |
| Diagnóstico WebRTC | Contadores acumulados cada `5 s`, sin contenido personal |
| Transcripción | Agente e interlocutor, original, en memoria, hasta 100 entradas y autoscroll |

La transcripción puede incluir palabras interrumpidas; no es un registro exacto
de lo escuchado. La entrada usa `gpt-4o-mini-transcribe`, con idioma detectado
automáticamente y texto asíncrono. No hay traducción integral.
La clave API está en `Config.local.xcconfig`, ignorado por Git y embebido en esta
instalación personal. No hay helper, backend, historial persistente ni cambios de
infraestructura de producción.

## Milestone 4 implementado: `ask_user` independiente de Telnyx

Contrato implementado y milestone aceptado por el usuario el 2026-09-13:

1. Distinguir un dato conocido del perfil/contexto de uno desconocido o que requiere
   autorización. No volver a preguntar un dato que ya se conoce y se puede usar.
2. Ante un dato pertinente desconocido o una decisión fuera de lo autorizado, el
   agente pide un momento en su idioma y solicita `ask_user`.
3. Mostrar `question`, `suggestedAnswers` y controles en el **idioma de la app**.
   `originalQuestion` puede conservar el texto original como contexto secundario.
4. Mantener la llamada de herramienta pendiente hasta que el usuario responda;
   no devolver una respuesta vacía ni continuar como si hubiera contestado.
5. Enviar la respuesta como resultado de esa llamada de herramienta y reanudar la
   conversación en el **idioma del agente**, conservando el significado.
6. Mientras espera, evitar confirmaciones inventadas y cierres por falta de datos.
   El cierre manual y una petición explícita de terminar deben seguir funcionando.
   Un resultado tardío no debe reabrir una sesión terminada.

El prompt utiliza ahora `ask_user` y la herramienta se registra junto a
`end_session`, conservando su contrato de cierre. La respuesta
pertenece a la solicitud de esa sesión: no diseñar persistencia clínica ni ampliar
el perfil automáticamente como parte de este milestone.

### Criterios de aceptación y regresión

- App español + agente japonés: pregunta/opciones en español, continuación japonesa.
- App inglés + agente japonés: pregunta/opciones en inglés, continuación japonesa.
- Agente español: mismo flujo completamente hablado en español.
- Pregunta por nombre completo conocido: respuesta desde identidad, sin modal innecesario.
- Pregunta por diente doloroso desconocido: pide confirmación al usuario y sigue,
  sin tratarla como ajena ni llamar `end_session` por desconocimiento.
- Pregunta por medicamentos: no inventa; espera y transmite fielmente la respuesta.
- Horario compatible + requisitos cumplidos: confirma y se despide sin pedir otra
  autorización innecesaria. Una condición que requiere aprobación activa `ask_user`.
- Astronomía durante la reserva: redirige; no necesita preguntárselo al usuario.
- Cancelar/cerrar mientras espera, respuesta duplicada o tardía: no reinicia ni
  corrompe otra sesión. Preservar el cierre después de la despedida completa.
- Perfil, selección independiente de idiomas, controles visibles y autoscroll se conservan.

Validar manualmente este milestone antes de pasar al puente de audio.

## Archivos para comenzar

| Archivo | Responsabilidad |
| --- | --- |
| [CallDefinition.swift](../AIPhoneAgent/Models/CallDefinition.swift) | Definición, idiomas, identidad y persistencia del perfil |
| [AIPhoneAgentApp.swift](../AIPhoneAgent/App/AIPhoneAgentApp.swift) | `AppSettings` compartido |
| [ContentView.swift](../AIPhoneAgent/App/ContentView.swift) | Configuración e identidad editable |
| [CallDefinitionView.swift](../AIPhoneAgent/Views/CallDefinitionView.swift) | Formulario y selector reutilizable de idioma |
| [RealtimeConfiguration.swift](../AIPhoneAgent/Models/RealtimeConfiguration.swift) | Instrucciones, parámetros y contrato de cierre |
| [OpenAIRealtimeClient.swift](../AIPhoneAgent/Services/OpenAIRealtimeClient.swift) | Transporte, eventos, herramientas y audio final |
| [RealtimeTestController.swift](../AIPhoneAgent/Controllers/RealtimeTestController.swift) | Estado observable y ciclo de vida de sesión |
| [RealtimeTestView.swift](../AIPhoneAgent/Views/RealtimeTestView.swift) | Prueba independiente, transcripción y controles |
| [CallDefinitionTests.swift](../Tests/CallDefinitionTests.swift) | Suite de regresión existente |
