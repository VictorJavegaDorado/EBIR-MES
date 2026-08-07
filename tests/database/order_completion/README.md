# Finalizacion de orden productiva

`verify-035A-static.ps1` valida sin conectar a SQL que el paquete 035A:

- esta limitado a `EBIR_MES_TEST`;
- exige orden completa, mesa sin recursos y salidas NAV confirmadas;
- permite etiquetas `LISTA` o `IMPRESA`, desacoplando la impresora de la linea;
- finaliza orden y sesion y libera la linea;
- concede solo ejecucion al principal runtime.

La validacion transaccional contra SQL se realiza en una fase expresamente
autorizada: instalar 035A dentro de su propia transaccion, comprobar permisos y
definicion, y ejecutar el procedimiento sobre un fixture sintetico con rollback.
El ensayo con `FL26-00003` es una fase funcional posterior y no sustituye al
fixture eliminable.
