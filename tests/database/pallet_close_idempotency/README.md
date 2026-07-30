# Pruebas del paquete 014

Estado: **diseñadas; no ejecutadas**.

Destino exclusivo: `EBIR_MES_TEST`.

La validación autorizada deberá usar fixtures `ZZTEST_014` / `ZZ14-` y cubrir:

1. cierre ordinario con un único palé, operación NAV y etiqueta;
2. repetición idéntica con el mismo `palet_id` y sin filas adicionales;
3. reutilización de correlación con cantidad, actor, autorización, parcialidad
   o motivo distintos, esperando `55403`;
4. correlación usada por otra operación, esperando `55402`;
5. propagación de los rechazos productivos `51400–51409`;
6. dos clientes concurrentes con la misma correlación y un único cierre;
7. dos correlaciones concurrentes sobre la misma reserva y un único ganador;
8. permiso efectivo limitado a `EXECUTE` para `mes_runtime`;
9. limpieza total de fixtures y `DBCC CHECKDB`.

Las fases se materializarán en scripts separados de prevuelo/fixtures,
funcionales, clientes de concurrencia, permisos y limpieza antes de solicitar
la instalación. Ninguna prueba contactará NAV, RFID o impresoras.
