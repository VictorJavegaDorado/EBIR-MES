# Especificacion de cambio NAV-001B

Esta especificacion describe comportamiento y puntos de modificacion. No es
codigo C/AL importable. La materializacion futura debe partir de objetos
exportados de `EbirTest` y permanecer fuera de `C:\MES`, Git y `Z:\MES`.

## 1. Precondiciones bloqueantes

1. Exportar de `EbirTest` el Report 50056 y la Table 472 `Job Queue Entry`.
2. Confirmar en la Table 472 de NAV 2017 los nombres de campos, opciones y
   funciones usados por la implementacion; la documentacion moderna solo es
   una referencia orientativa.
3. Inventariar en Object Designer un ID de codeunit libre y licenciado.
4. Sustituir `OBJECT_ID_PENDING_INVENTORY` en todo el material protegido.
5. Inventariar las entradas que apunten al Report 50056 o al nuevo codeunit.
6. Abortar ante cualquier entrada MES previa, duplicada o ambigua.

No se usa SQL contra la base NAV para ninguna precondicion.

## 2. Report 50056 `Registra salidas fabrica`

Agregar una funcion publica:

`SetSoloSalidasMES(Value : Boolean)`

La funcion asigna exclusivamente la variable global existente
`SoloSalidasMES`. No ejecuta el informe, no modifica registros y no cambia el
valor predeterminado `FALSE` usado por la ruta historica.

El codeunit dedicado debe instanciar el Report 50056, llamar al setter con
`TRUE`, desactivar la request page en esa instancia y ejecutar despues el
informe. Queda prohibido duplicar la logica del informe o construir a mano el
XML de sus opciones.

## 3. Nuevo codeunit `MES Job Queue Admin`

El ID permanece `OBJECT_ID_PENDING_INVENTORY` hasta completar la precondicion.
El objeto debe usar `TableNo=472` para recibir la entrada cuando sea ejecutado
por Job Queue.

Constantes funcionales:

- descripcion: `MES - Registro autonomo salidas`;
- parametro: `MES-SOLO-SALIDAS-V1`;
- informe interno: 50056;
- maximo de intentos: 1;
- periodicidad inicial: desactivada.

### 3.1 Funcion SOAP `EnsureStoppedMesEntry`

La funcion publica administrativa no recibe parametros y devuelve uno de dos
resultados seguros: `CREATED_ON_HOLD` o `EXISTS_ON_HOLD`.

Algoritmo obligatorio:

1. bloquear la Table 472 antes de decidir;
2. buscar por tipo `Codeunit`, ID exacto del nuevo objeto y parametro
   `MES-SOLO-SALIDAS-V1`;
3. contar el conjunto completo antes de escribir;
4. con mas de una coincidencia, abortar sin cambios;
5. con una coincidencia, exigir todos los invariantes de la seccion 3.2;
6. si cualquier campo diverge, abortar sin corregirlo;
7. con cero coincidencias, comprobar tambien que no existe otra entrada para
   el mismo codeunit o descripcion; cualquier coincidencia parcial bloquea;
8. insertar una nueva entrada con GUID generado por NAV y todos los campos
   seguros de la seccion 3.2;
9. releerla y validar los invariantes antes de devolver `CREATED_ON_HOLD`.

La funcion no llama al Report 50056, no cambia el estado a `Listo`, no crea
tareas programadas y no ejecuta ningun objeto.

### 3.2 Invariantes de la entrada

- tipo de objeto: `Codeunit`;
- ID de objeto: ID inventariado del nuevo codeunit;
- descripcion exacta: `MES - Registro autonomo salidas`;
- cadena de parametros exacta: `MES-SOLO-SALIDAS-V1`;
- estado: `En espera`;
- proyecto periodico: `FALSE`;
- dias de ejecucion: todos `FALSE`;
- fecha/hora inicial, final y caducidad: vacias;
- maximo de intentos: 1;
- intentos realizados: 0;
- tarea de sistema: GUID vacio;
- programada: `FALSE`;
- ejecutar en sesion de usuario: `FALSE`;
- nombre de impresora: vacio;
- opciones de informe y XML: vacios, porque el objeto programado es el
  codeunit dedicado.

La insercion no debe invocar `SetStatus(Listo)`, `ScheduleTask`, `Restart` ni
`RunJobQueueEntryOnce`.

### 3.3 `OnRun` futuro

El `OnRun` no forma parte de la funcion administrativa. Cuando una fase futura
autorice iniciar la entrada, debe:

1. exigir que `Rec` sea exactamente la entrada del propio codeunit;
2. exigir el parametro `MES-SOLO-SALIDAS-V1` y la descripcion exacta;
3. rechazar ejecucion interactiva o sin registro Job Queue valido;
4. crear una instancia del Report 50056;
5. llamar `SetSoloSalidasMES(TRUE)`;
6. desactivar la request page para esa instancia;
7. ejecutar una sola vez esa instancia;
8. no imprimir ni iniciar un segundo procesador.

No existe funcion SOAP para invocar este `OnRun`, cambiar estados o programar
la entrada.

## 4. Publicacion futura

La publicacion se realizara mediante un registro Web Service independiente:

- tipo: `Codeunit`;
- ID: el ID inventariado;
- nombre de servicio: `WS_MES_JobQueueAdmin`;
- empresa: `EBIR` en la instancia `EbirTest`;
- inicialmente no publicado.

Antes de publicarlo se inspeccionara el WSDL y se exigira que la unica
operacion administrativa sea `EnsureStoppedMesEntry`. Nunca se publica la Page
672 ni una pagina generica sobre la Table 472.

## 5. Idempotencia y concurrencia

- dos llamadas simultaneas producen como maximo una entrada;
- una segunda llamada exacta devuelve `EXISTS_ON_HOLD`;
- un duplicado, estado distinto o configuracion parcial produce error y cero
  correcciones automaticas;
- una respuesta SOAP incierta obliga a consultar la entrada antes de repetir;
- nunca se identifica la entrada solo por descripcion;
- nunca se inicia una cola como efecto colateral de asegurarla.

## 6. Exclusiones

- no ejecutar Report 50056 ni el nuevo codeunit durante preparacion;
- no crear, modificar o borrar entradas historicas;
- no procesar salidas de fabrica;
- no escribir SQL NAV;
- no iniciar Worker;
- no imprimir;
- no contactar produccion.
