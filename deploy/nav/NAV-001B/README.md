# NAV-001B - Administracion segura de la Job Queue MES

Estado: `PREPARADO_NO_MATERIALIZADO`.

Este paquete define una operacion administrativa minima para crear o validar,
de forma idempotente, una unica entrada Job Queue detenida que procese las
salidas MES mediante el Report 50056. No contiene objetos NAV exportados, no es
importable y no autoriza modificar, compilar, publicar ni ejecutar `EbirTest`.

## Decision

- no publicar la Page 672 `Job Queue Entries`;
- no escribir las tablas NAV mediante SQL;
- no construir manualmente el XML privado de la request page;
- incorporar al Report 50056 un setter publico `SetSoloSalidasMES`;
- crear un codeunit dedicado que ejecute el informe con request page oculta y
  `SoloSalidasMES=TRUE`;
- publicar en una fase posterior solo la funcion administrativa que asegura
  la entrada detenida;
- identificar la entrada con el parametro fijo `MES-SOLO-SALIDAS-V1`;
- rechazar duplicados o configuraciones divergentes en vez de corregirlas.

## Objetos previstos

| Tipo | Id. | Nombre | Cambio preparado |
|---|---:|---|---|
| Report | 50056 | Registra salidas fabrica | Setter explicito del modo MES, sin cambiar el valor por defecto |
| Codeunit | `OBJECT_ID_PENDING_INVENTORY` | MES Job Queue Admin | Creacion/validacion detenida y ejecucion futura aislada |

El identificador del nuevo codeunit no se asignara hasta inventariar en Object
Designer un ID libre y cubierto por la licencia de `EbirTest`. No se consultara
la base NAV mediante SQL para resolverlo.

## Contenido

- `CHANGE-SPECIFICATION.md`: contrato C/AL y guardas idempotentes;
- `TEST-MATRIX.md`: pruebas estaticas, de compilacion y funcionales;
- `PILOT-RUNBOOK.md`: materializacion, publicacion, creacion y rollback;
- `tests/nav/job_queue_mes_admin/verify-NAV-001B-static.ps1`: validacion local
  sin conexiones externas.

## Barreras

- exclusivamente `EbirTest`; produccion queda prohibida;
- la entrada nace y permanece `En espera`;
- no se llama a `SetStatus(Listo)`, `ScheduleTask` ni `RunJobQueueEntryOnce`;
- la funcion SOAP administrativa nunca ejecuta el Report 50056;
- no se inicia ninguna Job Queue ni Worker;
- no se imprime;
- no se publica la Page 672;
- no se guardan credenciales, configuracion operativa ni objetos NAV en Git.

## Criterio de preparado

`NAV-001B` esta preparado cuando su prueba estatica pasa, la documentacion
funcional enlaza el paquete y el repositorio queda limpio tras el commit. Esto
no equivale a objeto materializado, importado, compilado, publicado o ejecutado.
