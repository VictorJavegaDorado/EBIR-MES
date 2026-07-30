# Instrucciones de Application

- Cada carpeta representa una funcionalidad del mapa funcional.
- Dentro de una funcionalidad, separa casos de uso solo cuando tengan comandos,
  consultas o reglas diferentes.
- Los casos de uso coordinan dominio y límites externos; no contienen SQL ni
  detalles HTTP.
- Crea el contrato mínimo que necesite el caso de uso. No uses repositorios
  genéricos.

