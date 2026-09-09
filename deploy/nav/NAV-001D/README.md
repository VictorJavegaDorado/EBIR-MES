# NAV-001D - Disparo inmediato y aislado de la cola MES

Estado: `PREPARADO_NO_APLICADO`.

Este paquete reduce la espera entre el cierre de un palet y su etiqueta sin
crear un segundo procesador ni cambiar la recurrencia de un minuto. Cuando MES
observa su salida exacta en estado `Pendiente`, solicita al Codeunit 82000 que
reprograme exclusivamente la entrada del Codeunit 50009
`MES-SOLO-SALIDAS-V1` para comenzar en
aproximadamente un segundo. La tarea conserva el usuario `EBIR\NAVEBIR` y el
Report 50056 sigue siendo el unico procesador.

La Job Queue recurrente de un minuto permanece activa como respaldo. El camino
rapido esta desactivado por defecto en MES y solo se habilita tras compilar,
publicar, inspeccionar el WSDL y superar un canario en `EbirTest / EBIR`.

## Objeto afectado

| Tipo | Id. | Nombre | Cambio |
|---|---:|---|---|
| Codeunit | 82000 | WS Control Planta | Funcion SOAP `TriggerMesEntryNow` |

No se modifica el Codeunit 50009, el Codeunit 453, el Report 50056 ni ninguna de las otras
entradas de Job Queue. Los objetos NAV importables y sus backups permanecen
fuera de Git bajo `C:\ProgramData\EBIR\MES\protected\nav\NAV-001D`.

## Barreras

- solo `NAVISION2 / EbirTest / EBIR`;
- ninguna escritura SQL contra NAV;
- ningun registro directo bajo la identidad del servicio MES;
- ninguna impresion desde NAV;
- ningun bucle inferior a un minuto dentro de NAV;
- ninguna ejecucion interactiva del Codeunit 50009;
- no importar, compilar, publicar, activar ni ejecutar sin autorizacion de fase.
