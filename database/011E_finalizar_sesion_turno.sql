/*
Paquete 011E - Finalizacion supervisada de sesion de turno.
Estado: preparado para revision; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.finalizar_sesion_turno
    @sesion_linea_id bigint,
    @supervisor_id bigint,
    @correlacion_id uniqueidentifier,
    @fichajes_cerrados int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @fichajes_cerrados = 0;

    IF @correlacion_id IS NULL
        THROW 52100, 'La correlacion es obligatoria.', 1;

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
        THROW 52101, 'La finalizacion de turno requiere supervisor activo.', 1;

    DECLARE
        @ahora_utc datetime2(3) = SYSUTCDATETIME(),
        @orden_id bigint,
        @linea_id bigint,
        @orden_bloqueada_id bigint,
        @estado_orden nvarchar(30),
        @sesion_orden_id bigint,
        @sesion_linea_bloqueada_id bigint,
        @estado_sesion nvarchar(30),
        @estado_linea nvarchar(30),
        @sesion_estado_linea_id bigint;

    /* Orden global de bloqueos:
       orden -> sesion -> linea -> reservas/integracion -> operaciones abiertas. */
    SELECT
        @orden_id = orden_id,
        @linea_id = linea_id
    FROM prod.sesiones_linea
    WHERE sesion_linea_id = @sesion_linea_id;

    IF @orden_id IS NULL
        THROW 52102, 'Sesion no encontrada.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @orden_bloqueada_id = orden_id,
            @estado_orden = estado
        FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
        WHERE orden_id = @orden_id;

        IF @orden_bloqueada_id IS NULL
            THROW 52103, 'Orden no encontrada.', 1;

        IF @estado_orden NOT IN (N'IMPORTADA', N'ABIERTA', N'PICO_PENDIENTE')
            THROW 52113, 'El estado de la orden no admite fin de turno.', 1;

        SELECT
            @sesion_orden_id = orden_id,
            @sesion_linea_bloqueada_id = linea_id,
            @estado_sesion = estado
        FROM prod.sesiones_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND finalizada_utc IS NULL;

        IF @sesion_orden_id IS NULL
            THROW 52104, 'La sesion no esta activa.', 1;

        IF @sesion_orden_id <> @orden_id
           OR @sesion_linea_bloqueada_id <> @linea_id
            THROW 52105, 'La sesion cambio durante la operacion.', 1;

        IF @estado_sesion NOT IN
           (N'CARGADA', N'PRODUCIENDO', N'SIN_OPERARIOS',
            N'STANDBY', N'PICO_PENDIENTE')
            THROW 52106, 'El estado de la sesion no admite fin de turno.', 1;

        SELECT
            @estado_linea = estado,
            @sesion_estado_linea_id = sesion_linea_id
        FROM prod.estados_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE linea_id = @linea_id;

        IF @sesion_estado_linea_id <> @sesion_linea_id
            THROW 52107, 'La linea no corresponde a la sesion activa.', 1;

        IF @estado_linea NOT IN
           (N'ORDEN_CARGADA', N'PRODUCIENDO', N'SIN_OPERARIOS',
            N'STANDBY', N'PICO_PENDIENTE')
            THROW 52108, 'El estado de la linea no admite fin de turno.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.reservas_palet WITH (UPDLOCK, HOLDLOCK)
            WHERE sesion_linea_id = @sesion_linea_id
              AND estado = N'ACTIVA'
        )
            THROW 52109, 'La sesion mantiene una reserva activa.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.palets p
            JOIN nav.operaciones n WITH (UPDLOCK, HOLDLOCK)
              ON n.palet_id = p.palet_id
             AND n.orden_id = p.orden_id
             AND n.tipo = N'SALIDA_PALET'
            WHERE p.sesion_linea_id = @sesion_linea_id
              AND n.estado <> N'CONFIRMADA'
        )
            THROW 52110, 'La sesion mantiene una salida de palet NAV pendiente.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.palets p
            JOIN imp.etiquetas e WITH (UPDLOCK, HOLDLOCK)
              ON e.palet_id = p.palet_id
             AND e.orden_id = p.orden_id
             AND e.tipo = N'PALET'
            WHERE p.sesion_linea_id = @sesion_linea_id
              AND e.estado <> N'IMPRESA'
        )
            THROW 52111, 'La sesion mantiene una etiqueta de palet pendiente.', 1;

        /* Revalida y bloquea el supervisor dentro de la transaccion. */
        IF NOT EXISTS
        (
            SELECT 1
            FROM seg.empleados e WITH (UPDLOCK, HOLDLOCK)
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
            THROW 52112, 'El supervisor dejo de estar activo.', 1;

        UPDATE po
        SET fin_utc = @ahora_utc,
            estado = N'CERRADO'
        FROM prod.paros_operario po
        JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
        WHERE f.sesion_linea_id = @sesion_linea_id
          AND po.fin_utc IS NULL;

        UPDATE prod.sustituciones_capacidad
        SET fin_utc = @ahora_utc,
            estado = N'FINALIZADA'
        WHERE sesion_linea_id = @sesion_linea_id
          AND fin_utc IS NULL;

        UPDATE prod.paradas_linea
        SET fin_utc = @ahora_utc,
            cerrada_por_empleado_id = @supervisor_id
        WHERE sesion_linea_id = @sesion_linea_id
          AND fin_utc IS NULL;

        UPDATE prod.fichajes
        SET salida_utc = @ahora_utc,
            estado = N'CERRADO',
            cerrado_por_sistema = 1
        WHERE sesion_linea_id = @sesion_linea_id
          AND salida_utc IS NULL;

        SET @fichajes_cerrados = @@ROWCOUNT;

        UPDATE prod.tramos_capacidad
        SET fin_utc = @ahora_utc,
            segundos_productivos =
                CASE WHEN @estado_sesion = N'PRODUCIENDO'
                     THEN DATEDIFF(SECOND, inicio_utc, @ahora_utc)
                     ELSE segundos_productivos END
        WHERE sesion_linea_id = @sesion_linea_id
          AND fin_utc IS NULL;

        UPDATE prod.sesiones_linea
        SET estado = N'FINALIZADA_TURNO',
            finalizada_utc = @ahora_utc,
            motivo_fin = N'FIN_TURNO',
            cerrada_por_empleado_id = @supervisor_id
        WHERE sesion_linea_id = @sesion_linea_id;

        UPDATE prod.estados_linea
        SET sesion_linea_id = NULL,
            estado = N'LIBRE',
            motivo_bloqueo = NULL,
            actualizado_utc = @ahora_utc
        WHERE linea_id = @linea_id
          AND sesion_linea_id = @sesion_linea_id;

        EXEC aud.registrar_evento
            @tipo_evento = N'SESION_FINALIZADA_TURNO',
            @empleado_id = @supervisor_id,
            @rol_usado = N'SUPERVISOR',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'prod.sesiones_linea',
            @entidad_id = @sesion_linea_id,
            @valor_anterior = NULL,
            @valor_nuevo = NULL,
            @motivo = N'FIN_TURNO',
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
    GRANT EXECUTE ON OBJECT::prod.finalizar_sesion_turno TO mes_runtime;
GO
