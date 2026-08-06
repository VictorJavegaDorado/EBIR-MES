/*
Paquete 027A - Contexto autoritativo para salida de palet por codeunit NAV.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV ni reencola operaciones. Amplia el resultado reservado con el
lote, el codigo NAV del operario que cerro el palet y el codigo de linea MES.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'nav.reservar_siguiente_salida_palet', N'P') IS NULL
 OR OBJECT_ID(N'nav.operaciones', N'U') IS NULL
 OR OBJECT_ID(N'prod.palets', N'U') IS NULL
 OR OBJECT_ID(N'prod.ordenes', N'U') IS NULL
 OR OBJECT_ID(N'prod.sesiones_linea', N'U') IS NULL
 OR OBJECT_ID(N'cfg.lineas', N'U') IS NULL
 OR OBJECT_ID(N'seg.empleados', N'U') IS NULL
    THROW 51046, 'El paquete 027A requiere la cola 026A y los maestros operativos.', 1;
GO

IF COL_LENGTH(N'prod.ordenes', N'lote') IS NULL
 OR COL_LENGTH(N'prod.palets', N'sesion_linea_id') IS NULL
 OR COL_LENGTH(N'prod.palets', N'cerrado_por_empleado_id') IS NULL
 OR COL_LENGTH(N'cfg.lineas', N'codigo') IS NULL
 OR COL_LENGTH(N'seg.empleados', N'codigo_nav') IS NULL
    THROW 51047, 'El modelo no contiene todo el contexto requerido por 027A.', 1;
GO

IF EXISTS
(
    SELECT 1
    FROM nav.operaciones
    WHERE tipo = N'SALIDA_PALET'
      AND estado = N'PROCESANDO'
)
    THROW 51048, 'Existen salidas de palet en proceso; no se puede instalar 027A.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE nav.reservar_siguiente_salida_palet
    @worker_id nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @worker_id = NULLIF(LTRIM(RTRIM(@worker_id)), N'''');
    IF @worker_id IS NULL
        THROW 56000, ''La identidad del worker es obligatoria.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @ahora datetime2(3) = SYSUTCDATETIME();

        INSERT nav.intentos_operacion
        (
            operacion_nav_id, numero_intento, inicio_utc, fin_utc,
            resultado, error_normalizado, respuesta
        )
        SELECT
            operacion_nav_id, CONVERT(smallint, numero_intentos + 1),
            reservado_utc, @ahora, N''RESULTADO_DESCONOCIDO'',
            N''RESERVA_CADUCADA'',
            N''{""origen"":""MES_WORKER"",""motivo"":""reserva_caducada""}''
        FROM nav.operaciones WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE tipo = N''SALIDA_PALET''
          AND estado = N''PROCESANDO''
          AND reservado_utc < DATEADD(MINUTE, -5, @ahora);

        UPDATE nav.operaciones
        SET estado = N''RESULTADO_DESCONOCIDO'',
            numero_intentos = numero_intentos + 1,
            proximo_intento_utc = NULL,
            procesada_utc = @ahora,
            reservado_utc = NULL,
            reservado_por = NULL
        WHERE tipo = N''SALIDA_PALET''
          AND estado = N''PROCESANDO''
          AND reservado_utc < DATEADD(MINUTE, -5, @ahora);

        DECLARE @operacion_id bigint;
        SELECT TOP (1) @operacion_id = operacion_nav_id
        FROM nav.operaciones WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE tipo = N''SALIDA_PALET''
          AND estado IN (N''PENDIENTE'', N''ERROR_REINTENTABLE'')
          AND numero_intentos < 3
          AND (proximo_intento_utc IS NULL OR proximo_intento_utc <= @ahora)
        ORDER BY creada_utc, operacion_nav_id;

        IF @operacion_id IS NOT NULL
        BEGIN
            UPDATE nav.operaciones
            SET estado = N''PROCESANDO'',
                reservado_utc = @ahora,
                reservado_por = @worker_id,
                procesada_utc = NULL,
                proximo_intento_utc = NULL
            WHERE operacion_nav_id = @operacion_id;

            SELECT
                n.operacion_nav_id, n.operacion_uid, n.clave_idempotencia,
                o.numero_orden, o.producto_codigo, o.lote,
                e.codigo_nav, l.codigo, p.cantidad_buena,
                p.cerrado_utc, n.numero_intentos + 1 AS numero_intento
            FROM nav.operaciones n
            JOIN prod.palets p
              ON p.palet_id = n.palet_id
             AND p.orden_id = n.orden_id
            JOIN prod.ordenes o ON o.orden_id = n.orden_id
            JOIN prod.sesiones_linea s
              ON s.sesion_linea_id = p.sesion_linea_id
             AND s.orden_id = p.orden_id
            JOIN cfg.lineas l ON l.linea_id = s.linea_id
            JOIN seg.empleados e
              ON e.empleado_id = p.cerrado_por_empleado_id
            WHERE n.operacion_nav_id = @operacion_id;
        END;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    GRANT EXECUTE ON OBJECT::nav.reservar_siguiente_salida_palet TO mes_runtime;

    DECLARE @definition nvarchar(max) =
        OBJECT_DEFINITION(OBJECT_ID(N'nav.reservar_siguiente_salida_palet'));
    IF @definition NOT LIKE N'%o.lote%'
     OR @definition NOT LIKE N'%e.codigo_nav%'
     OR @definition NOT LIKE N'%l.codigo%'
     OR @definition NOT LIKE N'%p.cerrado_por_empleado_id%'
        THROW 51049, 'El contrato 027A no quedo publicado completamente.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.database_permissions dp
        JOIN sys.database_principals pr
          ON pr.principal_id = dp.grantee_principal_id
        WHERE dp.major_id = OBJECT_ID(N'nav.reservar_siguiente_salida_palet')
          AND dp.permission_name = N'EXECUTE'
          AND dp.state IN (N'G', N'W')
          AND pr.name = N'mes_runtime'
    )
        THROW 51050, 'Falta el permiso runtime del contrato 027A.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
