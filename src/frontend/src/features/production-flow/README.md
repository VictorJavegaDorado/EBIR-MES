# Flujo operativo de producción

Pantalla única para el recorrido del operario:

1. identificación de línea;
2. selección de orden;
3. trabajo: equipo, tiempos y palés.

La paletización permanece dentro de Trabajo y las reservas técnicas no se
presentan al operario. NAV se muestra como un estado de segundo plano, nunca
como un paso que haya que completar manualmente. `Nueva orden` conserva la
línea seleccionada; si todavía hay operarios activos impide abandonar la mesa.

La interfaz usa los contratos MES existentes y no simula transiciones. Las
credenciales RFID se envían para identificación, se eliminan del campo
inmediatamente y no se incorporan al estado de la pantalla.
