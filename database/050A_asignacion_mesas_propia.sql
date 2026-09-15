/*
Paquete 050A - Seleccion propia de mesas por el jefe de linea.
Base exclusiva: EBIR_MES_TEST.

Crea cfg.asignar_mesas_propias: contrato transaccional que permite a un jefe
de linea vigente (rol SUPERVISOR) declarar el conjunto de lineas que quiere
ver en su propio panel, usando cfg.lineas_jefes (paquete 049A). Una linea con
jefe vigente distinto queda bloqueada: el procedimiento aborta sin tocar
ninguna fila si el conjunto solicitado incluye una linea que otro jefe ya
tiene vigente. Libera sin autorizacion ajena las lineas propias que el jefe
deja de querer ver, cerrando su vigencia sin borrar el historial.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'cfg.lineas_jefes', N'U') IS NULL
 OR OBJECT_ID(N'cfg.lineas', N'U') IS NULL
 OR OBJECT_ID(N'seg.empleados', N'U') IS NULL
 OR OBJECT_ID(N'seg.empleados_roles', N'U') IS NULL
    THROW 51176, 'El paquete 050A requiere el paquete 049A instalado.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
    THROW 51177, 'El principal mes_runtime no existe.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @asignar nvarchar(max) = N'
CREATE OR ALTER PROCEDURE cfg.asignar_mesas_propias
    @empleado_id bigint,
    @lineas_csv nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @empleado_id IS NULL OR @empleado_id <= 0
        THROW 57000, ''El jefe de linea es obligatorio.'', 1;
    IF NOT EXISTS
    (
        SELECT 1
        FROM seg.empleados e
        JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
        JOIN seg.roles r ON r.rol_id = er.rol_id
        WHERE e.empleado_id = @empleado_id
          AND e.activo_nav = 1 AND e.activo_mes = 1
          AND r.codigo = N''SUPERVISOR'' AND r.activo = 1
          AND er.desde_utc <= SYSUTCDATETIME()
          AND (er.hasta_utc IS NULL OR er.hasta_utc > SYSUTCDATETIME())
    )
        THROW 57001, ''El empleado no es un jefe de linea vigente.'', 1;

    DECLARE @lineas TABLE (linea_id bigint PRIMARY KEY);
    INSERT INTO @lineas (linea_id)
    SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS bigint)
    FROM STRING_SPLIT(COALESCE(@lineas_csv, N''''), N'','')
    WHERE LTRIM(RTRIM(value)) <> N'''';

    IF EXISTS (SELECT 1 FROM @lineas WHERE linea_id IS NULL)
        THROW 57002, ''La lista de lineas no es valida.'', 1;
    IF EXISTS
    (
        SELECT 1 FROM @lineas l
        WHERE NOT EXISTS
        (
            SELECT 1 FROM cfg.lineas cl
            WHERE cl.linea_id = l.linea_id AND cl.activa = 1
        )
    )
        THROW 57003, ''Una linea seleccionada no existe o no esta activa.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF EXISTS
        (
            SELECT 1
            FROM @lineas l
            JOIN cfg.lineas_jefes lj WITH (UPDLOCK, HOLDLOCK)
                ON lj.linea_id = l.linea_id AND lj.asignado_hasta_utc IS NULL
            WHERE lj.empleado_id <> @empleado_id
        )
            THROW 57004, ''Una linea seleccionada ya tiene un jefe vigente distinto.'', 1;

        UPDATE lj
        SET asignado_hasta_utc = SYSUTCDATETIME()
        FROM cfg.lineas_jefes lj
        WHERE lj.empleado_id = @empleado_id AND lj.asignado_hasta_utc IS NULL
          AND NOT EXISTS (SELECT 1 FROM @lineas l WHERE l.linea_id = lj.linea_id);

        INSERT INTO cfg.lineas_jefes (linea_id, empleado_id, asignado_por_empleado_id, motivo)
        SELECT l.linea_id, @empleado_id, @empleado_id, N''Seleccion propia''
        FROM @lineas l
        WHERE NOT EXISTS
        (
            SELECT 1 FROM cfg.lineas_jefes lj
            WHERE lj.linea_id = l.linea_id AND lj.asignado_hasta_utc IS NULL
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';
    EXEC sys.sp_executesql @asignar;

    GRANT EXECUTE ON OBJECT::cfg.asignar_mesas_propias TO mes_runtime;

    IF OBJECT_ID(N'cfg.asignar_mesas_propias', N'P') IS NULL
        THROW 51178, 'El paquete 050A no creo su contrato.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
