SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'imp.trabajos_impresion', N'U') IS NULL
 OR OBJECT_ID(N'imp.intentos_impresion', N'U') IS NULL
 OR OBJECT_ID(N'imp.confirmar_trabajo_impresion', N'P') IS NULL
    THROW 51023, 'El paquete 018 requiere el modelo de impresion y el paquete 012.', 1;

IF COL_LENGTH(N'imp.trabajos_impresion', N'numero_intentos') IS NOT NULL
 OR OBJECT_ID(N'imp.reservar_siguiente_trabajo_impresion', N'P') IS NOT NULL
 OR OBJECT_ID(N'imp.completar_trabajo_impresion', N'P') IS NOT NULL
 OR OBJECT_ID(N'imp.fallar_trabajo_impresion', N'P') IS NOT NULL
    THROW 51024, 'El paquete 018 ya existe total o parcialmente.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    ALTER TABLE imp.trabajos_impresion ADD
        numero_intentos int NOT NULL
            CONSTRAINT DF_imp_trabajos_numero_intentos DEFAULT (0),
        reservado_utc datetime2(3) NULL,
        reservado_por nvarchar(100) NULL,
        proximo_intento_utc datetime2(3) NULL;

    EXEC sys.sp_executesql N'
ALTER TABLE imp.trabajos_impresion ADD
    CONSTRAINT CK_imp_trabajos_numero_intentos CHECK (numero_intentos >= 0),
    CONSTRAINT CK_imp_trabajos_reserva CHECK
    (
        estado <> N''PROCESANDO'' OR
        (reservado_utc IS NOT NULL AND LEN(LTRIM(RTRIM(reservado_por))) > 0)
    ),
    CONSTRAINT CK_imp_trabajos_proximo_intento CHECK
    (
        proximo_intento_utc IS NULL OR estado = N''PENDIENTE''
    );';

    DECLARE @reservar nvarchar(max) = N'
