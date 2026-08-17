# Especificacion de cambio NAV-001A

Esta especificacion describe comportamiento y puntos de modificacion. No es
codigo C/AL importable y no sustituye el backup ni la comparacion de objetos en
Object Designer.

## 1. Tabla 50013 `Salidas Fabricacion`

Agregar el campo 700:

- nombre: `Origen MES`;
- tipo: Boolean;
- clasificacion: `SystemMetadata`;
- valor historico y predeterminado: `FALSE`.

Antes de agregarlo se debe confirmar que el campo 700 sigue libre. No se
reutilizara otro campo sin actualizar y volver a revisar este paquete.

Agregar una funcion publica `TryClaimRegistration`, con este contrato:

1. recibir el identificador de salida y, opcionalmente, exigir origen MES;
2. bloquear la tabla antes de releer el registro;
3. devolver `FALSE` si no existe, ya no esta `Pendiente` o no cumple el origen;
4. cambiar una sola vez `Pendiente` a `Procesando` y limpiar `Error Estado`;
5. confirmar la reclamacion antes de ejecutar contabilizacion externa al registro;
6. devolver el registro reclamado al llamador;
7. no reabrir automaticamente estados `Procesando`, `Error`, `Anulado` o `Registrado`.

La reclamacion debe ser la unica ruta autorizada para iniciar un registro. Un
estado `Procesando` abandonado exige conciliacion por identificador antes de
cualquier intervencion manual.

## 2. Codeunit 82000 `WS Control Planta`

Conservar la firma y comportamiento de `OpenClosePallet` para DataCPP y otros
clientes. Esa operacion debe continuar creando salidas con `Origen MES=FALSE`.

Agregar una funcion publica `OpenClosePalletMES` con los mismos parametros que
`OpenClosePallet`. Ambas deben delegar en una funcion local comun que reciba el
origen. Al cerrar el bulto, `InsertSalidas` debe guardar `Origen MES` dentro de
la misma unidad de trabajo que crea la salida y vincula `Factory Outputs No.`.

La apertura no crea una salida. La marca se aplica solo cuando el cierre crea
la fila 50013. No se cambia `RegistrarSalidaFabricacion`, el calculo del bulto,
la linea de montaje ni los datos del operario.

La funcion `_RegistrarMovimientoSalida` y cualquier ruta interna que pase una
salida a `Procesando` deben usar `TryClaimRegistration`; queda prohibido
mantener una asignacion directa de estado como mecanismo de reclamacion.

## 3. Pagina 50036 `Salidas Fabrica`

Exponer `Origen MES` como campo no editable para que OData pueda verificar el
origen sin permitir cambiarlo.

Las acciones `Registrar` y `Registrar (ALM INTERNO)` deben reclamar cada fila
mediante `TryClaimRegistration` antes de ejecutar los codeunits existentes.
La accion ALM no puede conservar su ruta actual sin comprobacion de estado.

Una fila que no se pueda reclamar se omite y no se fuerza de nuevo a
`Pendiente`. Los errores posteriores conservan el comportamiento auditado
actual, pero nunca provocan un segundo registro automatico.

## 4. Report 50056 `Registra salidas fabrica`

Agregar un Boolean de request page `SoloSalidasMES`, persistible en las
opciones de Job Queue.

- con `FALSE`, conservar la seleccion historica;
- con `TRUE`, filtrar ademas por `Origen MES=TRUE`;
- en ambos modos, reclamar con `TryClaimRegistration` y releer antes de procesar;
- si la reclamacion falla, omitir la fila;
- conservar la bifurcacion actual entre fabricacion interna y subcontratista;
- tras exito interno, ejecutar `ImprimirAlRegistrar` solo cuando
  `Origen MES=FALSE`;
- nunca imprimir desde NAV una salida con `Origen MES=TRUE`.

La entrada historica de Job Queue permanece `En espera` y no se modifica. Una
fase posterior creara una entrada independiente del mismo Report 50056, con
`SoloSalidasMES=TRUE`, inicialmente tambien `En espera`.

## 5. Codeunit 60103 `Consumos Fabrica`

Al principio de la funcion local que registra la salida, antes de limpiar o
crear lineas de diario, consultar los movimientos de producto por:

- tipo de movimiento `Output`;
- orden de produccion exacta;
- producto exacto;
- `External Document No.` igual al identificador decimal de la salida 50013.

Resultados permitidos:

- cero movimientos: continuar por la contabilizacion normal;
- conjunto unico y coherente cuya cantidad total coincide exactamente con
  `Cantidad salida`: marcar la salida `Registrado`, limpiar el error y salir
  sin crear ni registrar diario;
- cualquier cantidad, producto, orden o conjunto ambiguo: abortar con error
  funcional y no contabilizar.

La comprobacion historica de orden completada se conserva despues de esta
reconciliacion exacta. El nuevo identificador es la barrera principal para
cualquier palet, no solo para el ultimo.

El diario nuevo debe seguir asignando el identificador de salida a
`External Document No.` antes de contabilizar. El codeunit no imprime.

## 6. Contrato MES posterior

Una release MES futura cambiara exclusivamente las dos llamadas de apertura y
cierre del bulto desde `OpenClosePallet` a `OpenClosePalletMES`. No se activara
hasta que el WSDL de `EbirTest` publique la operacion nueva y las pruebas de
compatibilidad demuestren que las operaciones existentes no han cambiado.

La confirmacion MES continuara dependiendo de OData `Registrado` e
`IsOpenPallet`; la respuesta SOAP o el estado `Procesando` no bastan.

## 7. Invariantes de seguridad

- una salida MES produce como maximo un movimiento productivo;
- una reclamacion pertenece a un solo ejecutor;
- ninguna recuperacion cambia a ciegas `Procesando` a `Pendiente`;
- la cola MES no procesa salidas heredadas;
- la impresion NAV nunca se ejecuta para origen MES;
- el Report 50056 historico y DataCPP conservan su contrato por defecto;
- ninguna fase contacta produccion.
