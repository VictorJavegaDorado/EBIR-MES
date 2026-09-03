# Especificacion de configuracion NAV-001C

## Precondiciones bloqueantes

1. Confirmar `NAVISION2 / EbirTest / EBIR` y usuario `EBIR\NAVEBIR`.
2. Confirmar que Codeunit 50009 y Table 472 coinciden con los exports actuales.
3. Verificar que existe una unica entrada con objeto Codeunit 50009 y parametro
   `MES-SOLO-SALIDAS-V1`.
4. Exigir descripcion exacta `MES - Registro autonomo salidas` y estado
   `En espera`.
5. Exigir cero tareas de sistema activas asociadas a esa entrada y cero errores
   pendientes.
6. Inventariar las demas entradas sin cambiar su estado ni su programacion.
7. Confirmar que el rango de fechas de registro de `EBIR\NAVEBIR` incluye el
   dia del canario. No ampliar ese rango de forma implicita.
8. Confirmar cero salidas MES pendientes antes de preparar la recurrencia.

Cualquier duplicado, divergencia o trabajo pendiente detiene la fase.

## Configuracion exacta

La entrada conserva:

- tipo de objeto: `Codeunit`;
- ID de objeto: `50009`;
- descripcion: `MES - Registro autonomo salidas`;
- cadena de parametros: `MES-SOLO-SALIDAS-V1`;
- maximo de intentos: `1`;
- impresora: vacia;
- opciones de informe: vacias;
- ejecutar en sesion de usuario: `No`.

La programacion se establece como:

- proyecto periodico: `Si`;
- lunes a domingo: `Si`;
- hora inicial: `00:00:00`;
- hora final: `23:59:59`;
- minutos entre ejecuciones: `1`;
- fecha/hora inicial mas temprana: el instante autorizado de activacion;
- fecha/hora de caducidad: vacia;
- estado durante la preparacion: `En espera`.

No se modifica Codeunit 50009, Report 50056, Table 472 ni ningun otro objeto.
No se usa SQL contra NAV. La transicion posterior a `Listo` se realiza desde el
cliente NAV con `EBIR\NAVEBIR`, nunca ejecutando el codeunit de forma
interactiva.

## Politica de fechas

La recurrencia es permanente, pero no concede permisos de fecha. Antes de cada
canario se valida que el rango permitido del usuario ejecutor incluye ese dia.
Antes de produccion debe existir una politica operativa para mantener dicho
rango; `NAV-001C` no lo amplia ni lo automatiza.

## Invariantes en ejecucion

- cada ciclo instancia Report 50056 con `SetSoloSalidasMES(TRUE)`;
- NAV nunca selecciona salidas heredadas en este modo;
- NAV no imprime las salidas MES;
- no se crea una segunda entrada MES;
- una ejecucion lenta no autoriza ejecucion interactiva ni otro procesador;
- las otras entradas Job Queue permanecen fuera del alcance.
