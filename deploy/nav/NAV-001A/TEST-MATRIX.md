# Matriz de pruebas NAV-001A

Las pruebas con objetos NAV se ejecutaran solo en `EbirTest`, despues de una
autorizacion distinta. Los casos estaticos no contactan sistemas externos.

## Estaticas y compilacion

| Caso | Resultado exigido |
|---|---|
| Baseline | Los cinco hashes coinciden antes de editar |
| Asignacion | El campo 700 esta libre |
| Exportacion | No se guarda ningun objeto, `.fob` o configuracion en Git |
| Compilacion | 50013, 50036, 50056, 60103 y 82000 compilan en `EbirTest` |
| WSDL | Aparece `OpenClosePalletMES`; las operaciones previas no cambian |
| OData | `Origen MES` es legible y no editable |

## Compatibilidad de creacion

| Caso | Resultado exigido |
|---|---|
| Apertura heredada | `OpenClosePallet` no crea salida y conserva el bulto abierto |
| Cierre heredado | La salida creada tiene `Origen MES=FALSE` |
| Apertura MES | `OpenClosePalletMES` no crea salida |
| Cierre MES | Crea una sola salida con `Origen MES=TRUE` y vinculo al bulto |
| Error o timeout | No se repite el cambio de bulto sin consultar `IsOpenPallet` |

## Reclamacion concurrente

| Caso | Resultado exigido |
|---|---|
| Dos sesiones | Solo una cambia la fila de `Pendiente` a `Procesando` |
| Boton y cola | Solo uno obtiene la reclamacion |
| ALM interno | No ejecuta 60103 sin reclamacion previa |
| Estado no pendiente | No se reabre ni procesa |
| Origen incorrecto | El modo MES no reclama la salida heredada |

## Idempotencia de contabilizacion

| Caso | Resultado exigido |
|---|---|
| Sin movimiento previo | Se contabiliza exactamente una vez y queda `Registrado` |
| Movimiento exacto previo | Se concilia a `Registrado` sin registrar diario |
| Cantidad diferente | Error funcional, cero nuevas contabilizaciones |
| Orden o producto diferente | No se acepta como coincidencia |
| Multiples filas coherentes | Solo se acepta si el conjunto es inequivoco y suma exacta |
| Conjunto ambiguo | Error funcional y revision manual |
| Ultimo palet historico | Se conserva la recuperacion por orden completada |

## Seleccion e impresion

| Caso | Resultado exigido |
|---|---|
| Report sin modo MES | Conserva el comportamiento heredado |
| Report con modo MES | Solo selecciona `Pendiente` y `Origen MES=TRUE` |
| Exito MES | Cero llamadas a `ImprimirAlRegistrar` |
| Exito heredado | Mantiene la impresion NAV existente |
| Cola historica | Permanece `En espera` y sin cambios |
| Cola MES nueva | Nace `En espera`, sin ejecucion ni programacion |

## Canario futuro

El primer canario debe usar una sola salida futura conocida. El prevuelo debe
demostrar cero salidas MES elegibles adicionales, cero estados ambiguos y
Printing MES desactivado. El resultado aceptable es un unico movimiento NAV,
salida `Registrado`, conciliacion MES por el mismo identificador, una etiqueta
MES lista y ningun envio a impresora.
