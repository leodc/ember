# Milestone 5 — prueba inicial del acceso a PCM

Iniciado el **2026-09-13**, tras la aceptación del milestone 4. **Milestone 5 en
curso, no completado**. Esta entrega implementa el primer paso experimental
indicado en [AudioBridgeFeasibility](AudioBridgeFeasibility.md): tono y retorno
con Telnyx antes de añadir OpenAI al recorrido de audio.

## Actualización tras la prueba del usuario — 2026-09-13

El usuario ha validado tono, retorno de voz y los tres cierres en el iPhone.
La etapa siguiente conecta Telnyx y OpenAI por dos dispositivos PCM WebRTC.
Ver [evidencia física y próxima prueba](Milestone5RealtimeBridge.md).
Las secciones siguientes conservan la entrega inicial y sus límites de entonces.

## Resultado de esta entrega

- Dispositivo virtual `AudioBridgeProbeDevice`: PCM Int16 mono, 48 kHz,
  480 muestras cada 10 ms. Un hilo dedicado estable atiende los callbacks
  `getPlayoutData` y `deliverRecordedData` de WebRTC M150.
- Captura del audio decodificado del receptor y suministro de un tono de 440 Hz
  de un segundo, con nivel limitado y pequeños fundidos. Retorno opcional de la
  voz recibida, atenuado a la mitad y retrasado 300 ms en un buffer acotado.
- No utiliza `AVAudioEngine`, `AVAudioSession`, micrófono, altavoz, archivos de
  audio ni backend. La llamada de prueba no solicita permiso de micrófono.
- Botón **Probar el puente de audio** en el resumen cuando existe un número
  válido. Abrir la pantalla no marca; **Llamar y probar audio** inicia la llamada.
- Cierre manual, cierre de pantalla, segundo plano, fallo y desconexión detienen
  el dispositivo y cuelgan. Intentos duplicados y eventos de sesiones anteriores
  se descartan. Timeout de conexión de 60 segundos. El POC termina si detecta
  reconexión después de estar conectado; no pretende recuperar audio pendiente.
- Contadores en pantalla una vez por segundo y logs de contadores cada cinco
  segundos, sin registrar contenido de voz ni números/credenciales. No hay transcripción, herramientas ni audio de OpenAI
  dentro de esta prueba. El ensayo Realtime conserva el comportamiento del M4.

La dependencia Telnyx pública no permite inyectar ese dispositivo. Por eso el
proyecto utiliza una copia local de **TelnyxRTC 4.2.0**, con un parche explícito
sobre tres archivos. No se cambian las cachés de Xcode. Procedencia, licencia y
parche: [Vendor/telnyx-webrtc-ios/EMBER_PATCH.md](../Vendor/telnyx-webrtc-ios/EMBER_PATCH.md).

## Evidencia técnica

La prueba `AudioBridgeNativeTests.testTwoCustomDevicesExchangeToneWithoutHardwareAudio`
crea dos conexiones WebRTC reales en el simulador, negocia SDP e ICE localmente y
conecta un dispositivo virtual a cada una. **Ambas reciben el tono PCM generado
por la otra**, con más de diez bloques de señal recibidos por extremo y cero
errores de callback. Después de detenerlas se comprueba que los contadores dejan
de avanzar y que ambos dispositivos se liberan junto con sus factories. No usa Telnyx, OpenAI, micrófono ni altavoz.

Esto demuestra el acceso nativo a PCM en el binario WebRTC M150 del simulador.
**No demuestra todavía el recorrido Telnyx/PSTN, la calidad auditiva ni el
funcionamiento en un iPhone físico.** Los contadores incluyen silencios y no
acreditan por sí solos que el receptor escuche audio.

- [64 pruebas aprobadas, cero fallos y cero omitidas](audio-bridge/tests-summary.json):
  las 54 anteriores, cinco de señal, cuatro de ciclo de vida del controlador y
  una de intercambio real entre peers WebRTC locales, incluida su liberación.
- Compilación Debug para simulador y Release para iPhone sin firma correctas.
  Revisión de la pantalla en español con una llamada simulada, sin red.
- No se ha realizado una llamada real, instalado esta versión en un iPhone ni
  utilizado consumo de OpenAI durante estas pruebas.

## Prueba manual en tu iPhone

