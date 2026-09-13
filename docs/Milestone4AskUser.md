# Milestone 4 — ask_user independiente

**Cierre del milestone — 2026-09-13:** el usuario lo da por validado y completado.
Los resultados y límites técnicos descritos abajo documentan lo observado durante
la revisión; no representan bloqueos de aceptación pendientes. Siguiente paso:
milestone 5, puente de audio Telnyx–Realtime.

Implementado el 2026-09-12. No conecta Realtime a Telnyx.

## Flujo

El agente recibe `ask_user` y `end_session`. Ante un dato pertinente desconocido
(o una aprobación necesaria), pide un momento en el idioma de la llamada.
`question` y `suggestedAnswers` deben estar en el idioma de la app; `originalQuestion`
es opcional. Los argumentos completos se procesan desde `response.done` con estado
`completed`, evitando mostrar JSON parcial o llamadas de respuestas canceladas.

El controlador muestra `waitingForUser` y `AskUserView`. Las sugerencias se seleccionan sin enviar; **Enviar respuesta** confirma el texto
elegido o escrito en el campo libre; un texto vacío no se admite. No se envía
ningún resultado para la pregunta válida hasta recibir la respuesta. Se crea un
`function_call_output` con el `call_id` original y JSON `{status: answered, answer: …}`,
seguido de `response.create`. Si hay una generación activa, se espera su final antes
de enviar el resultado y solicitar continuación.

El micrófono/VAD sigue activo para que recepción pueda pedir terminar. El prompt
limita al agente a esperar sin asumir respuestas; la espera conversacional y el
idioma del contenido generado requieren validación real del modelo. Los eventos de
voz no quitan el estado de espera del controlador. Un cierre por objetivo cumplido
o acuerdo pendiente se rechaza mientras hay una pregunta; `recipient_requested_end`
cancela la herramienta sin respuesta y usa la despedida existente.

Una segunda pregunta simultánea recibe rechazo sin sustituir a la primera.
Argumentos inválidos reciben un resultado explícito. IDs de llamada/eventos
completados y un UUID por modal evitan duplicados. Cerrar, salir, pasar a segundo
plano o perder la conexión elimina la pregunta y cualquier respuesta en cola.
Las respuestas no se guardan en el perfil ni se incluyen en logs.