CREATE PROCEDURE imp.reservar_siguiente_trabajo_impresion
    @worker_id nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @worker_id = NULLIF(LTRIM(RTRIM(@worker_id)), N'''');
    IF @worker_id IS NULL
        THROW 55800, ''La identidad del worker es obligatoria.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @ahora datetime2(3) = SYSUTCDATETIME();

        INSERT imp.intentos_impresion
        (
            trabajo_impresion_id, numero_intento, inicio_utc, fin_utc,
            resultado, mensaje_error, datos_tecnicos
        )
        SELECT
            trabajo_impresion_id, numero_intentos, reservado_utc, @ahora,
            N''RESULTADO_DESCONOCIDO'', N''RESERVA_CADUCADA'',
            N''{""origen"":""MES_WORKER"",""motivo"":""reserva_caducada""}''
        FROM imp.trabajos_impresion WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE estado = N''PROCESANDO''
          AND reservado_utc < DATEADD(MINUTE, -5, @ahora);

        UPDATE imp.trabajos_impresion
        SET estado = N''RESULTADO_DESCONOCIDO'',
            procesado_utc = @ahora,
            proximo_intento_utc = NULL
        WHERE estado = N''PROCESANDO''
          AND reservado_utc < DATEADD(MINUTE, -5, @ahora);

        DECLARE @trabajo_id bigint;
        SELECT TOP (1) @trabajo_id = t.trabajo_impresion_id
        FROM imp.trabajos_impresion t WITH (UPDLOCK, READPAST, ROWLOCK)
        JOIN imp.etiquetas e ON e.etiqueta_id = t.etiqueta_id
        JOIN cfg.impresoras i ON i.impresora_id = t.impresora_solicitada_id
        WHERE t.estado = N''PENDIENTE''
          AND (t.proximo_intento_utc IS NULL OR t.proximo_intento_utc <= @ahora)
          AND e.estado = N''LISTA''
          AND i.activa = 1
        ORDER BY t.creado_utc, t.trabajo_impresion_id;

        IF @trabajo_id IS NOT NULL
        BEGIN
            UPDATE imp.trabajos_impresion
            SET estado = N''PROCESANDO'',
                numero_intentos = numero_intentos + 1,
                reservado_utc = @ahora,
                reservado_por = @worker_id,
                proximo_intento_utc = NULL
            WHERE trabajo_impresion_id = @trabajo_id;

            SELECT
                t.trabajo_impresion_id, t.trabajo_uid,
                e.etiqueta_id, e.etiqueta_uid,
                t.impresora_solicitada_id, i.codigo AS impresora_codigo,
                i.modelo AS impresora_modelo, e.plantilla_codigo,
                e.plantilla_version, e.datos_etiqueta, e.numero_copias,
                t.numero_intentos
            FROM imp.trabajos_impresion t
            JOIN imp.etiquetas e ON e.etiqueta_id = t.etiqueta_id
            JOIN cfg.impresoras i ON i.impresora_id = t.impresora_solicitada_id
            WHERE t.trabajo_impresion_id = @trabajo_id;
        END;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';
    EXEC sys.sp_executesql @reservar;

    DECLARE @completar nvarchar(max) = N'
CREATE PROCEDURE imp.completar_trabajo_impresion
    @trabajo_impresion_id bigint,
    @numero_intento int,
    @impresora_utilizada_id bigint,
    @correlacion_id uniqueidentifier,
    @datos_tecnicos nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISJSON(@datos_tecnicos) <> 1
        THROW 55810, ''Los datos tecnicos deben ser JSON.'', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @inicio_utc datetime2(3);
        SELECT @inicio_utc = reservado_utc
        FROM imp.trabajos_impresion WITH (UPDLOCK, HOLDLOCK)
        WHERE trabajo_impresion_id = @trabajo_impresion_id
          AND estado = N''PROCESANDO''
          AND numero_intentos = @numero_intento;
        IF @inicio_utc IS NULL
            THROW 55811, ''El trabajo no corresponde a la reserva activa.'', 1;

        EXEC imp.confirmar_trabajo_impresion
            @trabajo_impresion_id = @trabajo_impresion_id,
            @impresora_utilizada_id = @impresora_utilizada_id,
            @correlacion_id = @correlacion_id;

        INSERT imp.intentos_impresion
        (
            trabajo_impresion_id, numero_intento, inicio_utc, fin_utc,
            resultado, datos_tecnicos
        )
        VALUES
        (
            @trabajo_impresion_id, @numero_intento, @inicio_utc,
            SYSUTCDATETIME(), N''COMPLETADO'', @datos_tecnicos
        );
        UPDATE imp.trabajos_impresion
        SET reservado_utc = NULL, reservado_por = NULL
        WHERE trabajo_impresion_id = @trabajo_impresion_id;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';
    EXEC sys.sp_executesql @completar;

    DECLARE @fallar nvarchar(max) = N'
CREATE PROCEDURE imp.fallar_trabajo_impresion
    @trabajo_impresion_id bigint,
    @numero_intento int,
    @error_normalizado nvarchar(1000),
    @datos_tecnicos nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @error_normalizado = NULLIF(LTRIM(RTRIM(@error_normalizado)), N'''');
    IF @error_normalizado IS NULL OR ISJSON(@datos_tecnicos) <> 1
        THROW 55820, ''El fallo de impresion no es valido.'', 1;
    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @inicio_utc datetime2(3);
        SELECT @inicio_utc = reservado_utc
        FROM imp.trabajos_impresion WITH (UPDLOCK, HOLDLOCK)
        WHERE trabajo_impresion_id = @trabajo_impresion_id
          AND estado = N''PROCESANDO''
          AND numero_intentos = @numero_intento;
        IF @inicio_utc IS NULL
            THROW 55821, ''El trabajo no corresponde a la reserva activa.'', 1;

        INSERT imp.intentos_impresion
        (
            trabajo_impresion_id, numero_intento, inicio_utc, fin_utc,
            resultado, mensaje_error, datos_tecnicos
        )
        VALUES
        (
            @trabajo_impresion_id, @numero_intento, @inicio_utc,
            SYSUTCDATETIME(), N''ERROR'', @error_normalizado, @datos_tecnicos
        );

        UPDATE imp.trabajos_impresion
        SET estado = CASE WHEN numero_intentos >= 3 THEN N''ERROR'' ELSE N''PENDIENTE'' END,
            procesado_utc = CASE WHEN numero_intentos >= 3 THEN SYSUTCDATETIME() ELSE NULL END,
            reservado_utc = NULL,
            reservado_por = NULL,
            proximo_intento_utc = CASE WHEN numero_intentos >= 3 THEN NULL
                ELSE DATEADD(SECOND, 5 * numero_intentos, SYSUTCDATETIME()) END
        WHERE trabajo_impresion_id = @trabajo_impresion_id;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';
    EXEC sys.sp_executesql @fallar;

    GRANT EXECUTE ON OBJECT::imp.reservar_siguiente_trabajo_impresion TO mes_runtime;
    GRANT EXECUTE ON OBJECT::imp.completar_trabajo_impresion TO mes_runtime;
    GRANT EXECUTE ON OBJECT::imp.fallar_trabajo_impresion TO mes_runtime;

    IF COL_LENGTH(N'imp.trabajos_impresion', N'numero_intentos') IS NULL
     OR OBJECT_ID(N'imp.reservar_siguiente_trabajo_impresion', N'P') IS NULL
     OR OBJECT_ID(N'imp.completar_trabajo_impresion', N'P') IS NULL
     OR OBJECT_ID(N'imp.fallar_trabajo_impresion', N'P') IS NULL
        THROW 51025, 'No se crearon todos los objetos del paquete 018.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
