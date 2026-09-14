# Milestone 5 — Telnyx y OpenAI conectados por PCM

## Validación física recibida — 2026-09-13

El usuario confirma en el iPhone:

- Su esposa contestó, escuchó el tono y el retorno de voz funcionó bien.
- Colgar desde Ember terminó la llamada.
- Colgar desde el teléfono receptor también la terminó correctamente.
- Al enviar la app que marca a segundo plano, la llamada terminó, según lo previsto.

Los valores visibles en las dos capturas aportadas son:

| Contador | Captura 1, 20:03 | Captura 2, 20:05 |
| --- | ---: | ---: |
| Bloques recibidos | 2777 | 818 |
| Recibidos con señal | 1238 | 647 |
| Bloques suministrados | 2777 | 818 |
| Suministrados con señal | 658 | 232 |
| Pico remoto | 2200 | 22 |
| Errores de callback | 0 | 0 |
| Ciclos retrasados | 0 | 0 |

Se registra el relato del usuario junto a los contadores; los números por sí
solos no prueban audibilidad. No se duplica el número telefónico de las capturas.
Esta evidencia valida **tono y retorno por Telnyx en el iPhone**, y permite pasar
al segundo paso. No valida aún la conversación de OpenAI por teléfono, ni las
comprobaciones no mencionadas (voz junto al micrófono local, Bluetooth, etc.).

## Implementación del segundo paso

`BridgedCallService` coordina una única llamada. Primero prepara Realtime y solo
marca Telnyx cuando OpenAI está listo. Al contestar el receptor, activa ambos
dispositivos virtuales. El audio fluye así:

```text
Teléfono receptor → Telnyx/WebRTC → dispositivo PCM Telnyx
                                  ↓ cola de 100 ms
                         dispositivo PCM OpenAI → OpenAI/WebRTC

Teléfono receptor ← Telnyx/WebRTC ← dispositivo PCM Telnyx
                                  ↑ cola de 100 ms
                         dispositivo PCM OpenAI ← OpenAI/WebRTC
```

Se reutiliza `AudioBridgeProbeDevice`, probado en el primer paso, con dos
endpoints PCM a 48 kHz, Int16 y mono. Cada uno conserva su hilo estable. Las dos
colas son acotadas: vaciar una produce silencio; desbordarla termina la llamada
con un error visible, en lugar de acumular voz antigua. El audio no pasa por un
backend, el micrófono ni el altavoz del iPhone. Tampoco se pide permiso de micrófono.

**Decisión actualizada:** se mantiene WebRTC también con OpenAI, en vez de
introducir el WebSocket/PCM24k considerado en la nota anterior. La API admite
[tracks de audio y eventos por data channel](https://developers.openai.com/api/docs/guides/voice-webrtc?api=realtime),
y el punto de inyección nativo ya está demostrado. Esto permite conservar el
cliente, las transcripciones, `ask_user` e instrucciones escritas del milestone 4,
sin otro transporte ni conversiones innecesarias. El modelo y la voz configurados
se conservan; no se migra a otra API.

- El contexto identifica una llamada telefónica real y a su receptor. El ensayo
  independiente sigue enviando su contexto de ensayo.
- El inicio exige un número válido y muestra que habrá una llamada y costes.
  Abrir la pantalla todavía no marca.
- No se envía audio durante el timbre. Ember espera el saludo del receptor.
- Ante voz entrante o una instrucción escrita se limpia y bloquea la cola hacia
  Telnyx hasta el inicio de la siguiente respuesta. Se conserva la cancelación
  de generación y `output_audio_buffer.clear` de Realtime.
- La despedida espera generación + vaciado de OpenAI + margen existente, después
  ausencia de señal pendiente y un margen adicional de 500 ms para Telnyx. Una
  instrucción escrita durante ese margen puede cancelar el cierre.
- El cierre remoto, manual, por error o al pasar a segundo plano libera las dos
  conexiones y cuelga Telnyx. No hay recuperación de la llamada tras desconexión.
- La preparación tiene un límite de 100 segundos; Telnyx dispone de hasta 60
  segundos desde que se empieza a marcar. Se evita marcar si falla la configuración.
- La pantalla reutiliza transcripciones y controles del ensayo, con textos de
  llamada real, y un diagnóstico desplegable de ambos sentidos. Las respuestas
  siguen viviendo solo durante esa sesión y no modifican el perfil guardado.

## Validación pendiente y límites

El milestone **permanece abierto** hasta que el usuario confirme que su esposa
puede hablar con OpenAI por esta ruta. La validación de tono/retorno no sustituye
esa prueba. El flujo integral de reserva con `ask_user` sigue correspondiendo al
milestone 6, aunque sus herramientas se conservan en esta implementación.

La prueba local del segundo paso usa cuatro peers WebRTC reales: dos representan
los extremos remotos y dos el puente. Verifica PCM en ambas direcciones, ausencia
de retorno accidental al emisor, bloqueo de audio interrumpido y ausencia de
desbordamientos. No marca teléfonos ni consume OpenAI. Se añaden regresiones de
colas, errores, cancelación, orden de conexión y cierre después del audio.

El margen final de audio y la interrupción deben escucharse en la llamada real:
no hay confirmación PSTN por muestra de lo que reprodujo el receptor. Las colas
del puente están acotadas, pero WebRTC, la red y el teléfono remoto también
introducen latencia. Los contadores de bloques incluyen silencio.

## Próxima prueba en el iPhone

1. Compila y ejecuta esta versión desde Xcode. Se usan las mismas credenciales
   locales de Telnyx y OpenAI; no necesitas añadir un servidor.
2. Prepara la llamada de prueba, el objetivo y el idioma del agente.
3. En el resumen elige **Llamada telefónica · Habla Ember → Preparar llamada con
   Ember**. Revisa el número e idioma y pulsa **Llamar con Ember**.
4. Tu esposa contesta y saluda. Tú no hables: Ember debe oírla y responder por el
   teléfono. El iPhone que marca permanece silencioso.
5. Que ella haga una pregunta sencilla relacionada con el objetivo. Comprueba
   que transcripción y respuesta corresponden a su voz. En el diagnóstico deben
   avanzar los cuatro contadores, y aparecer señal del receptor y del agente.
6. Que interrumpa una respuesta del agente; después prueba una instrucción escrita
   breve. Comprueba auditivamente que no continúen frases antiguas.
7. Termina desde ambos extremos en llamadas separadas y prueba el segundo plano.
   Prueba también una despedida solicitada por recepción: debe oírse antes de colgar.
8. Informa si pudo conversar, si hubo cortes/retrasos, si el audio era claro y qué
   mostró el diagnóstico. No compartas claves ni datos personales innecesarios.

Se mantienen **Probar el puente de audio** (tono/retorno), la llamada donde hablas
tú y el ensayo independiente para comparar si hay algún fallo.
