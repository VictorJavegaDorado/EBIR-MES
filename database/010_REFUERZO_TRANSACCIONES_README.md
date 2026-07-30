# Paquete 010 — refuerzo transaccional

Estado: **aplicado y validado el 28/07/2026 con autorización expresa**.

Archivo:

- `010_refuerzo_transacciones_procedimientos.sql`

Base exclusiva: `EBIR_MES_TEST`.

## Motivo

Durante la prueba de sobre-reserva, `prod.reservar_palet` devolvió correctamente
el error funcional `51204`, pero dejó la transacción de la conexión sin
posibilidad de confirmación. La siguiente escritura falló hasta cerrar la
conexión, momento en el que SQL Server revirtió la transacción pendiente.

## Alcance

Se redefinen únicamente los cinco procedimientos que abren transacciones:

1. `nav.confirmar_salida_palet`.
2. `imp.confirmar_trabajo_impresion`.
3. `prod.reservar_palet`.
4. `prod.cancelar_reserva_palet`.
5. `prod.cerrar_palet`.

No se modifica `aud.registrar_evento`, porque no abre una transacción propia.

No se modifican:

- tablas, columnas, restricciones o índices;
- datos existentes o fixtures;
- permisos o miembros de roles;
- contratos, parámetros o códigos de error;
- lógica funcional, NAV o impresión;
- paquetes `001–009`.

## Cambio aplicado a cada procedimiento

La transacción y su lógica existente quedan dentro de:

```sql
BEGIN TRY
    BEGIN TRANSACTION;

    -- lógica existente sin cambios

    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
```

Así, cualquier error posterior a `BEGIN TRANSACTION` revierte antes de
propagarse, conservando el número y mensaje originales.

Si en el futuro uno de estos procedimientos se invoca dentro de una transacción
exterior y se produce un error con la transacción no confirmable, el `ROLLBACK`
revierte la transacción completa. En la operativa actual los cinco
procedimientos se invocan como unidades transaccionales autónomas.

## Validación propuesta tras una futura autorización

1. Aplicar `010` exclusivamente en `EBIR_MES_TEST`.
2. Comprobar que siguen existiendo 37 tablas y 6 procedimientos críticos.
3. Repetir el caso 2 sobre el estado actual:
   - esperar `51204`;
   - comprobar inmediatamente `@@TRANCOUNT = 0`;
   - comprobar `XACT_STATE() = 0`;
   - confirmar que la reserva válida sigue activa.
4. Continuar los casos 3–8.
5. Ejecutar concurrencia, auditoría y permisos.
6. Ejecutar limpieza y `DBCC CHECKDB` con autorización separada.

## Estado actual de datos de prueba

Los fixtures permanecen cargados. Para `ZZT-FL-TX-01` solo está confirmada la
reserva válida del caso 1: 0 buenas, 20 reservadas, una reserva activa y ningún
palé, operación NAV o etiqueta.

## Resultado de aplicación

- Cinco procedimientos objetivo aplicados.
- Cinco procedimientos contienen `BEGIN CATCH` y `ROLLBACK TRANSACTION`.
- Se mantienen 37 tablas y 6 procedimientos críticos.
- Repetición controlada del error `51204`:
  `@@TRANCOUNT = 0` y `XACT_STATE() = 0`.