Contrato comprobado con la [documentación oficial de conversaciones Realtime](https://developers.openai.com/api/docs/guides/realtime-conversations).

## Verificación

Revisión posterior de interfaz y estado actual: [Evaluación visual](VisualReview.md).
Las cifras siguientes corresponden a la implementación inicial del milestone.

- Compilación final para iPhone (`generic/platform=iOS`, sin firma): **correcta**.
- Suite en iPhone 17 Pro, simulador iOS 26.5: **38 aprobadas, 0 fallos, 0 omitidas**.
- Incluye 9 pruebas nuevas para argumentos inválidos, resultado exacto y `call_id`,
  cola durante voz/generación, duplicados, eventos tardíos, cierres simultáneos,
  cancelación por recepción y fallo de envío. Conserva las 29 regresiones anteriores.
- `git diff --check`: correcto.

Las pruebas usan servicios y transporte falsos; no consumen API ni demuestran por
sí solas la calidad de la conversación o de la traducción. Prueba de voz y revisión
visual en iPhone pendientes.

## Prueba manual en iPhone

1. Configura la app en español, agente en japonés, objetivo de limpieza dental y
   disponibilidad. Abre **Probar voz de OpenAI → Iniciar prueba de voz** y saluda
   como recepción. No uses «Ejecutar llamada», que sigue siendo la prueba Telnyx.
2. Pregunta `現在、何か薬を飲んでいますか？`. Debe pedir un momento en japonés y
   aparecer la pregunta y opciones en español. Espera unos segundos: no debe
   inventar una respuesta ni finalizar. Selecciona **No**, pulsa **Enviar respuesta** y comprueba que comunica
   fielmente la respuesta en japonés y continúa.
3. Pregunta por el diente doloroso; escribe una respuesta libre y envíala. Comprueba
   que el teclado permite alcanzar el envío y que el agente conserva su significado.
4. Repite con app en inglés y agente japonés, y después con agente español.
   El idioma de la app debe controlar los textos del modal; cambiar el idioma del
   agente no debe cambiarlo. La transcripción sigue en el idioma original.
5. Pregunta por el nombre completo conocido: debe usar el perfil sin modal.
   Ofrece un horario compatible y requisitos cumplidos: debe confirmar sin otra
   aprobación. Un tratamiento adicional que requiere permiso sí abre el modal.
   Una pregunta de astronomía se redirige sin consultarla al usuario.
6. Mientras espera, pide verbalmente terminar. Debe desaparecer el modal y escucharse
   la despedida completa. Repite finalizando desde el botón del modal, saliendo de
   la prueba y pasando la app a segundo plano: el micrófono debe detenerse.
7. Reinicia y comprueba una nueva pregunta. Prueba doble pulsación, respuesta vacía
   y pérdida de red: no deben duplicar la respuesta, reutilizar una anterior ni
   reabrir una sesión cerrada. Comprueba el autoscroll y texto grande de accesibilidad.

No avanzar al milestone 5 hasta validar este flujo.

## Ajuste tras la primera prueba del usuario — 2026-09-12

Validado por el usuario: pregunta sobre medicamentos, modal, respuesta introducida
por el usuario y comunicación correcta a la clínica. Fallo reportado: tras esa
consulta, la clínica ofreció otro día/hora fuera de disponibilidad y el agente
respondió que no podía confirmar sin volver a consultar al usuario.

El prompt distinguía de forma ambigua entre restricciones y decisiones autorizables.
Se aclara que la disponibilidad limita la aceptación autónoma: una oferta alternativa
concreta activa otro `ask_user`. Se aclaran primero fecha/hora, se espera la decisión,
y una aceptación permite ese horario manteniendo las demás restricciones. Rechazar
lleva a buscar otra opción. Una respuesta de medicamentos no autoriza cambios de horario.

Repetir el caso en la misma sesión: responder medicamentos → clínica sin horario
compatible → oferta concreta alternativa → segundo modal con fecha/hora → aceptar
→ agente acepta ese horario y comprueba requisitos antes de pedir confirmación.
Repetir rechazando: no debe reservar ese horario. Probar también un horario compatible:
no debe pedir autorización redundante. La corrección conversacional depende del modelo
hasta validarla de nuevo en voz.

## Transcripción del interlocutor — 2026-09-12

La prueba muestra ambas voces con rótulos localizados. La sesión mantiene
`type: realtime` y activa `audio.input.transcription.model = gpt-4o-mini-transcribe`.
No fuerza el idioma del interlocutor al idioma de la app ni al del agente.

Se procesan `conversation.item.input_audio_transcription.delta`, `.completed` y
`.failed`. Los eventos de inicio de voz/commit reservan una fila por `item_id`;
los textos tardíos actualizan esa fila en su lugar. El texto final sustituye los
deltas y no admite deltas tardíos. El seguimiento compara las filas cada 200 ms mediante una sola tarea; se pausa
durante `ask_user` y al desplazar manualmente el historial. **Últimos mensajes** lo
reactiva. Ver [evaluación visual](VisualReview.md).
Un fallo de transcripción se muestra sin cerrar la sesión ni descartar `ask_user`.

El texto permanece en memoria y en su idioma original. El modelo de voz sigue
escuchando el audio directamente: este texto es auxiliar y puede ser inexacto.
Referencia: [configuración de transcripción de entrada de OpenAI](https://developers.openai.com/api/reference/resources/realtime/subresources/client_secrets)
y [eventos de transcripción](https://developers.openai.com/api/docs/guides/realtime-transcription).

Prueba manual: recompilar, iniciar una sesión nueva y saludar como recepción.
Comprobar las filas «Interlocutor» y «Agente», primero en japonés y luego hablando
en español con el agente en japonés. Verificar que el texto entrante conserva su
posición cuando llega después de la respuesta del agente y que `ask_user` sigue
funcionando. La llamada Telnyx aún no alimenta esta sesión: requiere el puente.

Verificación de esta ampliación: **41 pruebas aprobadas, 0 fallos, 0 omitidas**
en simulador iPhone 17 Pro con iOS 26.5. Tres pruebas nuevas cubren orden y
texto final, fallo no fatal durante `ask_user` y eventos de sesiones anteriores.
