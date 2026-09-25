# Seguimiento de solicitudes de material

`verify-052A-static.ps1` valida sin conectarse a SQL que el paquete 052A:

- solo admite `EBIR_MES_TEST`;
- crea un procedimiento de lectura limitado a diez solicitudes por sesion;
- encapsula el acceso a auditoria mediante `EXECUTE AS OWNER`;
- concede al runtime unicamente `EXECUTE`, nunca `SELECT` sobre auditoria;
- conserva transaccion y rollback de instalacion.

La comprobacion es estatica y no crea fixtures ni modifica datos.
