# Flujo operativo de producción

Pantalla única para el recorrido del operario:

1. identificación de línea;
2. selección de orden;
3. trabajo: equipo, tiempos y palés.

La paletización permanece dentro de Trabajo y las reservas técnicas no se
presentan al operario. NAV se muestra como un estado de segundo plano, nunca
como un paso que haya que completar manualmente. `Nueva orden` conserva la
línea seleccionada; si todavía hay operarios activos impide abandonar la mesa.
Cuando la orden alcanza `PENDIENTE_CIERRE`, la misma acción se presenta como
`Finalizar orden` y confirma expresamente que la orden quedó finalizada y la
línea libre para escanear la siguiente. La confirmación se mantiene visible
inmediatamente bajo la cabecera, antes del progreso y del nuevo campo de
escaneo, para que no quede fuera de pantalla al abandonar la mesa terminada.

Al escanear una orden que todavia no esta en la lista MES, primero se conserva
la recuperacion de una mesa pendiente y, si no existe, se solicita al servidor
la preparacion exacta desde EbirTest. El operario recibe confirmacion antes de
identificar el equipo o un rechazo funcional seguro sin abandonar el paso de
escaneo.

La interfaz usa los contratos MES existentes y no simula transiciones. Las
credenciales RFID se envían para identificación, se eliminan del campo
inmediatamente y no se incorporan al estado de la pantalla.
