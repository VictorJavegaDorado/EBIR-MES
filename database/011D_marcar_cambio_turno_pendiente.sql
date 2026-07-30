/*
Paquete 011D - Marcado idempotente de cambio de turno pendiente.
Estado: preparado para revision; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.marcar_cambio_turno_pendiente
    @sesion_linea_id bigint,
    @correlacion_id uniqueidentifier,
    @cambio_marcado bit OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @cambio_marcado = 0;

    IF @correlacion_id IS NULL
        THROW 52003, 'La correlacion es obligatoria.', 1;

    DECLARE
        @ahora_utc datetime2(3) = SYSUTCDATETIME(),
        @ahora_madrid datetimeoffset(3),
        @fecha_madrid date,
        @hora_madrid time(0),
        @orden_id bigint,
        @linea_id bigint,
        @fecha_operativa date,
        @turno_codigo nvarchar(20),
        @cambio_actual bit,
        @limite_hora time(0),
        @limite_alcanzado bit;

    SET @ahora_madrid =
        @ahora_utc AT TIME ZONE N'UTC'
                   AT TIME ZONE N'Romance Standard Time';
    SET @fecha_madrid = CONVERT(date, @ahora_madrid);
    SET @hora_madrid = CONVERT(time(0), @ahora_madrid);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @orden_id = s.orden_id,
            @linea_id = s.linea_id,
            @fecha_operativa = s.fecha_operativa,
            @turno_codigo = t.codigo,
            @cambio_actual = s.cambio_turno_pendiente
        FROM prod.sesiones_linea s WITH (UPDLOCK, HOLDLOCK)
        JOIN cfg.turnos t ON t.turno_id = s.turno_id
        WHERE s.sesion_linea_id = @sesion_linea_id
          AND s.finalizada_utc IS NULL;

        IF @orden_id IS NULL
            THROW 52000, 'La sesion no existe o ya esta finalizada.', 1;

        IF @turno_codigo NOT IN (N'MANANA', N'TARDE')
            THROW 52001, 'El turno de la sesion no admite el calculo automatico.', 1;

        SET @limite_hora =
            CASE WHEN @turno_codigo = N'MANANA'
                 THEN '14:00' ELSE '22:00' END;

        SET @limite_alcanzado =
            CASE
                WHEN @fecha_madrid > @fecha_operativa THEN 1
                WHEN @fecha_madrid = @fecha_operativa
                     AND @hora_madrid >= @limite_hora THEN 1
                ELSE 0
            END;

        IF @limite_alcanzado = 0
            THROW 52002, 'Todavia no se ha alcanzado el cambio de turno.', 1;

        IF @cambio_actual = 0
        BEGIN
            UPDATE prod.sesiones_linea
            SET cambio_turno_pendiente = 1
            WHERE sesion_linea_id = @sesion_linea_id;

            SET @cambio_marcado = 1;

            EXEC aud.registrar_evento
                @tipo_evento = N'CAMBIO_TURNO_PENDIENTE',
                @cuenta_dominio = N'EBIR\MES$',
                @linea_id = @linea_id,
                @orden_id = @orden_id,
                @sesion_linea_id = @sesion_linea_id,
                @entidad = N'prod.sesiones_linea',
                @entidad_id = @sesion_linea_id,
                @valor_anterior = N'{"cambio_turno_pendiente":false}',
                @valor_nuevo = N'{"cambio_turno_pendiente":true}',
                @motivo = NULL,
                @correlacion_id = @correlacion_id;
        END;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NOT NULL
    GRANT EXECUTE ON OBJECT::prod.marcar_cambio_turno_pendiente TO mes_runtime;
GO
