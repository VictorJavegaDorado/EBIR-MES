/*
Paquete 038A - Reimpresion supervisada de etiquetas de palet.
Base exclusiva: EBIR_MES_TEST.

La solicitud crea una unica copia auditada e idempotente. La etiqueta original
permanece IMPRESA y el Worker reconoce el trabajo por es_reimpresion, por lo
que una copia no repite transiciones productivas ni operaciones NAV.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'imp.etiquetas', N'U') IS NULL
 OR OBJECT_ID(N'imp.trabajos_impresion', N'U') IS NULL
 OR OBJECT_ID(N'imp.intentos_impresion', N'U') IS NULL
 OR OBJECT_ID(N'imp.reservar_siguiente_trabajo_impresion', N'P') IS NULL
 OR OBJECT_ID(N'imp.completar_trabajo_impresion', N'P') IS NULL
 OR OBJECT_ID(N'imp.confirmar_trabajo_impresion', N'P') IS NULL
 OR OBJECT_ID(N'aud.registrar_evento', N'P') IS NULL
    THROW 51070, 'El paquete 038A requiere la cola de impresion y auditoria.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
    THROW 51071, 'El principal mes_runtime no existe.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @solicitar nvarchar(max) = N'
CREATE OR ALTER PROCEDURE imp.solicitar_reimpresion_palet
    @palet_id bigint,
    @solicitado_por_supervisor_id bigint,
    @motivo nvarchar(500),
    @correlacion_id uniqueidentifier,
    @trabajo_impresion_id bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @motivo = NULLIF(LTRIM(RTRIM(@motivo)), N'''');
    IF @palet_id IS NULL OR @palet_id <= 0
        THROW 56500, ''El pale es obligatorio.'', 1;
    IF @solicitado_por_supervisor_id IS NULL OR @solicitado_por_supervisor_id <= 0
        THROW 56501, ''La reimpresion requiere un supervisor.'', 1;
    IF @motivo IS NULL
        THROW 56502, ''El motivo de reimpresion es obligatorio.'', 1;
    IF @correlacion_id IS NULL
        THROW 56503, ''La correlacion es obligatoria.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @lock_result int,
            @lock_resource nvarchar(255) = CONCAT(
                N''imp:reimpresion:'', CONVERT(nvarchar(36), @correlacion_id));
        EXEC @lock_result = sys.sp_getapplock
            @Resource = @lock_resource,
            @LockMode = N''Exclusive'',
            @LockOwner = N''Transaction'',
            @LockTimeout = 5000;
        IF @lock_result < 0
            THROW 56504, ''No se pudo asegurar la idempotencia de la reimpresion.'', 1;

        DECLARE
            @evento_tipo nvarchar(80),
            @evento_entidad nvarchar(80),
            @evento_trabajo_id bigint,
            @evento_valor nvarchar(max),
            @evento_motivo nvarchar(1000);

        SELECT TOP (1)
            @evento_tipo = tipo_evento,
            @evento_entidad = entidad,
            @evento_trabajo_id = entidad_id,
            @evento_valor = valor_nuevo,
            @evento_motivo = motivo
        FROM aud.eventos WITH (UPDLOCK, HOLDLOCK)
        WHERE correlacion_id = @correlacion_id
        ORDER BY evento_auditoria_id;

        IF @evento_tipo IS NOT NULL
        BEGIN
            IF @evento_tipo <> N''REIMPRESION_ETIQUETA_SOLICITADA''
               OR @evento_entidad <> N''imp.trabajos_impresion''
                THROW 56505, ''La correlacion ya pertenece a otra operacion.'', 1;

            IF ISNULL(TRY_CONVERT(bigint,
                    JSON_VALUE(@evento_valor, ''$.palletId'')), -1) <> @palet_id
               OR ISNULL(TRY_CONVERT(bigint,
                    JSON_VALUE(@evento_valor, ''$.requestedBySupervisorId'')), -1)
                    <> @solicitado_por_supervisor_id
               OR @evento_motivo <> @motivo
                THROW 56506, ''La correlacion ya se utilizo con parametros diferentes.'', 1;

            SET @trabajo_impresion_id = @evento_trabajo_id;
            COMMIT TRANSACTION;
            RETURN;
        END;

        DECLARE
            @orden_id bigint,
            @sesion_linea_id bigint,
            @linea_id bigint,
            @etiqueta_id bigint,
            @etiqueta_uid uniqueidentifier,
            @estado_etiqueta nvarchar(20),
            @impresora_id bigint,
            @valor_nuevo nvarchar(max);

        SELECT
            @orden_id = p.orden_id,
            @sesion_linea_id = p.sesion_linea_id,
            @linea_id = s.linea_id
        FROM prod.palets p WITH (UPDLOCK, HOLDLOCK)
        JOIN prod.sesiones_linea s ON s.sesion_linea_id = p.sesion_linea_id
        WHERE p.palet_id = @palet_id;
        IF @orden_id IS NULL
            THROW 56507, ''El pale no existe.'', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM seg.empleados e WITH (UPDLOCK, HOLDLOCK)
            JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
            JOIN seg.roles r ON r.rol_id = er.rol_id
            WHERE e.empleado_id = @solicitado_por_supervisor_id
              AND e.activo_mes = 1
              AND er.hasta_utc IS NULL
              AND r.codigo = N''SUPERVISOR''
              AND r.activo = 1
        )
            THROW 56508, ''La reimpresion requiere un supervisor activo.'', 1;

        SELECT
            @etiqueta_id = e.etiqueta_id,
            @etiqueta_uid = e.etiqueta_uid,
            @estado_etiqueta = e.estado
        FROM imp.etiquetas e WITH (UPDLOCK, HOLDLOCK)
        WHERE e.palet_id = @palet_id
          AND e.orden_id = @orden_id
          AND e.tipo = N''PALET'';
        IF @etiqueta_id IS NULL
            THROW 56509, ''El pale no tiene una etiqueta disponible.'', 1;
        IF @estado_etiqueta <> N''IMPRESA''
            THROW 56510, ''La etiqueta original todavia no consta como impresa.'', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM imp.trabajos_impresion WITH (UPDLOCK, HOLDLOCK)
            WHERE etiqueta_id = @etiqueta_id
              AND es_reimpresion = 0
              AND estado = N''COMPLETADO''
        )
            THROW 56511, ''No existe una impresion original completada.'', 1;

        IF EXISTS
        (
            SELECT 1
            FROM imp.trabajos_impresion WITH (UPDLOCK, HOLDLOCK)
            WHERE etiqueta_id = @etiqueta_id
              AND estado IN (N''PENDIENTE'', N''PROCESANDO'')
        )
            THROW 56512, ''Ya existe una impresion pendiente para esta etiqueta.'', 1;

        SELECT TOP (1) @impresora_id = li.impresora_id
        FROM cfg.lineas_impresoras li
        JOIN cfg.impresoras i ON i.impresora_id = li.impresora_id
        WHERE li.linea_id = @linea_id
          AND li.asignado_hasta_utc IS NULL
          AND li.es_principal = 1
          AND i.activa = 1
        ORDER BY li.asignado_desde_utc DESC;
        IF @impresora_id IS NULL
            THROW 56513, ''La linea no tiene una impresora principal disponible.'', 1;

        INSERT imp.trabajos_impresion
        (
            etiqueta_id, impresora_solicitada_id, clave_idempotencia,
            es_reimpresion, solicitado_por_empleado_id, motivo, estado
        )
        VALUES
        (
            @etiqueta_id,
            @impresora_id,
            CONCAT(N''MES:PRINT:'', CONVERT(nvarchar(36), @etiqueta_uid),
                N'':REPRINT:'', CONVERT(nvarchar(36), @correlacion_id)),
            1,
            @solicitado_por_supervisor_id,
            @motivo,
            N''PENDIENTE''
        );
        SET @trabajo_impresion_id = SCOPE_IDENTITY();

        SELECT @valor_nuevo =
        (
            SELECT
                @palet_id AS palletId,
                @etiqueta_id AS labelId,
                @trabajo_impresion_id AS printJobId,
                @solicitado_por_supervisor_id AS requestedBySupervisorId,
                1 AS copies
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC aud.registrar_evento
            @tipo_evento = N''REIMPRESION_ETIQUETA_SOLICITADA'',
            @empleado_id = @solicitado_por_supervisor_id,
            @cuenta_dominio = N''EBIR\MES$'',
            @rol_usado = N''SUPERVISOR'',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N''imp.trabajos_impresion'',
            @entidad_id = @trabajo_impresion_id,
            @valor_nuevo = @valor_nuevo,
            @motivo = @motivo,
            @correlacion_id = @correlacion_id;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';
    EXEC sys.sp_executesql @solicitar;

    DECLARE @reservar nvarchar(max) = N'
CREATE OR ALTER PROCEDURE imp.reservar_siguiente_trabajo_impresion
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
          AND
          (
              (t.es_reimpresion = 0 AND e.estado = N''LISTA'')
              OR (t.es_reimpresion = 1 AND e.estado = N''IMPRESA'')
          )
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
CREATE OR ALTER PROCEDURE imp.completar_trabajo_impresion
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
        DECLARE
            @inicio_utc datetime2(3),
            @es_reimpresion bit,
            @etiqueta_id bigint,
            @orden_id bigint,
            @palet_id bigint,
            @sesion_linea_id bigint,
            @linea_id bigint;

        SELECT
            @inicio_utc = t.reservado_utc,
            @es_reimpresion = t.es_reimpresion,
            @etiqueta_id = t.etiqueta_id
        FROM imp.trabajos_impresion t WITH (UPDLOCK, HOLDLOCK)
        WHERE t.trabajo_impresion_id = @trabajo_impresion_id
          AND t.estado = N''PROCESANDO''
          AND t.numero_intentos = @numero_intento;
        IF @inicio_utc IS NULL
            THROW 55811, ''El trabajo no corresponde a la reserva activa.'', 1;

        IF @es_reimpresion = 1
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1 FROM cfg.impresoras
                WHERE impresora_id = @impresora_utilizada_id
                  AND activa = 1
            )
                THROW 51601, ''La impresora utilizada no existe o no esta activa.'', 1;

            SELECT
                @orden_id = e.orden_id,
                @palet_id = e.palet_id
            FROM imp.etiquetas e WITH (UPDLOCK, HOLDLOCK)
            WHERE e.etiqueta_id = @etiqueta_id
              AND e.tipo = N''PALET''
              AND e.estado = N''IMPRESA'';
            IF @orden_id IS NULL
                THROW 51602, ''La etiqueta original no esta impresa.'', 1;

            SELECT
                @sesion_linea_id = p.sesion_linea_id,
                @linea_id = s.linea_id
            FROM prod.palets p
            JOIN prod.sesiones_linea s ON s.sesion_linea_id = p.sesion_linea_id
            WHERE p.palet_id = @palet_id
              AND p.orden_id = @orden_id;

            UPDATE imp.trabajos_impresion
            SET impresora_utilizada_id = @impresora_utilizada_id,
                estado = N''COMPLETADO'',
                procesado_utc = SYSUTCDATETIME()
            WHERE trabajo_impresion_id = @trabajo_impresion_id;

            EXEC aud.registrar_evento
                @tipo_evento = N''ETIQUETA_REIMPRESA'',
                @cuenta_dominio = N''EBIR\MES$'',
                @linea_id = @linea_id,
                @orden_id = @orden_id,
                @sesion_linea_id = @sesion_linea_id,
                @entidad = N''imp.trabajos_impresion'',
                @entidad_id = @trabajo_impresion_id,
                @correlacion_id = @correlacion_id;
        END
        ELSE
        BEGIN
            EXEC imp.confirmar_trabajo_impresion
                @trabajo_impresion_id = @trabajo_impresion_id,
                @impresora_utilizada_id = @impresora_utilizada_id,
                @correlacion_id = @correlacion_id;
        END;

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

    GRANT EXECUTE ON OBJECT::imp.solicitar_reimpresion_palet TO mes_runtime;
    GRANT EXECUTE ON OBJECT::imp.reservar_siguiente_trabajo_impresion TO mes_runtime;
    GRANT EXECUTE ON OBJECT::imp.completar_trabajo_impresion TO mes_runtime;

    IF OBJECT_ID(N'imp.solicitar_reimpresion_palet', N'P') IS NULL
     OR OBJECT_DEFINITION(OBJECT_ID(N'imp.reservar_siguiente_trabajo_impresion'))
        NOT LIKE N'%t.es_reimpresion = 1 AND e.estado = N''IMPRESA''%'
     OR OBJECT_DEFINITION(OBJECT_ID(N'imp.completar_trabajo_impresion'))
        NOT LIKE N'%ETIQUETA_REIMPRESA%'
        THROW 51072, 'El paquete 038A no creo todos sus contratos.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
