# Paquete 022: formato de palet POK

`022A_formato_palet_pok.sql` incorpora al snapshot de entrada el formato POK
leido en NAV y lo promueve a `prod.formatos_palet_orden` de forma atomica con
la orden productiva.

- Solo admite exactamente un POK por producto y unidades enteras positivas.
- Verifica producto, codigo y cantidad contra el JSON incluido en el hash.
- Conserva el JSON OData minimo como evidencia, sin credenciales.
- Una orden ya promovida con un hash anterior pasa por la regla de revision
  existente; el paquete no sobrescribe silenciosamente el formato productivo.
- El script solo puede ejecutarse en `EBIR_MES_TEST` y requiere autorizacion
  expresa de escritura SQL.

## Estado de instalacion

Instalado y validado el 05/08/2026 exclusivamente en `EBIR_MES_TEST`:

- ensayo completo dentro de una transaccion exterior y rollback verificado;
- backup `COPY_ONLY` con checksum y `RESTORE VERIFYONLY` correcto:
  `D:\BBDD\EBIR_MES_TEST_pre022_20260805_104355_360e0ac3.bak`;
- instalacion definitiva con tabla, procedimientos y permisos comprobados;
- bandeja POK inicial vacia;
- `DBCC CHECKDB` sin errores.

La instalacion no activa ninguna release. La API que consume el nuevo
procedimiento debe desplegarse en una fase posterior autorizada.

Validacion estatica sin ejecutar SQL:

```powershell
pwsh tests/database/production_order_pallet_format/verify-022-static.ps1
```
