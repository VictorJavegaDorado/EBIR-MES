# Runbook NAV-001C en EbirTest

Cada fase que cambie la Job Queue o contacte NAV necesita autorizacion expresa.

## Fase 0 - Prevuelo de solo lectura

1. Confirmar `NAVISION2 / EbirTest / EBIR` y `EBIR\NAVEBIR`.
2. Comparar Codeunit 50009 y Table 472 con los exports protegidos actuales.
3. Filtrar Job Queue por Codeunit 50009 y token
   `MES-SOLO-SALIDAS-V1`; exigir una unica fila en `En espera`.
4. Fotografiar los valores actuales de esa fila y el inventario de las demas
   entradas, sin mostrar parametros ajenos.
5. Confirmar tarea de sistema vacia, cero ejecuciones activas y cero errores.
6. Confirmar que el dia del canario esta permitido para `EBIR\NAVEBIR`.
7. Confirmar `041A` instalado y cero operaciones `SALIDA_PALET` no terminales
   en `EBIR_MES_TEST`.
8. Confirmar `MES NAV Worker` ausente o detenido y `MES Worker` limitado a
   impresion.

## Fase 1 - Preparar sin ejecutar

Con la entrada aun en `En espera`, editar exclusivamente:

1. proyecto periodico: `Si`;
2. lunes, martes, miercoles, jueves, viernes, sabado y domingo: `Si`;
3. hora inicial: `00:00:00`;
4. hora final: `23:59:59`;
5. minutos entre ejecuciones: `1`;
6. fecha/hora inicial mas temprana: el instante aprobado para el canario;
7. fecha/hora de caducidad: vacia.

Releer la fila y confirmar que descripcion, token, Codeunit 50009, intentos,
impresora y opciones de informe no cambiaron. Detenerse antes de `Listo`.

## Fase 2 - Canario sin salida pendiente

Solo con nueva autorizacion:

1. verificar otra vez que no existe trabajo MES pendiente;
2. cambiar la entrada a `Listo` con `EBIR\NAVEBIR`;
3. observar un ciclo completo sin usar `Run` interactivo;
4. exigir que la fila siga existiendo y vuelva a `Listo` con una proxima
   ejecucion posterior;
5. confirmar cero movimientos, cero impresiones y cero cambios en otras
   entradas;
6. devolverla a `En espera` antes de terminar esta fase.

## Fase 3 - Canario integrado

Despues de activar una release validada e instalar `MES NAV Worker`, crear una
orden nueva de piloto y recorrer el circuito normal. No se detienen ni alternan
los Workers. Para cada palet se observa:

1. una operacion MES `SALIDA_PALET`;
2. una unica escritura mediante el codeunit de planta;
3. una unica fila NAV que termina `Registrado`;
4. reconciliacion automatica 041A si OData publica con retraso;
5. una etiqueta habilitada e impresa por el servicio separado;
6. entrada NAV recurrente conservada en `Listo`.

## Parada y rollback

1. poner la entrada en `En espera` y confirmar tarea detenida;
2. detener `MES NAV Worker` con cancelacion cooperativa;
3. comprobar cero reservas SQL y cero salidas inciertas;
4. restaurar los campos periodicos a `No`, todos los dias a `No`, horas y
   fechas vacias, conservando maximo de intentos 1;
5. validar de nuevo la entrada mediante el procedimiento administrativo solo
   si permanece exactamente en el contrato detenido de NAV-001B.

Nunca se borra la fila durante un resultado incierto ni se repite manualmente
Report 50056.
