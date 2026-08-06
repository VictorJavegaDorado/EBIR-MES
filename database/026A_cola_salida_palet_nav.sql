/*
Paquete 026A - Cola segura para salidas de palet hacia NAV.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV. Publica contratos de reserva y resultado para que un worker
procese exclusivamente operaciones SALIDA_PALET con reintento acotado y
resultado desconocido ante una reserva caducada.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'nav.operaciones', N'U') IS NULL
 OR OBJECT_ID(N'nav.intentos_operacion', N'U') IS NULL
 OR OBJECT_ID(N'nav.confirmar_salida_palet', N'P') IS NULL
 OR OBJECT_ID(N'prod.palets', N'U') IS NULL
 OR OBJECT_ID(N'prod.ordenes', N'U') IS NULL
    THROW 51042, 'El paquete 026A requiere la cola NAV y su confirmacion de salida.', 1;
GO

IF COL_LENGTH(N'nav.operaciones', N'reservado_utc') IS NOT NULL
 OR COL_LENGTH(N'nav.operaciones', N'reservado_por') IS NOT NULL
 OR OBJECT_ID(N'nav.reservar_siguiente_salida_palet', N'P') IS NOT NULL
 OR OBJECT_ID(N'nav.completar_salida_palet', N'P') IS NOT NULL
 OR OBJECT_ID(N'nav.fallar_salida_palet', N'P') IS NOT NULL
    THROW 51043, 'El paquete 026A ya existe total o parcialmente.', 1;
GO

IF EXISTS (SELECT 1 FROM nav.operaciones WHERE estado = N'PROCESANDO')
    THROW 51045, 'Existen operaciones NAV en proceso; no se puede instalar 026A.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    ALTER TABLE nav.operaciones ADD
        reservado_utc datetime2(3) NULL,
        reservado_por nvarchar(100) NULL;

    EXEC sys.sp_executesql N'
ALTER TABLE nav.operaciones ADD CONSTRAINT CK_nav_operaciones_reserva
CHECK
(
    estado <> N''PROCESANDO'' OR
    (reservado_utc IS NOT NULL AND LEN(LTRIM(RTRIM(reservado_por))) > 0)
);';

    EXEC sys.sp_executesql N'
CREATE PROCEDURE nav.reservar_siguiente_salida_palet
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
                o.numero_orden, o.producto_codigo, p.cantidad_buena,
                p.cerrado_utc, n.numero_intentos + 1 AS numero_intento
            FROM nav.operaciones n
            JOIN prod.palets p
              ON p.palet_id = n.palet_id
             AND p.orden_id = n.orden_id
            JOIN prod.ordenes o ON o.orden_id = n.orden_id
            WHERE n.operacion_nav_id = @operacion_id;
        END;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'
CREATE PROCEDURE nav.completar_salida_palet
    @operacion_nav_id bigint,
    @numero_intento int,
    @identificador_externo nvarchar(100),
    @codigo_http int = NULL,
    @correlacion_id uniqueidentifier,
    @datos_tecnicos nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @identificador_externo = NULLIF(LTRIM(RTRIM(@identificador_externo)), N'''');
    IF @identificador_externo IS NULL OR @correlacion_id IS NULL
       OR ISJSON(@datos_tecnicos) <> 1
       OR (@codigo_http IS NOT NULL AND @codigo_http NOT BETWEEN 100 AND 599)
        THROW 56010, ''El resultado confirmado de NAV no es valido.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @inicio datetime2(3), @intentos int;
        SELECT @inicio = reservado_utc, @intentos = numero_intentos
        FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
        WHERE operacion_nav_id = @operacion_nav_id
          AND tipo = N''SALIDA_PALET''
          AND estado = N''PROCESANDO'';
        IF @inicio IS NULL OR @numero_intento <> @intentos + 1
            THROW 56011, ''La salida NAV no corresponde a la reserva activa.'', 1;

        EXEC nav.confirmar_salida_palet
            @operacion_nav_id = @operacion_nav_id,
            @respuesta = @datos_tecnicos,
            @identificador_externo = @identificador_externo,
            @correlacion_id = @correlacion_id;

        INSERT nav.intentos_operacion
        (
            operacion_nav_id, numero_intento, inicio_utc, fin_utc,
            resultado, codigo_http, respuesta
        )
        VALUES
        (
            @operacion_nav_id, CONVERT(smallint, @numero_intento), @inicio,
            SYSUTCDATETIME(), N''CONFIRMADA'', @codigo_http, @datos_tecnicos
        );

        UPDATE nav.operaciones
        SET reservado_utc = NULL, reservado_por = NULL
        WHERE operacion_nav_id = @operacion_nav_id;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'
CREATE PROCEDURE nav.fallar_salida_palet
    @operacion_nav_id bigint,
    @numero_intento int,
    @resultado nvarchar(30),
    @identificador_externo nvarchar(100) = NULL,
    @codigo_http int = NULL,
    @datos_tecnicos nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @identificador_externo =
        NULLIF(LTRIM(RTRIM(@identificador_externo)), N'''');
    IF @resultado NOT IN
       (N''ERROR_REINTENTABLE'', N''RESULTADO_DESCONOCIDO'', N''ERROR_DEFINITIVO'')
       OR ISJSON(@datos_tecnicos) <> 1
       OR (@codigo_http IS NOT NULL AND @codigo_http NOT BETWEEN 100 AND 599)
        THROW 56020, ''El fallo normalizado de NAV no es valido.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @inicio datetime2(3), @intentos int, @resultado_final nvarchar(30);
        SELECT @inicio = reservado_utc, @intentos = numero_intentos
        FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
        WHERE operacion_nav_id = @operacion_nav_id
          AND tipo = N''SALIDA_PALET''
          AND estado = N''PROCESANDO'';
        IF @inicio IS NULL OR @numero_intento <> @intentos + 1
            THROW 56021, ''La salida NAV no corresponde a la reserva activa.'', 1;

        SET @resultado_final = CASE
            WHEN @resultado = N''ERROR_REINTENTABLE'' AND @numero_intento >= 3
                THEN N''ERROR_DEFINITIVO''
            ELSE @resultado END;

        INSERT nav.intentos_operacion
        (
            operacion_nav_id, numero_intento, inicio_utc, fin_utc,
            resultado, codigo_http, error_normalizado, respuesta
        )
        VALUES
        (
            @operacion_nav_id, CONVERT(smallint, @numero_intento), @inicio,
            SYSUTCDATETIME(), @resultado_final, @codigo_http,
            @resultado_final, @datos_tecnicos
        );

        UPDATE nav.operaciones
        SET estado = @resultado_final,
            numero_intentos = @numero_intento,
            proximo_intento_utc = CASE
                WHEN @resultado_final = N''ERROR_REINTENTABLE''
                    THEN DATEADD(SECOND, 5 * @numero_intento, SYSUTCDATETIME())
                ELSE NULL END,
            procesada_utc = CASE
                WHEN @resultado_final = N''ERROR_REINTENTABLE'' THEN NULL
                ELSE SYSUTCDATETIME() END,
            identificador_externo = COALESCE(
                @identificador_externo, identificador_externo),
            reservado_utc = NULL,
            reservado_por = NULL
        WHERE operacion_nav_id = @operacion_nav_id;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    GRANT EXECUTE ON OBJECT::nav.reservar_siguiente_salida_palet TO mes_runtime;
    GRANT EXECUTE ON OBJECT::nav.completar_salida_palet TO mes_runtime;
    GRANT EXECUTE ON OBJECT::nav.fallar_salida_palet TO mes_runtime;

    IF COL_LENGTH(N'nav.operaciones', N'reservado_utc') IS NULL
     OR COL_LENGTH(N'nav.operaciones', N'reservado_por') IS NULL
     OR OBJECT_ID(N'nav.reservar_siguiente_salida_palet', N'P') IS NULL
     OR OBJECT_ID(N'nav.completar_salida_palet', N'P') IS NULL
     OR OBJECT_ID(N'nav.fallar_salida_palet', N'P') IS NULL
        THROW 51044, 'No se crearon todos los objetos del paquete 026A.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
