/*
Paquete 028A - Reconciliacion diferida y continuidad tras cerrar un palet.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV. Permite que el Worker reserve en modo de solo reconciliacion
una SALIDA_PALET con identificador externo y resultado desconocido. El cierre
de un palet no final conserva el estado operativo de la linea, pero impide
cerrar el siguiente hasta confirmar la salida anterior.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'nav.reservar_siguiente_salida_palet', N'P') IS NULL
 OR OBJECT_ID(N'nav.fallar_salida_palet', N'P') IS NULL
 OR OBJECT_ID(N'prod.cerrar_palet', N'P') IS NULL
 OR OBJECT_ID(N'nav.operaciones', N'U') IS NULL
 OR OBJECT_ID(N'nav.intentos_operacion', N'U') IS NULL
 OR OBJECT_ID(N'prod.palets', N'U') IS NULL
 OR OBJECT_ID(N'prod.sesiones_linea', N'U') IS NULL
 OR OBJECT_ID(N'prod.estados_linea', N'U') IS NULL
    THROW 51051, 'El paquete 028A requiere las colas y contratos de palet instalados.', 1;
GO

IF EXISTS
(
    SELECT 1 FROM nav.operaciones
    WHERE tipo = N'SALIDA_PALET' AND estado = N'PROCESANDO'
)
    THROW 51052, 'Existen salidas de palet en proceso; no se puede instalar 028A.', 1;
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
    SET @worker_id = NULLIF(LTRIM(RTRIM(@worker_id)), N'''' );
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
            N''{"origen":"MES_WORKER","motivo":"reserva_caducada"}''
        FROM nav.operaciones WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE tipo = N''SALIDA_PALET''
          AND estado = N''PROCESANDO''
          AND reservado_utc < DATEADD(MINUTE, -5, @ahora);

        UPDATE nav.operaciones
        SET estado = N''RESULTADO_DESCONOCIDO'',
            numero_intentos = numero_intentos + 1,
            proximo_intento_utc = @ahora,
            procesada_utc = NULL,
            reservado_utc = NULL,
            reservado_por = NULL
        WHERE tipo = N''SALIDA_PALET''
          AND estado = N''PROCESANDO''
          AND reservado_utc < DATEADD(MINUTE, -5, @ahora);

        DECLARE @operacion_id bigint;
        SELECT TOP (1) @operacion_id = operacion_nav_id
        FROM nav.operaciones WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE tipo = N''SALIDA_PALET''
          AND
          (
              (
                  estado IN (N''PENDIENTE'', N''ERROR_REINTENTABLE'')
                  AND numero_intentos < 3
                  AND (proximo_intento_utc IS NULL OR proximo_intento_utc <= @ahora)
              )
              OR
              (
                  estado = N''RESULTADO_DESCONOCIDO''
                  AND NULLIF(LTRIM(RTRIM(identificador_externo)), N'''') IS NOT NULL
                  AND (proximo_intento_utc IS NULL OR proximo_intento_utc <= @ahora)
              )
          )
        ORDER BY
            CASE WHEN estado = N''RESULTADO_DESCONOCIDO'' THEN 0 ELSE 1 END,
            creada_utc,
            operacion_nav_id;

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
                p.cerrado_utc, n.numero_intentos + 1 AS numero_intento,
                n.identificador_externo
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

    DECLARE @fallo nvarchar(max) =
        OBJECT_DEFINITION(OBJECT_ID(N'nav.fallar_salida_palet'));
    SET @fallo = REPLACE(@fallo, NCHAR(13) + NCHAR(10), NCHAR(10));
    IF CHARINDEX(N'CREATE PROCEDURE', @fallo) > 0
        SET @fallo = STUFF(
            @fallo,
            CHARINDEX(N'CREATE PROCEDURE', @fallo),
            LEN(N'CREATE PROCEDURE'),
            N'ALTER PROCEDURE');

    DECLARE @fallo_plan_anterior nvarchar(max) =
        N'            proximo_intento_utc = CASE' + CHAR(10) +
        N'                WHEN @resultado_final = N''ERROR_REINTENTABLE''' + CHAR(10) +
        N'                    THEN DATEADD(SECOND, 5 * @numero_intento, SYSUTCDATETIME())' + CHAR(10) +
        N'                ELSE NULL END,' + CHAR(10) +
        N'            procesada_utc = CASE' + CHAR(10) +
        N'                WHEN @resultado_final = N''ERROR_REINTENTABLE'' THEN NULL' + CHAR(10) +
        N'                ELSE SYSUTCDATETIME() END,';
    DECLARE @fallo_plan_nuevo nvarchar(max) =
        N'            proximo_intento_utc = CASE' + CHAR(10) +
        N'                WHEN @resultado_final = N''ERROR_REINTENTABLE''' + CHAR(10) +
        N'                    THEN DATEADD(SECOND, 5 * @numero_intento, SYSUTCDATETIME())' + CHAR(10) +
        N'                WHEN @resultado_final = N''RESULTADO_DESCONOCIDO''' + CHAR(10) +
        N'                 AND COALESCE(@identificador_externo, identificador_externo) IS NOT NULL' + CHAR(10) +
        N'                    THEN DATEADD(SECOND, 10, SYSUTCDATETIME())' + CHAR(10) +
        N'                ELSE NULL END,' + CHAR(10) +
        N'            procesada_utc = CASE' + CHAR(10) +
        N'                WHEN @resultado_final = N''ERROR_REINTENTABLE'' THEN NULL' + CHAR(10) +
        N'                WHEN @resultado_final = N''RESULTADO_DESCONOCIDO''' + CHAR(10) +
        N'                 AND COALESCE(@identificador_externo, identificador_externo) IS NOT NULL THEN NULL' + CHAR(10) +
        N'                ELSE SYSUTCDATETIME() END,';
    IF CHARINDEX(@fallo_plan_anterior, @fallo) = 0
        THROW 51053, 'El contrato de fallo no coincide con la base esperada.', 1;
    SET @fallo = REPLACE(@fallo, @fallo_plan_anterior, @fallo_plan_nuevo);
    EXEC sys.sp_executesql @fallo;

    DECLARE @cierre nvarchar(max) =
        OBJECT_DEFINITION(OBJECT_ID(N'prod.cerrar_palet'));
    SET @cierre = REPLACE(@cierre, NCHAR(13) + NCHAR(10), NCHAR(10));
    IF CHARINDEX(N'CREATE PROCEDURE', @cierre) > 0
        SET @cierre = STUFF(
            @cierre,
            CHARINDEX(N'CREATE PROCEDURE', @cierre),
            LEN(N'CREATE PROCEDURE'),
            N'ALTER PROCEDURE');
    IF CHARINDEX(N'CREATE   PROCEDURE', @cierre) > 0
        SET @cierre = STUFF(
            @cierre,
            CHARINDEX(N'CREATE   PROCEDURE', @cierre),
            LEN(N'CREATE   PROCEDURE'),
            N'ALTER PROCEDURE');

    DECLARE @cierre_cantidad nvarchar(max) =
        N'    IF @cantidad_buena > @cantidad_reservada';
    DECLARE @cierre_salida_previa nvarchar(max) =
        N'    IF EXISTS' + CHAR(10) +
        N'    (' + CHAR(10) +
        N'        SELECT 1' + CHAR(10) +
        N'        FROM prod.palets p_anterior WITH (UPDLOCK, HOLDLOCK)' + CHAR(10) +
        N'        JOIN nav.operaciones n_anterior WITH (UPDLOCK, HOLDLOCK)' + CHAR(10) +
        N'          ON n_anterior.palet_id = p_anterior.palet_id' + CHAR(10) +
        N'         AND n_anterior.orden_id = p_anterior.orden_id' + CHAR(10) +
        N'         AND n_anterior.tipo = N''SALIDA_PALET''' + CHAR(10) +
        N'        WHERE p_anterior.sesion_linea_id = @sesion_linea_id' + CHAR(10) +
        N'          AND n_anterior.estado <> N''CONFIRMADA''' + CHAR(10) +
        N'    )' + CHAR(10) +
        N'        THROW 51412, ''La salida del palet anterior no esta confirmada en NAV.'', 1;' + CHAR(10) + CHAR(10) +
        @cierre_cantidad;
    IF CHARINDEX(N'La salida del palet anterior no esta confirmada', @cierre) = 0
    BEGIN
        IF CHARINDEX(@cierre_cantidad, @cierre) = 0
            THROW 51054, 'El cierre no contiene el punto de secuencia esperado.', 1;
        SET @cierre = REPLACE(@cierre, @cierre_cantidad, @cierre_salida_previa);
    END;

    DECLARE @cierre_bloqueo_anterior nvarchar(max) =
        N'    UPDATE prod.estados_linea' + CHAR(10) +
        N'    SET estado = N''PENDIENTE_NAV'',' + CHAR(10) +
        N'        motivo_bloqueo = N''SALIDA_PALET_PENDIENTE'',' + CHAR(10) +
        N'        actualizado_utc = SYSUTCDATETIME()' + CHAR(10) +
        N'    WHERE linea_id = @linea_id;';
    DECLARE @cierre_bloqueo_nuevo nvarchar(max) =
        N'    IF @es_ultimo = 1' + CHAR(10) +
        N'        UPDATE prod.estados_linea' + CHAR(10) +
        N'        SET estado = N''PENDIENTE_NAV'',' + CHAR(10) +
        N'            motivo_bloqueo = N''SALIDA_ULTIMO_PALET_PENDIENTE'',' + CHAR(10) +
        N'            actualizado_utc = SYSUTCDATETIME()' + CHAR(10) +
        N'        WHERE linea_id = @linea_id' + CHAR(10) +
        N'          AND sesion_linea_id = @sesion_linea_id;';
    IF CHARINDEX(@cierre_bloqueo_anterior, @cierre) = 0
        THROW 51055, 'El cierre no contiene el bloqueo NAV esperado.', 1;
    SET @cierre = REPLACE(
        @cierre, @cierre_bloqueo_anterior, @cierre_bloqueo_nuevo);
    EXEC sys.sp_executesql @cierre;

    UPDATE el
    SET estado = CASE
            WHEN s.estado IN (N'PRODUCIENDO', N'SIN_OPERARIOS', N'ORDEN_CARGADA')
                THEN s.estado
            ELSE N'SIN_OPERARIOS'
        END,
        motivo_bloqueo = NULL,
        actualizado_utc = SYSUTCDATETIME()
    FROM prod.estados_linea el
    JOIN prod.sesiones_linea s
      ON s.sesion_linea_id = el.sesion_linea_id
     AND s.linea_id = el.linea_id
     AND s.finalizada_utc IS NULL
    JOIN prod.ordenes o
      ON o.orden_id = s.orden_id
     AND o.estado IN (N'IMPORTADA', N'ABIERTA', N'PICO_PENDIENTE')
    WHERE el.estado = N'PENDIENTE_NAV'
      AND EXISTS
      (
          SELECT 1
          FROM prod.palets p
          JOIN nav.operaciones n
            ON n.palet_id = p.palet_id
           AND n.orden_id = p.orden_id
           AND n.tipo = N'SALIDA_PALET'
           AND n.estado <> N'CONFIRMADA'
          WHERE p.sesion_linea_id = s.sesion_linea_id
            AND p.es_ultimo = 0
      );

    GRANT EXECUTE ON OBJECT::nav.reservar_siguiente_salida_palet TO mes_runtime;
    GRANT EXECUTE ON OBJECT::nav.fallar_salida_palet TO mes_runtime;

    DECLARE @reserva_def nvarchar(max) =
        OBJECT_DEFINITION(OBJECT_ID(N'nav.reservar_siguiente_salida_palet'));
    DECLARE @fallo_def nvarchar(max) =
        OBJECT_DEFINITION(OBJECT_ID(N'nav.fallar_salida_palet'));
    DECLARE @cierre_def nvarchar(max) =
        OBJECT_DEFINITION(OBJECT_ID(N'prod.cerrar_palet'));
    IF @reserva_def NOT LIKE N'%n.identificador_externo%'
     OR @reserva_def NOT LIKE N'%estado = N''RESULTADO_DESCONOCIDO''%'
     OR @fallo_def NOT LIKE N'%DATEADD(SECOND, 10%'
     OR @cierre_def NOT LIKE N'%THROW 51412%'
     OR @cierre_def NOT LIKE N'%IF @es_ultimo = 1%'
     OR @cierre_def LIKE N'%motivo_bloqueo = N''SALIDA_PALET_PENDIENTE''%'
        THROW 51056, 'El contrato 028A no quedo publicado completamente.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
