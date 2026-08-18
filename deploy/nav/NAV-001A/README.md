# NAV-001A - Registro autonomo de salidas MES

Estado: `INSTALADO_COMPILADO_EBIRTEST_SIN_EJECUCION`.

Este paquete define el cambio minimo para que NAV `EbirTest` registre de forma
autonoma solo las salidas creadas por MES. Sus cinco objetos se instalaron y
compilaron exclusivamente en `EbirTest` el 17 de agosto de 2026. Este directorio
no contiene objetos NAV exportados, no es importable y no autoriza nuevas
modificaciones ni ejecuciones en NAV.

## Alcance

- marcar de forma explicita el origen MES al crear la salida de fabrica;
- conservar sin cambios el contrato existente de `OpenClosePallet`;
- publicar una operacion nueva `OpenClosePalletMES`;
- reclamar cada salida de forma atomica desde todos los puntos de entrada;
- reconciliar un movimiento ya contabilizado por el identificador de salida;
- ejecutar el Report 50056 en un modo `SoloSalidasMES` independiente;
- omitir `ImprimirAlRegistrar` exclusivamente para salidas MES;
- conservar detenida la entrada historica de Job Queue;
- preparar pruebas, canario y rollback sin contactar NAV.

## Objetos afectados

| Tipo | Id. | Nombre | Cambio preparado |
|---|---:|---|---|
| Tabla | 50013 | Salidas Fabricacion | Campo 700 `Origen MES` y reclamacion compartida |
| Pagina | 50036 | Salidas Fabrica | Campo observable y uso de la reclamacion compartida |
| Informe | 50056 | Registra salidas fabrica | Modo `SoloSalidasMES`, reclamacion y supresion de impresion MES |
| Codeunit | 60103 | Consumos Fabrica | Reconciliacion exacta antes de contabilizar |
| Codeunit | 82000 | WS Control Planta | `OpenClosePalletMES` y propagacion del origen |

El campo 700 estaba libre en la exportacion examinada y quedo materializado en
`EbirTest`. El backup versionado de los objetos previos y las evidencias de la
importacion permanecen protegidos fuera de Git.

## Baseline examinada

Los objetos protegidos permanecen fuera de Git. Solo se conservan sus hashes
SHA-256 para verificar que la implementacion futura parte de la misma baseline.

| Objeto | SHA-256 |
|---|---|
| Tabla 50013 | `EA8A15BEB92E0AFE77C7BF3F99A35DE765BB2EBD2961EFDDF41150C315CDE692` |
| Pagina 50036 | `B9B7F66E5B7F3C55F63D7C48F4C422FF94B69307782319812D7348F9BC2FBC9B` |
| Codeunit 60103 | `46C43DEC8BBBE519339C9D09118A62EC4B94FE37231D82F4CEBF69410283CA34` |
| Codeunit 82000 | `602A554617552F6C9542598FEE24335EA013B57A9EA5D91B82BB451C6A17F002` |
| Report 50056 | `9929C5C2F8766B530B2FC231DAC72035CE5F68EE5990C70625F936B2FD491676` |

## Contenido

- `CHANGE-SPECIFICATION.md`: contrato que debe implementar el desarrollador NAV;
- `TEST-MATRIX.md`: pruebas estaticas y funcionales exigidas;
- `PILOT-RUNBOOK.md`: preparacion, canario, observacion y rollback;
- `tests/nav/autonomous_mes_output/verify-NAV-001A-static.ps1`: validacion local sin conexiones externas.

## Exclusiones y barreras

- solo `EbirTest`; produccion queda prohibida;
- no se cambia ni activa ninguna Job Queue con este paquete;
- no se ejecutan codeunits, informes, SOAP, OData o SQL;
- no se instala ni inicia el Worker;
- no se imprime ni se consume ningun trabajo de impresion;
- no se copian objetos NAV, licencias, configuracion o credenciales al repositorio;
- el cambio del adaptador MES para usar `OpenClosePalletMES` pertenece a una
  release independiente; esta preparado en `main`, pero no queda activo por
  este estado documental.

## Estado instalado

`NAV-001A` esta instalado y compilado en `EbirTest`, pero no se ha ejecutado el
procesador autonomo ni se ha activado ninguna Job Queue. La prueba estatica solo
valida el paquete documental y sus barreras; no consulta ni ejecuta NAV.
