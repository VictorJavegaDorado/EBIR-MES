/*
Paquete 024A - Tiempo productivo individual acumulado por sesion.
Base exclusiva: EBIR_MES_TEST.

Corrige la vista de mesa para que una salida y posterior reincorporacion del
mismo empleado no reinicie su contador individual. Los paros de cada fichaje
se descuentan del acumulado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'prod.obtener_estado_mesa') IS NULL
 OR OBJECT_ID(N'prod.sesiones_linea') IS NULL
 OR OBJECT_ID(N'prod.fichajes') IS NULL
 OR OBJECT_ID(N'prod.paros_operario') IS NULL
 OR OBJECT_ID(N'prod.tramos_capacidad') IS NULL
 OR OBJECT_ID(N'prod.formatos_palet_orden') IS NULL
 OR OBJECT_ID(N'prod.recursos_efectivos_sesion') IS NULL
    THROW 51032, 'El paquete 024A requiere los paquetes de sesiones, paros y mesa.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
    THROW 51033, 'El principal mes_runtime no existe.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @definicion nvarchar(max) = N'
CREATE OR ALTER PROCEDURE prod.obtener_estado_mesa
    @orden_id bigint,
    @linea_id bigint
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @ahora_utc datetime2(3) = SYSUTCDATETIME(),
        @sesion_linea_id bigint;

    SELECT @sesion_linea_id = s.sesion_linea_id
    FROM prod.sesiones_linea s
    WHERE s.orden_id = @orden_id
      AND s.linea_id = @linea_id
      AND s.finalizada_utc IS NULL;

    IF @sesion_linea_id IS NULL
        RETURN;

    SELECT
        s.sesion_linea_id,
        s.orden_id,
        s.linea_id,
        s.estado,
        s.iniciada_utc,
        @ahora_utc AS servidor_utc,
        CONVERT(bigint, ISNULL((
            SELECT SUM(
                CASE WHEN tc.fin_utc IS NULL
                     THEN DATEDIFF_BIG(SECOND, tc.inicio_utc, @ahora_utc)
                     ELSE CONVERT(bigint, tc.segundos_productivos) END)
            FROM prod.tramos_capacidad tc
            WHERE tc.sesion_linea_id = s.sesion_linea_id
              AND tc.recursos_activos > 0
        ), 0)) AS segundos_productivos,
        CONVERT(int, ISNULL(re.recursos_activos, 0)) AS recursos_activos,
        CONVERT(decimal(18,4), ISNULL((
            SELECT TOP (1) tc.capacidad_teorica_hora
            FROM prod.tramos_capacidad tc
            WHERE tc.sesion_linea_id = s.sesion_linea_id
              AND tc.fin_utc IS NULL
            ORDER BY tc.tramo_capacidad_id DESC
        ), 0)) AS capacidad_teorica_hora,
        fp.codigo_formato,
        fp.unidades_por_palet
    FROM prod.sesiones_linea s
    JOIN prod.formatos_palet_orden fp
      ON fp.formato_palet_orden_id = s.formato_palet_orden_id
     AND fp.orden_id = s.orden_id
    OUTER APPLY prod.recursos_efectivos_sesion(s.sesion_linea_id) re
    WHERE s.sesion_linea_id = @sesion_linea_id;

    SELECT
        e.empleado_id,
        e.codigo_nav,
        e.nombre_completo,
        f.entrada_utc,
        CONVERT(bigint, ISNULL(acumulado.segundos_productivos, 0))
            AS segundos_productivos,
        CASE WHEN EXISTS
             (
                 SELECT 1
                 FROM prod.paros_operario po
                 WHERE po.fichaje_id = f.fichaje_id
                   AND po.fin_utc IS NULL
             ) THEN N''EN_PAUSA'' ELSE N''PRODUCIENDO'' END AS estado
    FROM prod.fichajes f
    JOIN seg.empleados e ON e.empleado_id = f.empleado_id
    OUTER APPLY
    (
        SELECT SUM(
            DATEDIFF_BIG(
                SECOND,
                fh.entrada_utc,
                COALESCE(fh.salida_utc, @ahora_utc))
            - ISNULL(pausas.segundos, 0)) AS segundos_productivos
        FROM prod.fichajes fh
        OUTER APPLY
        (
            SELECT SUM(DATEDIFF_BIG(
                SECOND,
                po.inicio_utc,
                COALESCE(po.fin_utc, @ahora_utc))) AS segundos
            FROM prod.paros_operario po
            WHERE po.fichaje_id = fh.fichaje_id
        ) pausas
        WHERE fh.sesion_linea_id = f.sesion_linea_id
          AND fh.empleado_id = f.empleado_id
    ) acumulado
    WHERE f.sesion_linea_id = @sesion_linea_id
      AND f.salida_utc IS NULL
    ORDER BY f.entrada_utc, f.fichaje_id;
END;';

    EXEC sys.sp_executesql @definicion;
    GRANT EXECUTE ON OBJECT::prod.obtener_estado_mesa TO mes_runtime;

    IF OBJECT_DEFINITION(OBJECT_ID(N'prod.obtener_estado_mesa'))
       NOT LIKE N'%fh.empleado_id = f.empleado_id%'
        THROW 51034, 'La vista de mesa no contiene el acumulado individual.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.database_permissions
        WHERE class = 1
          AND major_id = OBJECT_ID(N'prod.obtener_estado_mesa')
          AND minor_id = 0
          AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
          AND permission_name = N'EXECUTE'
          AND state IN (N'G', N'W')
    )
        THROW 51035, 'mes_runtime no puede ejecutar la vista de mesa.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
