# Operación de línea

Incluye identificación de línea, apertura de sesión, turnos, entradas, salidas,
ausencias, sustituciones y finalización de sesión.

La base normativa detallada está en los paquetes SQL 011 y 012:

- `database/011_DISENO_SESIONES_TURNOS_FICHAJES.md`
- `database/012_DISENO_AUSENCIAS_SUSTITUCIONES_CORRECCIONES.md`

La API será la única autoridad para iniciar y finalizar estas transiciones. El
cliente muestra el estado devuelto y no reconstruye las reglas horarias.

