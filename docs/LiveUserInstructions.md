# Instrucciones del usuario durante la conversación

Ampliación del POC solicitada el 2026-09-12. El usuario eligió interrupción inmediata.
Se conserva la prueba Realtime independiente; el puente Telnyx sigue pendiente.

## Comportamiento

«Instrucción para el agente…» y «Interrumpir y enviar» están disponibles desde que
la sesión está conectada, también dentro de `ask_user` y durante la despedida.
El borrador es compartido entre ambas pantallas. No se envían textos vacíos y se
bloquea el envío duplicado mientras se tramita la instrucción actual.

Ejemplos: «También puedo el viernes por la tarde», «Pregunta cuánto cuesta»,
«No aceptes ese tratamiento», «Espera, pregunta la dirección» o «Termina la llamada».
El usuario puede cambiar datos, restricciones y el objetivo de esa sesión. La
recepción no adquiere esa capacidad. La interpretación de estas indicaciones
sigue dependiendo del modelo; no se implementa un motor semántico de reglas.

El agente habla al interlocutor en el idioma configurado y no lee literalmente
la indicación privada. La app muestra el texto enviado como «Tu instrucción».
No modifica el perfil ni persiste las instrucciones. No añade contenido a logs.

## Transporte y ciclo de vida

- Durante el envío se desactiva temporalmente la generación automática de VAD,
  manteniendo la entrada de audio. Se cancela la respuesta identificada mediante
  `response.cancel` y se corta su salida mediante `output_audio_buffer.clear`.
- Se espera `response.done` antes de generar la continuación. Si la respuesta aún
  no tiene ID, se cancela al recibir `response.created`. Se tolera exclusivamente
  el error `response_cancel_not_active` asociado a una cancelación propia, que
  puede llegar si la generación acabó entre la comprobación y la petición.
- Las herramientas del turno interrumpido reciben un resultado de sustitución;
  no se ejecuta un `end_session` que pertenecía a ese turno. Eventos tardíos de
  cancelación no deben afectar a la nueva respuesta.
- Una pregunta pendiente recibe `superseded_by_instruction`, sin `answer` ni
  aprobación inventada. Se cierra el modal y el modelo reevalúa la necesidad de
  preguntar usando los datos reales de la nueva instrucción.
- Se añade `conversation.item.create` con un mensaje `system` marcado
  `APP_USER_INSTRUCTION`, seguido del texto codificado como JSON. Esto distingue
  la indicación escrita del audio de recepción. Se solicita `response.create` y
  se restaura el VAD habitual. «Tu instrucción» indica envío al canal; no prueba
  por sí solo que el modelo ya haya realizado la acción.
- Una instrucción durante la despedida cancela las tareas de cierre y restaura
  el micrófono. Un cierre pedido desde este canal usa `user_requested_end` y la
  despedida normal. La app exige haber enviado una instrucción para aceptar ese
  motivo; determinar que el texto realmente solicita cierre depende del modelo.
- El envío pendiente tiene límite de 30 segundos. Cerrar, perder conexión o pasar
  a segundo plano libera la sesión y descarta la instrucción pendiente. Una
  instrucción o evento tardío no reabre la conexión.

Referencia: [eventos cliente de OpenAI Realtime](https://developers.openai.com/api/reference/resources/realtime/client-events),
`conversation.item.create`, `response.cancel` y `output_audio_buffer.clear`.

## Prueba manual

1. Recompilar y abrir una sesión nueva de **Probar voz de OpenAI** con agente japonés.
2. Mientras el agente habla, escribir «Pregunta cuánto cuesta» y enviar. Debe
   cortar su respuesta y preguntar el precio en japonés; no leer la instrucción.
3. Ofrecer un horario fuera de disponibilidad. En el modal, enviar «También puedo
   ese día a esa hora». Debe reevaluar la consulta y continuar con ese permiso.
4. En una pregunta sobre medicamentos, enviar «Pregunta si puedo dar ese dato en
   la consulta». No debe convertirlo en una respuesta médica inventada. Si el dato
   sigue siendo obligatorio, debe volver a consultarlo.
5. Durante la despedida, enviar «Espera, pregunta la dirección». Debe continuar sin
   colgar por el audio o los eventos de la despedida anterior.
6. Enviar «Termina la llamada». Debe despedirse y cerrar con el estado real de la
   reserva. El cierre manual debe seguir disponible en todo momento.
7. Probar doble pulsación, texto vacío, cierre mientras se envía y nueva sesión.
   No deben duplicarse instrucciones ni reaparecer instrucciones anteriores.
8. Repetir con app en inglés y español, teclado abierto y tamaño de texto grande.
   Revisar que el botón de envío y el de terminar siguen siendo accesibles.

La comprobación real de voz, interrupción auditiva y disposición en iPhone queda
pendiente del usuario; las pruebas automáticas usan transporte/servicios falsos.

## Verificación automática

Suite final en iPhone 17 Pro, simulador iOS 26.5: **51 pruebas aprobadas, 0 fallos,
0 omitidas**. Las 10 pruebas nuevas comprueban texto exacto y canal, duplicados,
interrupción y vaciado de audio, carreras de cancelación, herramientas obsoletas,
preguntas pendientes, despedida, cierre pedido desde la app y eventos tardíos.
`git diff --check` correcto.

## Revisión de interfaz — 2026-09-12

La pantalla de conversación usa una entrada compacta. El modal ofrece
**Dar una nueva instrucción** para cambiar de modo, y **Volver a la pregunta**
para conservar y recuperar la respuesta en edición. Escribir no interrumpe: el
envío explícito aplica la indicación. Capturas y límites de validación en
[Evaluación visual](VisualReview.md).
