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
Durante ese tránsito el refresco pasa de 10 a 2 segundos y la pantalla muestra
el progreso `Palé cerrado > Registro NAV > Etiqueta`, el tiempo transcurrido y
las comprobaciones realizadas. Una conciliación aún en curso se distingue de
una incidencia que realmente requiere una acción de recuperación.

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
solicitan la tarjeta RFID del propio operario. El selector muestra solo `WC` y
`PAUSA_CALOR` y una nota con el número de motivos pendientes de definir; el
contrato actual solo registra esos dos.

## Composición fija de Trabajo

La fase 3 se compone como un panel fijo para la pantalla de 32″ a 1920×1080,
sin scroll: a partir de 1500 px de ancho se divide en dos columnas. La
izquierda contiene la cabecera de orden y una rejilla 3×2 de operarios (máximo
seis). El lector RFID ocupa el primer hueco libre de esa rejilla y desaparece
cuando la mesa está completa. La derecha contiene el panel de tiempos y el
bloque `NAV e impresión` con altura reservada. El título de página queda solo
para lectores de pantalla y las acciones `Nueva orden` y `Cambiar de línea`
pasan a la tira de fases. Los avisos se superponen como toast para no robar
altura. Por debajo de 1500 px se conserva la disposición apilada.

El panel de tiempos muestra un semáforo y el porcentaje de cumplimiento:
`unidades buenas ÷ unidades teóricas acumuladas`, donde las unidades teóricas
proceden de los tramos de capacidad del servidor (`theoreticalUnitsToDate`) y
avanzan localmente con la capacidad actual. Gris hasta el primer palé; verde
≥ 95 %, ámbar 80–95 %, rojo < 80 % o mesa sin operarios productivos. La fila
`Promedio operarios` divide los segundos-recurso acumulados
(`resourceSeconds`) entre los segundos transcurridos desde que se abrió la
mesa.
