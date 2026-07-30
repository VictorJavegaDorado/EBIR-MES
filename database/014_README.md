# Paquete 014 — cierre idempotente de palé

Estado: **preparado para revisión estática; no ejecutado**.

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

## Errores nuevos

```text
55400  correlación obligatoria
55401  bloqueo de idempotencia no disponible
55402  correlación perteneciente a otra operación
55403  correlación reutilizada con parámetros diferentes
55404  cierre idempotente anterior o nuevo incompleto
```

Los rechazos productivos `51400–51409` del procedimiento delegado se conservan
sin modificación.

## Instalación futura

El único archivo instalable es:

```text
014A_cerrar_palet_idempotente.sql
```

No debe ejecutarse sin autorización específica. Tras una instalación
autorizada se esperaría un procedimiento adicional y el permiso `EXECUTE` de
`mes_runtime` trasladado del contrato anterior al nuevo; no cambia ninguna
tabla, fila o integración.

## Validación futura

Las pruebas preparadas en
`tests/database/pallet_close_idempotency` separan prevuelo, casos funcionales,
concurrencia, permisos y limpieza. Cada fase requerirá autorización propia.
