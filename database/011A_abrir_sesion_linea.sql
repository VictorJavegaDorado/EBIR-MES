/*
Paquete 011A - Apertura/reanudacion de sesion de linea.
Estado: preparado para revision; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.abrir_sesion_linea
    @orden_id bigint,
    @linea_id bigint,
    @formato_palet_orden_id bigint,
    @supervisor_id bigint,
    @inicio_fuera_horario_confirmado bit = 0,
    @correlacion_id uniqueidentifier,
    @sesion_linea_id bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @sesion_linea_id = NULL;

    IF NOT EXISTS
    (
        SELECT 1
        FROM seg.empleados e
        JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
        JOIN seg.roles r ON r.rol_id = er.rol_id
        WHERE e.empleado_id = @supervisor_id
          AND e.activo_nav = 1
          AND e.activo_mes = 1
          AND e.anonimizado_utc IS NULL
          AND er.hasta_utc IS NULL
          AND r.codigo = N'SUPERVISOR'
          AND r.activo = 1
    )
        THROW 51700, 'La apertura de sesion requiere supervisor activo.', 1;

    DECLARE
        @ahora_utc datetime2(3) = SYSUTCDATETIME(),
        @ahora_madrid datetimeoffset(3),
        @hora_madrid time(0),
        @fecha_madrid date,
        @fecha_operativa date,
        @turno_codigo nvarchar(20),
        @turno_id smallint,
        @fuera_horario bit,
        @modo_trabajo nvarchar(20),
        @estado_orden nvarchar(30),
        @estado_linea nvarchar(30),
        @sesion_actual_id bigint;

    SET @ahora_madrid =
        @ahora_utc AT TIME ZONE N'UTC'
                   AT TIME ZONE N'Romance Standard Time';
    SET @hora_madrid = CONVERT(time(0), @ahora_madrid);
    SET @fecha_madrid = CONVERT(date, @ahora_madrid);
    SET @fuera_horario =
        CASE WHEN @hora_madrid < '06:00' OR @hora_madrid >= '22:00'
             THEN 1 ELSE 0 END;

    IF @fuera_horario = 1 AND @inicio_fuera_horario_confirmado = 0
        THROW 51701, 'El inicio fuera de horario requiere confirmacion explicita.', 1;

    SET @turno_codigo =
        CASE WHEN @hora_madrid >= '06:00' AND @hora_madrid < '14:00'
             THEN N'MANANA' ELSE N'TARDE' END;
    SET @fecha_operativa =
        CASE WHEN @hora_madrid < '06:00'
             THEN DATEADD(DAY, -1, @fecha_madrid)
             ELSE @fecha_madrid END;

    SELECT @turno_id = turno_id
    FROM cfg.turnos
    WHERE codigo = @turno_codigo
      AND activo = 1;

    IF @turno_id IS NULL
        THROW 51702, 'No existe el turno activo calculado para la sesion.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS
        (
            SELECT 1
            FROM cfg.lineas WITH (UPDLOCK, HOLDLOCK)
            WHERE linea_id = @linea_id
              AND activa = 1
        )
            THROW 51703, 'La linea no existe o no esta activa.', 1;

        SELECT
            @estado_linea = estado,
            @sesion_actual_id = sesion_linea_id
        FROM prod.estados_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE linea_id = @linea_id;

        IF @estado_linea IS NULL
            THROW 51704, 'La linea no dispone de estado operativo inicial.', 1;

        IF @estado_linea <> N'LIBRE' OR @sesion_actual_id IS NOT NULL
            THROW 51705, 'La linea no esta libre para abrir una sesion.', 1;

        SELECT
            @modo_trabajo = modo_trabajo,
            @estado_orden = estado
        FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
        WHERE orden_id = @orden_id;

        IF @modo_trabajo IS NULL
            THROW 51706, 'Orden no encontrada.', 1;

        IF @estado_orden NOT IN (N'IMPORTADA', N'ABIERTA', N'PICO_PENDIENTE')
            THROW 51707, 'La orden no admite una nueva sesion.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM prod.formatos_palet_orden WITH (UPDLOCK, HOLDLOCK)
            WHERE formato_palet_orden_id = @formato_palet_orden_id
              AND orden_id = @orden_id
              AND activo = 1
        )
            THROW 51708, 'El formato de palet no pertenece a la orden o no esta activo.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.sesiones_linea WITH (UPDLOCK, HOLDLOCK)
            WHERE linea_id = @linea_id
              AND finalizada_utc IS NULL
        )
            THROW 51709, 'La linea ya tiene una sesion activa.', 1;

        IF @modo_trabajo = N'NORMAL'
           AND EXISTS
           (
               SELECT 1
               FROM prod.sesiones_linea WITH (UPDLOCK, HOLDLOCK)
               WHERE orden_id = @orden_id
                 AND finalizada_utc IS NULL
           )
            THROW 51710, 'La orden normal ya tiene una sesion activa.', 1;

        INSERT prod.sesiones_linea
        (
            orden_id, linea_id, turno_id, formato_palet_orden_id,
            fecha_operativa, estado, cambio_turno_pendiente, cargada_utc,
            cargada_por_empleado_id
        )
        VALUES
        (
            @orden_id, @linea_id, @turno_id, @formato_palet_orden_id,
            @fecha_operativa, N'CARGADA', @fuera_horario, @ahora_utc,
            @supervisor_id
        );

        SET @sesion_linea_id = SCOPE_IDENTITY();

        UPDATE prod.estados_linea
        SET sesion_linea_id = @sesion_linea_id,
            estado = N'ORDEN_CARGADA',
            motivo_bloqueo = NULL,
            actualizado_utc = @ahora_utc
        WHERE linea_id = @linea_id;

        EXEC aud.registrar_evento
            @tipo_evento = N'SESION_LINEA_ABIERTA',
            @empleado_id = @supervisor_id,
            @rol_usado = N'SUPERVISOR',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'prod.sesiones_linea',
            @entidad_id = @sesion_linea_id,
            @valor_nuevo = NULL,
            @motivo = NULL,
            @correlacion_id = @correlacion_id;

        IF @fuera_horario = 1
            EXEC aud.registrar_evento
                @tipo_evento = N'INICIO_FUERA_HORARIO',
                @empleado_id = @supervisor_id,
                @rol_usado = N'SUPERVISOR',
                @linea_id = @linea_id,
                @orden_id = @orden_id,
                @sesion_linea_id = @sesion_linea_id,
                @entidad = N'prod.sesiones_linea',
                @entidad_id = @sesion_linea_id,
                @valor_nuevo = NULL,
                @motivo = N'Inicio fuera de 06:00-22:00 confirmado',
                @correlacion_id = @correlacion_id;

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
    GRANT EXECUTE ON OBJECT::prod.abrir_sesion_linea TO mes_runtime;
GO
