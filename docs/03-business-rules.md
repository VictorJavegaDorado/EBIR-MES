# Reglas de negocio transversales

## Turnos

- `MANANA`: 06:00–14:00.
- `TARDE`: 14:00–22:00.
- Una sesión nueva entre 22:00 y 23:59 pertenece a `TARDE` del día actual.
- Una sesión nueva entre 00:00 y 05:59 pertenece a `TARDE` del día anterior.
- Fuera del horario ordinario se exige supervisor, confirmación explícita y
  auditoría.
- No existe turno nocturno.

## Consistencia

- Las transiciones productivas se validan y persisten en el servidor.
- Una acción repetida desde un terminal no debe duplicar producción, palés,
  scrap, movimientos ni trabajos de impresión.
- Las llamadas externas no forman parte de una transacción SQL; se persiste una
  intención y un worker la procesa con reintentos controlados.
- Toda corrección manual relevante conserva el valor anterior, el nuevo valor,
  el actor y el motivo.

