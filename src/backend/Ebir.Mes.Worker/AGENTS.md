# Instrucciones de Worker

- Solo procesa trabajo previamente persistido.
- No inicia llamadas a NAV o impresión durante el arranque.
- Cada procesador debe tolerar reintentos y apagado mediante cancelación.
- Registra identificadores de correlación, nunca secretos ni datos personales
  innecesarios.

