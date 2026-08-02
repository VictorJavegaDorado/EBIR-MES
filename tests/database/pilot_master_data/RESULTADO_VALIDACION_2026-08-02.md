# Resultado de validación del paquete 019 — 02/08/2026

El paquete se validó en `EBIR_MES_TEST` sobre
`SQL.EBIR.LOCAL\NAVISION2017`, sin instalarlo y sin conservar fixtures.

## Controles ejecutados

- revisión estática de guardas, transacción y ausencia de valores físicos;
- carga parametrizada desde un JSON sintético fuera del repositorio;
- ejecución con identidad administrativa `EBIR\vjavega`;
- transacción exterior en aislamiento `Serializable`;
- inserción temporal de una línea, impresora, lector, asignaciones, dos
  operarios, un supervisor, tres asignaciones de rol y tres huellas RFID;
- validaciones internas y auditoría resumida;
- `ROLLBACK` exterior mediante `-ValidateOnly`;
- consulta posterior independiente de códigos `ZZ19-*`.

## Resultado

- modo: `VALIDATED_AND_ROLLED_BACK`;
- empleados validados: 3;
- credenciales validadas: 3;
- filas sintéticas restantes: 0;
- tareas programadas temporales restantes: 0;
- listeners temporales en 50731–50735: 0.

No se creó backup porque no hubo instalación. No se ejecutó `DBCC CHECKDB` en
esta fase de rollback. Ambas operaciones siguen siendo obligatorias y
separadas antes y después de una futura instalación autorizada.

La validación descubrió y corrigió dos incompatibilidades de PowerShell 5.1 en
el instalador: nombres canónicos del constructor de conexión y conversión
explícita de la huella a `Byte[]`. Ninguno de los intentos fallidos alcanzó una
inserción persistente.
