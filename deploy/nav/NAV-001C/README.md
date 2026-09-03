# NAV-001C - Entrada MES recurrente en EbirTest

Estado: `PREPARADO_NO_APLICADO`.

Este paquete convierte exclusivamente la entrada existente del Codeunit 50009
`MES Job Queue Admin` en una entrada recurrente de Job Queue. No modifica
objetos C/AL: los exports actuales confirman que el validador de ejecucion
mantiene el token, la descripcion y el bloqueo interactivo, pero no restringe
los campos de programacion.

## Alcance

- servidor: `NAVISION2`;
- instancia: `EbirTest`;
- empresa: `EBIR`;
- usuario ejecutor: `EBIR\NAVEBIR`;
- objeto: Codeunit 50009 `MES Job Queue Admin`;
- descripcion exacta: `MES - Registro autonomo salidas`;
- parametro exacto: `MES-SOLO-SALIDAS-V1`.

Produccion, SQL NAV, Page 672, importacion, compilacion y ejecucion interactiva
quedan fuera de alcance. La entrada se prepara primero en `En espera`; pasarla
a `Listo` y observar el primer ciclo requieren autorizacion separada.

## Contenido

- `CONFIGURATION-SPECIFICATION.md`: valores exactos e invariantes;
- `TEST-MATRIX.md`: comprobaciones antes, durante y despues del canario;
- `PILOT-RUNBOOK.md`: preparacion, activacion y rollback manuales.

Los objetos exportados y cualquier evidencia permanecen fuera de Git, bajo
`C:\ProgramData\EBIR\MES\protected\nav\NAV-001C`.
