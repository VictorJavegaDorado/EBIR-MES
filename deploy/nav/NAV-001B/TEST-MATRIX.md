# Matriz de pruebas NAV-001B

Las pruebas funcionales se ejecutaran solo en `EbirTest` y bajo autorizaciones
posteriores. La prueba estatica no contacta sistemas externos.

## Estaticas y baseline

| Caso | Resultado exigido |
|---|---|
| Paquete | Solo contiene Markdown; ningun objeto NAV o secreto |
| Estado | `PREPARADO_NO_MATERIALIZADO` |
| ID nuevo | Permanece `OBJECT_ID_PENDING_INVENTORY` hasta inventario autorizado |
| Superficie | Page 672 no se publica |
| SQL | No existe ruta de escritura a tablas NAV |
| Ejecucion | Preparar el paquete no ejecuta report, codeunit, cola o impresion |

## Compilacion futura

| Caso | Resultado exigido |
|---|---|
| Baseline | Report 50056 coincide con el objeto compilado de `EbirTest` |
| Table 472 | Campos, opciones y metodos usados existen en NAV 2017 |
| ID | El codeunit elegido esta libre y cubierto por licencia |
| Report 50056 | Compila con `SetSoloSalidasMES` y conserva request page |
| Codeunit nuevo | Compila con `TableNo=472` y permisos minimos |
| Compatibilidad | Report 50056 sin setter conserva `SoloSalidasMES=FALSE` |

## Creacion idempotente futura

| Caso | Resultado exigido |
|---|---|
| Primera llamada | Crea una entrada y devuelve `CREATED_ON_HOLD` |
| Segunda llamada | No modifica nada y devuelve `EXISTS_ON_HOLD` |
| Dos sesiones | Existe como maximo una entrada |
| Duplicado previo | Error funcional y cero escrituras |
| Estado distinto | Error funcional; nunca fuerza `En espera` |
| Configuracion parcial | Error funcional; nunca repara automaticamente |
| Respuesta incierta | Conciliacion previa antes de repetir |

## Guardas de la entrada

| Caso | Resultado exigido |
|---|---|
| Estado | `En espera` |
| Programacion | No periodica, sin dias, horas ni tarea de sistema |
| Intentos | Maximo 1 y realizados 0 |
| Parametro | `MES-SOLO-SALIDAS-V1` exacto |
| Objeto | Solo el codeunit dedicado; no Report directo ni Page 672 |
| Impresion | Impresora vacia y ninguna llamada de impresion |

## Separacion administrativa y productiva

| Caso | Resultado exigido |
|---|---|
| SOAP administrativa | Nunca ejecuta Report 50056 |
| WSDL | Expone `EnsureStoppedMesEntry`; no expone iniciar o ejecutar |
| OnRun sin Job Queue | Rechazado antes de abrir el Report 50056 |
| Parametro incorrecto | Rechazado antes de abrir el Report 50056 |
| OnRun autorizado futuro | Fuerza `SoloSalidasMES=TRUE` y oculta request page |
| Salida heredada | Nunca seleccionada por el modo MES |
| Salida MES | No imprime desde NAV |

## Rollback

| Caso | Resultado exigido |
|---|---|
| Sin entrada creada | Despublicar y retirar objetos sin datos residuales |
| Entrada nunca ejecutada | Borrado solo tras verificar token, ID y estado detenidos |
| Entrada usada | Conservar evidencia y aplicar rollback compatible; no borrar a ciegas |
