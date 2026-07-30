# Instrucciones de API

- Los endpoints validan transporte, invocan un caso de uso y traducen su
  resultado a HTTP.
- No contienen SQL ni reglas productivas.
- Usa rutas funcionales estables y respuestas de error coherentes.
- No expongas excepciones, nombres internos de tablas o detalles de sistemas
  externos.

