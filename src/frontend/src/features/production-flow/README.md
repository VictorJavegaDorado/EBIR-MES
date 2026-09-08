# Flujo operativo de producción

Pantalla única para el recorrido del operario. Mantiene tres pantallas de
captura y muestra cinco fases visuales persistentes:

1. línea y orden;
2. identificación de operarios;
3. producción y palés;
4. confirmación NAV e impresión;
5. finalización de orden.

La paletización permanece dentro de Trabajo y las reservas técnicas no se
presentan al operario. NAV se muestra como un estado de segundo plano, nunca
como un paso que haya que completar manualmente. `Nueva orden` conserva la
línea seleccionada; si todavía hay operarios activos impide abandonar la mesa.
Cuando la orden alcanza `PENDIENTE_CIERRE`, la misma acción se presenta como
`Finalizar orden` y confirma expresamente que la orden quedó finalizada y la
línea libre para escanear la siguiente. La confirmación se mantiene visible
inmediatamente bajo la cabecera, antes del progreso y del nuevo campo de
escaneo, para que no quede fuera de pantalla al abandonar la mesa terminada.
El refresco automático recupera conjuntamente la orden y la mesa activas de la
línea. Así, cuando el último palé queda confirmado en NAV y su etiqueta está
disponible, la transición a `PENDIENTE_CIERRE` cambia el botón a
`Finalizar orden` sin recargar manualmente el navegador.

Al escanear una orden que todavia no esta en la lista MES, primero se conserva
la recuperacion de una mesa pendiente y, si no existe, se solicita al servidor
la preparacion exacta desde EbirTest. El operario recibe confirmacion antes de
identificar el equipo o un rechazo funcional seguro sin abandonar el paso de
escaneo.

La interfaz usa los contratos MES existentes y no simula transiciones. Las
credenciales RFID se envían para identificación, se eliminan del campo
inmediatamente y no se incorporan al estado de la pantalla.

Las tarjetas de operario presentan `Cerrar palé` como acción principal. `PARO`
abre un selector de motivos y `PARO`, `Reincorporar` y `Salir de la mesa`
solicitan la tarjeta RFID del propio operario. Las posiciones `Motivo 3` a
`Motivo 10` permanecen visibles pero deshabilitadas hasta disponer del catálogo
real; el contrato actual solo registra `WC` y `PAUSA_CALOR`.
