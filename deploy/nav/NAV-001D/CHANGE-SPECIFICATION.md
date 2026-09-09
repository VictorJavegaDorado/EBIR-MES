# Especificacion de cambio NAV-001D

## 1. Motivo

Los Workers MES consultan sus colas cada segundo. La espera observable procede
del intervalo de un minuto entre ejecuciones del Codeunit 50009. Ejecutar el
registro directamente desde el SOAP de planta no es admisible: usaria la
identidad del servicio MES en lugar del usuario de la entrada Job Queue.

## 2. Funcion publica `TriggerMesEntryNow`

Agregar al Codeunit 82000 `WS Control Planta` una funcion publica con un unico parametro entero
`SalidaId` y retorno Boolean. La funcion:

1. exige un identificador positivo y una fila existente de Table 50013;
2. exige `Origen MES=TRUE` y tipo `Salida`;
3. devuelve `TRUE` si la fila ya esta `Registrado` o `Procesando`;
4. solo continua si la fila esta `Pendiente`; `Error` y cualquier otro estado
   se rechazan sin corregirlos;
5. localiza por tipo `Codeunit`, ID `50009` y parametro exacto
   `MES-SOLO-SALIDAS-V1` y exige una sola coincidencia;
6. valida descripcion exacta, recurrencia, todos los dias, ventana completa,
   maximo de intentos 1, ausencia de impresora y request page, usuario exacto
   `EBIR\NAVEBIR` y estado `Ready` o `In Process`;
7. si esta `In Process`, devuelve `TRUE` sin crear otra tarea;
8. si esta `Ready`, ejecuta una sola vez Codeunit 453 `Job Queue - Enqueue`
   sobre esa misma entrada.

El Codeunit 453 instalado cancela la tarea futura de esa entrada, fija un inicio
minimo de un segundo, crea una nueva tarea y conserva en ella el `User ID` de la
entrada. La materializacion debe comparar su baseline para demostrar este
contrato, pero no lo modifica.

El Codeunit 82000 conserva su endpoint ya autorizado
`WS_CPP_ControlPlanta`; no se publica un servicio adicional ni se amplian los
permisos de ejecucion del servicio MES. La funcion no ejecuta Report 50056 en la sesion SOAP, no cambia una salida a
`Procesando`, no registra diarios y no recibe nombre de entrada ni objeto desde
el cliente.

## 3. Contrato MES

El adaptador llama `TriggerMesEntryNow(SalidaId)` solo despues de:

- observar una unica salida posterior a su baseline;
- comprobar orden, producto, cantidad y tipo exactos;
- observar estado `Pendiente`;
- cerrar y verificar el bulto NAV.

Tras el disparo observa por OData durante un maximo nominal de 5,5 segundos. La
confirmacion MES y la impresion siguen dependiendo exclusivamente de observar
`Registrado`. Una respuesta SOAP, `Procesando` o un timeout nunca confirman la
salida. Ante incertidumbre se conserva el identificador externo y la cola de un
minuto reconcilia sin repetir `RegistrarSalidaFabricacion`.

La configuracion `NavisionOutput:ImmediateRegistrationEnabled` nace en `false`.

## 4. Concurrencia e idempotencia

- la salida exacta se valida antes de tocar la programacion;
- solo existe una entrada y una tarea MES autorizada;
- una carrera con la tarea ya iniciada devuelve sin reprogramar;
- la reclamacion atomica de Table 50013 decide el unico procesador;
- ninguna respuesta incierta permite reenviar la salida;
- las demas entradas Job Queue no se consultan ni se modifican.
