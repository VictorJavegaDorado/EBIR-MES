# Paquete 014 — cierre idempotente de palé

Estado: **instalado y validado el 30/07/2026**.

Base única autorizable: `EBIR_MES_TEST`.

## Alcance

El paquete añade `prod.cerrar_palet_idempotente` como contrato público para la
API. El procedimiento existente `prod.cerrar_palet`, instalado por el paquete
010, permanece inmutable y se utiliza internamente para el primer cierre.

El nuevo contrato:

- exige una correlación;
- toma un `sp_getapplock` transaccional exclusivo por correlación;
- devuelve el mismo `palet_id` al repetir exactamente una petición completada;
- rechaza una correlación perteneciente a otra operación con `55402`;
- rechaza parámetros distintos con `55403`;
- comprueba que el palé, la operación NAV local y la etiqueta existan;
- delega el primer cierre dentro de la misma transacción;
- sustituye para `mes_runtime` el permiso del contrato anterior por el nuevo;
- no llama a NAV ni a impresoras.

La instalación valida previamente los objetos requeridos y el rol
`mes_runtime`. La creación del procedimiento, el traslado de permisos y su
validación posterior se realizan en una única transacción; cualquier fallo
revierte el paquete completo.

## Errores nuevos

```text
55400  correlación obligatoria
55401  bloqueo de idempotencia no disponible
55402  correlación perteneciente a otra operación
55403  correlación reutilizada con parámetros diferentes
55404  cierre idempotente anterior o nuevo incompleto
```

Los rechazos productivos `51400–51409` del procedimiento delegado se conservan
sin modificación. La prueba SQL funcional verifica `51400` como caso
representativo y las pruebas backend comprueban la traducción segura de todo el
rango.

## Instalación realizada

El único archivo instalable es:

```text
014A_cerrar_palet_idempotente.sql
```

Se ejecutó con autorización específica el 30/07/2026. La instalación añadió un
procedimiento y trasladó el permiso `EXECUTE` de `mes_runtime` del contrato
anterior al nuevo; no cambió ninguna tabla ni contactó integraciones.

## Validación realizada

Las pruebas preparadas en `tests/database/pallet_close_idempotency` separan
prevuelo/fixtures (`00_PREVUELO_Y_FIXTURES_014.sql`), funcionales
(`01_FUNCIONALES_014.sql`), concurrencia en dos clientes independientes
(`05_CONCURRENCIA_A_014.sql` y `06_CONCURRENCIA_B_014.sql`), permisos
(`07_PERMISOS_014.sql`), limpieza (`99A_LIMPIEZA_014.sql`) e integridad
(`99B_DBCC_014.sql`). Cada fase recibió autorización explícita. Los funcionales
prueban `55402` con auditoría sintética de autor válido y `55403` sin filas
parciales; la concurrencia conserva una transacción exterior en el cliente A y
exige una espera observable en B antes de reunir los resultados mediante
barreras auditables. Todas las fases terminaron correctamente y los fixtures
fueron eliminados. Las evidencias completas están en
`tests/database/pallet_close_idempotency/RESULTADO_EJECUCION_2026-07-30.md`.
