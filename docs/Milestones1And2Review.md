# Revisión de milestones 1 y 2 — 2026-09-12

## Evaluación

La separación SwiftUI / CallController / TelnyxCallService es suficiente para
este MVP. El formulario, resumen, llamada saliente y selección independiente de
idioma de interfaz y agente cubren el alcance actual. La validación de audio
bidireccional en iPhone fue realizada previamente por el usuario.

No hace falta introducir backend, persistencia, CallKit ni otra arquitectura
antes del milestone 3.

## Correcciones

- Cancelar durante el permiso del micrófono invalida ese intento. Aceptar después
  no marca el número, incluso si se ha abierto un segundo intento.
- Se rechazan ejecuciones duplicadas y eventos tardíos de servicios anteriores.
  Cada intento crea su propio servicio; los callbacks se desvinculan al terminar.
- Los eventos de ciclo de vida de Telnyx se procesan en la cola principal.
  Una desconexión definitiva también finaliza la llamada activa y libera audio.
- El altavoz solo puede cambiarse cuando la llamada está conectada.
- El formulario conserva lo escrito: el formateador anterior eliminaba el cero
  inicial japonés durante la edición y podía modificar el número. La conversión
  a E.164 se realiza para marcar; la validación rechaza letras, extensiones y
  signos `+` mal colocados en lugar de eliminarlos silenciosamente.
- Los errores propios de la app respetan inglés/español. El permiso del sistema
  tiene traducción española y sigue el idioma elegido por iOS; los detalles
  técnicos enviados por Telnyx se conservan tal como llegan.
- La documentación del puente distingue una propuesta técnica de una prueba
  experimental completada.

## Validación automática

Resultado: **16 pruebas aprobadas, 0 fallos**, en iPhone 17 Pro Simulator con
iOS 26.5. Compilación para iPhone físico verificada sin firma.

Las pruebas cubren los campos requeridos, normalización telefónica, idioma,
cancelación del permiso, ejecución duplicada, rechazo del permiso y eventos de
una llamada anterior. Utilizan un servicio falso y no realizan llamadas reales.

## Comprobación final en iPhone

1. En español y en inglés, completar el formulario y comprobar el resumen.
2. Probar un teléfono japonés con cero inicial y uno internacional con `+81`.
3. Cancelar antes de conectar y volver a intentar. Si aparece el permiso del
   micrófono, cancelar la llamada antes de aceptarlo y comprobar que no se marca.
4. Repetir una llamada real: audio en ambas direcciones, altavoz/auricular y
   cierre desde cada teléfono. Comprobar duración y una segunda llamada.
5. Durante una llamada, cortar la conectividad y comprobar que se recupera o
   termina con un error, sin quedar permanentemente en «Conectado».

La prueba real de audio debe repetirse tras los cambios de ciclo de vida.
El milestone 3 sigue pendiente y debe probar Realtime de forma independiente.
El puente Telnyx/Realtime permanece pendiente de validación experimental.
