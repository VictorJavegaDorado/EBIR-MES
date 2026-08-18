# ADR 0004: administracion por comando de la Job Queue MES

## Estado

Aceptada como diseno; paquete `NAV-001B` preparado, no materializado.

## Contexto

`EbirTest` no publica una pagina SOAP/OData de Job Queue. Publicar la Page 672
expondria una superficie administrativa generica. Insertar la Table 472 desde
SQL evitaria las validaciones NAV y queda prohibido.

El Report 50056 ya contiene el modo `SoloSalidasMES`, pero una entrada directa
de tipo Report depende del XML de su request page. Ese XML debe obtenerse de la
plataforma; construirlo a mano acoplaria la automatizacion a un formato privado
y dificil de validar sin ejecutar la request page.

## Decision

Se prepara un codeunit dedicado con dos responsabilidades separadas:

1. una funcion SOAP idempotente que solo crea o valida una entrada detenida;
2. un `OnRun` que, en una fase futura, instancia el Report 50056 y fuerza
   `SoloSalidasMES=TRUE` mediante un setter explicito.

La entrada programa el codeunit, no el Report directamente. Se identifica por
ID de objeto y el token `MES-SOLO-SALIDAS-V1`. Una divergencia bloquea; nunca se
repara ni se inicia automaticamente.

El ID del codeunit no se anticipa: debe inventariarse en Object Designer y
validarse contra la licencia antes de materializar.

## Consecuencias

- la Page 672 permanece sin publicar;
- no se depende del XML de request page;
- la creacion administrativa no puede procesar salidas;
- el contrato historico del Report 50056 conserva `FALSE` por defecto;
- materializacion, importacion, publicacion, creacion y ejecucion son fases
  independientes;
- se agrega un objeto NAV cuyo ID y licencia deben verificarse.

## Referencias

- Microsoft documenta que la Table 472 conserva parametros de report y ofrece
  operaciones de estado; la exportacion de NAV 2017 sigue siendo autoritativa:
  <https://learn.microsoft.com/en-us/dynamics365/business-central/application/base-application/table/system.threading.job-queue-entry>
- Microsoft documenta que `RunRequestPage` devuelve el XML generado por la
  plataforma para ejecuciones posteriores:
  <https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/methods-auto/report/report-runrequestpage-method>
