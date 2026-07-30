/*
Paquete 012F - Definicion comun de recursos efectivos por sesion.
Estado: preparado para revision estatica; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

/*
La funcion no abre transacciones ni adquiere bloqueos especiales. Los
procedimientos transaccionales que la consuman deben bloquear previamente
sesion, fichajes y paros con el orden global del paquete.

Una sustitucion no necesita un descuento adicional:
- el operario sustituido conserva su fichaje, pero tiene un paro abierto;
- el supervisor sustituto conserva un fichaje abierto sin paro;
- la formula excluye al primero e incluye al segundo una sola vez.
*/
CREATE OR ALTER FUNCTION prod.recursos_efectivos_sesion
(
    @sesion_linea_id bigint
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        recursos_activos =
            CONVERT
            (
                int,
                COUNT_BIG(*)
            )
    FROM prod.fichajes f
    WHERE f.sesion_linea_id = @sesion_linea_id
      AND f.salida_utc IS NULL
      AND NOT EXISTS
      (
          SELECT 1
          FROM prod.paros_operario po
          WHERE po.fichaje_id = f.fichaje_id
            AND po.fin_utc IS NULL
      )
);
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

/*
mes_runtime hereda SELECT sobre el esquema prod. Se deniega la invocacion
directa de esta funcion interna. Los procedimientos del mismo propietario
podran consumirla mediante la cadena de propiedad.
*/
IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NOT NULL
    DENY SELECT ON OBJECT::prod.recursos_efectivos_sesion TO mes_runtime;
GO