1. Abre `AIPhoneAgent.xcodeproj` en Xcode y ejecuta en el iPhone. Se mantienen las
   credenciales Telnyx de `Config.local.xcconfig`; no hacen falta nuevas claves.
2. Prepara una definición con el teléfono de tu esposa y pasa al resumen.
3. Abre **Probar el puente de audio**. Pulsa **Llamar y probar audio**. Se marca
   un número real y se aplican los costes habituales de Telnyx.
4. Que ella conteste usando el **auricular**, sin altavoz. Mantén Ember en primer
   plano. La pantalla debe pasar a **Conectado**.
5. Pulsa **Enviar un tono de 1 segundo**. Ella debe escuchar un tono breve.
   Los bloques enviados con señal deben aumentar. Tú no necesitas hablar.
6. Pulsa **Activar retorno de voz**. Que ella pronuncie una frase: debe escuchar
   su propia voz con un pequeño retraso. Deben subir los bloques recibidos con
   señal y enviados con señal. Detén el retorno tras comprobarlo.
7. Habla cerca del iPhone mientras ella está callada: tu voz no debe llegar al
   otro teléfono. El altavoz y volumen del iPhone no forman parte del puente.
8. Termina desde Ember y comprueba que el otro teléfono cuelga. Repite terminando
   desde el otro teléfono. Repite enviando Ember a segundo plano.
9. Vuelve a probar **Llamada telefónica · Hablas tú** y **Ensayar con Ember** para
   comprobar en el dispositivo físico las dos experiencias previamente validadas.

Si algo falla, conserva los siete valores del diagnóstico y describe qué escuchó
ella: ningún sonido, tono correcto, voz retardada, cortes, distorsión o eco.
No hace falta compartir credenciales ni grabar contenido personal.

| Indicador | Cómo interpretarlo |
| --- | --- |
| Bloques recibidos | WebRTC entregó PCM decodificado; puede ser silencio |
| Recibidos con señal | El pico superó 64/32768; ruido también puede contarse |
| Bloques enviados a Telnyx | El callback de suministro aceptó PCM; puede ser silencio |
| Enviados con señal | PCM generado o retornado por encima del umbral |
| Pico remoto | Máximo absoluto del último bloque, 0–32768 |
| Errores de audio | Debe mantenerse en cero; un error termina la prueba |
| Ciclos con retraso | El hilo se retrasó más de 20 ms; aumentos frecuentes requieren investigar |

## Alternativa considerada inicialmente para el siguiente paso

Tras validar tono y retorno en la llamada física, conectar el PCM del receptor a
OpenAI y devolver su voz generada a Telnyx. La API oficial ofrece
[`input_audio_buffer.append` y `response.output_audio.delta`](https://developers.openai.com/api/docs/guides/realtime-conversations)
sobre WebSocket, con PCM a 24 kHz. Esa vía requerirá conversión explícita desde
48 kHz, colas acotadas, manejo de congestión, truncado al interrumpir y cierre
tras drenar el audio local. No se ha implementado ni se declara validada aquí.

El criterio final sigue siendo que tu esposa hable y escuche la respuesta de
OpenAI sin que tú hables. Después se hará el flujo completo `ask_user` del M6.
No confundir la prueba nativa local, la prueba física de tono/retorno y ese
criterio final: cada una aporta evidencia distinta.

## Repetir las comprobaciones locales

```sh
xcodebuild -project AIPhoneAgent.xcodeproj -scheme AIPhoneAgent \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test

xcodebuild -project AIPhoneAgent.xcodeproj -scheme AIPhoneAgent \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

La prueba nativa usa ICE local entre peers del simulador, sin cuentas ni servicios
externos. Si el entorno bloquea la red local o no tiene ese simulador, selecciona
un simulador iOS disponible y conserva la distinción entre fallo de entorno y
fallo de PCM. Para ejecutar solo esa comprobación, añade
`-only-testing:AIPhoneAgentTests/AudioBridgeNativeTests`.

Galería Debug: `--visual-review bridge-ready` o `--visual-review bridge-connected`,
con `--review-language en` para inglés y `--review-accessibility` para texto grande.
Todos los controles de esta galería usan un servicio falso y no pueden marcar.
Capturas: [inicio](audio-bridge/probe-ready-es.png) y
[controles durante la llamada simulada](audio-bridge/probe-connected-es.png).
