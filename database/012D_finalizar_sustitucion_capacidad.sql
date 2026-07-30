/*
Paquete 012D - Finalizacion supervisada de sustitucion de capacidad.
Estado: preparado para revision estatica; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.finalizar_sustitucion_capacidad
    @sustitucion_capacidad_id bigint,
    @supervisor_id bigint,
    @motivo nvarchar(250),
    @correlacion_id uniqueidentifier,
    @recursos_activos int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @recursos_activos = NULL;
    SET @motivo = NULLIF(LTRIM(RTRIM(@motivo)), N'');

    IF @correlacion_id IS NULL
        THROW 52500, 'La correlacion es obligatoria.', 1;

    IF @motivo IS NULL
        THROW 52501, 'El motivo de finalizacion es obligatorio.', 1;

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
        THROW 52502, 'La finalizacion requiere un supervisor activo.', 1;

    DECLARE
        @ahora_utc datetime2(3) = SYSUTCDATETIME(),
        @sesion_linea_id bigint,
        @operario_sustituido_id bigint,
        @supervisor_sustituto_id bigint,
        @fichaje_operario_id bigint,
        @fichaje_supervisor_id bigint,
        @inicio_sustitucion_utc datetime2(3),
        @motivo_inicio nvarchar(250),
        @orden_id bigint,
        @linea_id bigint,
        @orden_bloqueada_id bigint,
        @sesion_orden_id bigint,
        @sesion_linea_bloqueada_id bigint,
        @estado_sesion nvarchar(30),
        @estado_linea nvarchar(30),
        @sesion_estado_linea_id bigint,
        @tiempo_nav decimal(12,1),
        @paro_operario_id bigint,
        @recursos_antes int,
        @capacidad decimal(18,4),
        @valor_anterior nvarchar(max),
        @valor_nuevo nvarchar(max);

    /*
    Lectura inicial sin bloqueo para obtener el contexto. Todos los valores se
    revalidan despues con bloqueos en el orden global.
    */
    SELECT
        @sesion_linea_id = sesion_linea_id,
        @operario_sustituido_id = operario_sustituido_id,
        @supervisor_sustituto_id = supervisor_sustituto_id,
        @fichaje_operario_id = fichaje_operario_id,
        @fichaje_supervisor_id = fichaje_supervisor_id
    FROM prod.sustituciones_capacidad
    WHERE sustitucion_capacidad_id = @sustitucion_capacidad_id;

    IF @sesion_linea_id IS NULL
        THROW 52503, 'Sustitucion no encontrada.', 1;

    SELECT
        @orden_id = orden_id,
        @linea_id = linea_id
    FROM prod.sesiones_linea
    WHERE sesion_linea_id = @sesion_linea_id;

    IF @orden_id IS NULL
        THROW 52504, 'Sesion de la sustitucion no encontrada.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @orden_bloqueada_id = orden_id,
            @tiempo_nav = tiempo_ejecucion_nav_min
        FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
        WHERE orden_id = @orden_id
          AND estado IN
              (N'ABIERTA', N'PICO_PENDIENTE',
               N'PENDIENTE_CIERRE', N'PENDIENTE_NAV', N'ERROR_NAV');

        IF @orden_bloqueada_id IS NULL
            THROW 52505, 'La orden no admite finalizar la sustitucion.', 1;

        SELECT
            @sesion_orden_id = orden_id,
            @sesion_linea_bloqueada_id = linea_id,
            @estado_sesion = estado
        FROM prod.sesiones_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND finalizada_utc IS NULL;

        IF @sesion_orden_id IS NULL
            THROW 52506, 'La sesion no esta activa.', 1;

        IF @sesion_orden_id <> @orden_id
           OR @sesion_linea_bloqueada_id <> @linea_id
            THROW 52507, 'La sesion cambio durante la operacion.', 1;

        IF @estado_sesion NOT IN (N'PRODUCIENDO', N'SIN_OPERARIOS')
            THROW 52508, 'El estado de la sesion no admite finalizar la sustitucion.', 1;

        SELECT
            @estado_linea = estado,
            @sesion_estado_linea_id = sesion_linea_id
        FROM prod.estados_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE linea_id = @linea_id;

        IF @sesion_estado_linea_id <> @sesion_linea_id
            THROW 52509, 'La linea no corresponde a la sesion activa.', 1;

        IF @estado_linea NOT IN
           (N'PRODUCIENDO', N'SIN_OPERARIOS', N'PENDIENTE_NAV', N'BLOQUEADA')
            THROW 52510, 'El estado de la linea no admite finalizar la sustitucion.', 1;

        /*
        Bloquea primero los fichajes conocidos y despues paros y sustitucion,
        respetando el orden utilizado por el resto del paquete.
        */
        IF NOT EXISTS
        (
            SELECT 1
            FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
            WHERE fichaje_id = @fichaje_operario_id
              AND sesion_linea_id = @sesion_linea_id
              AND empleado_id = @operario_sustituido_id
              AND salida_utc IS NULL
        )
            THROW 52511, 'El fichaje del operario sustituido no esta abierto.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
            WHERE fichaje_id = @fichaje_supervisor_id
              AND sesion_linea_id = @sesion_linea_id
              AND empleado_id = @supervisor_sustituto_id
              AND salida_utc IS NULL
        )
            THROW 52512, 'El fichaje del supervisor sustituto no esta abierto.', 1;

        SELECT @paro_operario_id = paro_operario_id
        FROM prod.paros_operario WITH (UPDLOCK, HOLDLOCK)
        WHERE fichaje_id = @fichaje_operario_id
          AND fin_utc IS NULL;

        IF @paro_operario_id IS NULL
            THROW 52513, 'El operario sustituido ya no tiene un paro abierto.', 1;

        SELECT
            @inicio_sustitucion_utc = inicio_utc,
            @motivo_inicio = motivo
        FROM prod.sustituciones_capacidad WITH (UPDLOCK, HOLDLOCK)
        WHERE sustitucion_capacidad_id = @sustitucion_capacidad_id
          AND sesion_linea_id = @sesion_linea_id
          AND operario_sustituido_id = @operario_sustituido_id
          AND supervisor_sustituto_id = @supervisor_sustituto_id
          AND fichaje_operario_id = @fichaje_operario_id
          AND fichaje_supervisor_id = @fichaje_supervisor_id
          AND fin_utc IS NULL;

        IF @inicio_sustitucion_utc IS NULL
            THROW 52514, 'La sustitucion no esta activa o cambio durante la operacion.', 1;

        /* Revalida y bloquea al supervisor autorizador. */
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
            THROW 52515, 'El autorizador dejo de ser supervisor activo.', 1;

        SELECT @recursos_antes = COUNT(*)
        FROM prod.fichajes f WITH (UPDLOCK, HOLDLOCK)
        WHERE f.sesion_linea_id = @sesion_linea_id
          AND f.salida_utc IS NULL
          AND NOT EXISTS
          (
              SELECT 1
              FROM prod.paros_operario po WITH (UPDLOCK, HOLDLOCK)
              WHERE po.fichaje_id = f.fichaje_id
                AND po.fin_utc IS NULL
          );

        IF @recursos_antes <= 0
            THROW 52516, 'La sustitucion activa no aporta un recurso efectivo.', 1;

        SELECT @valor_anterior =
        (
            SELECT
                @operario_sustituido_id AS operario_sustituido_id,
                @supervisor_sustituto_id AS supervisor_sustituto_id,
                @fichaje_operario_id AS fichaje_operario_id,
                @fichaje_supervisor_id AS fichaje_supervisor_id,
                @inicio_sustitucion_utc AS inicio_utc,
                @motivo_inicio AS motivo,
                N'ACTIVA' AS estado
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        UPDATE prod.tramos_capacidad
        SET fin_utc = @ahora_utc,
            segundos_productivos =
                DATEDIFF(SECOND, inicio_utc, @ahora_utc)
        WHERE sesion_linea_id = @sesion_linea_id
          AND fin_utc IS NULL;

        UPDATE prod.sustituciones_capacidad
        SET fin_utc = @ahora_utc,
            estado = N'FINALIZADA'
        WHERE sustitucion_capacidad_id = @sustitucion_capacidad_id
          AND fin_utc IS NULL;

        IF @@ROWCOUNT <> 1
            THROW 52517, 'No se pudo finalizar la sustitucion activa.', 1;

        UPDATE prod.fichajes
        SET salida_utc = @ahora_utc,
            estado = N'CERRADO',
            cerrado_por_sistema = 1
        WHERE fichaje_id = @fichaje_supervisor_id
          AND salida_utc IS NULL;

        IF @@ROWCOUNT <> 1
            THROW 52518, 'No se pudo cerrar el fichaje del supervisor sustituto.', 1;

        SELECT @recursos_activos = COUNT(*)
        FROM prod.fichajes f WITH (UPDLOCK, HOLDLOCK)
        WHERE f.sesion_linea_id = @sesion_linea_id
          AND f.salida_utc IS NULL
          AND NOT EXISTS
          (
              SELECT 1
              FROM prod.paros_operario po WITH (UPDLOCK, HOLDLOCK)
              WHERE po.fichaje_id = f.fichaje_id
                AND po.fin_utc IS NULL
          );

        IF @recursos_activos <> @recursos_antes - 1
            THROW 52519, 'La finalizacion no retiro exactamente un recurso.', 1;

        IF @recursos_activos > 0
        BEGIN
            SET @capacidad =
                CONVERT(decimal(18,4),
                        (CONVERT(decimal(18,4), 60) / @tiempo_nav)
                        * @recursos_activos);

            INSERT prod.tramos_capacidad
            (
                sesion_linea_id, inicio_utc, recursos_activos,
                tiempo_nav_min_unidad, capacidad_teorica_hora,
                segundos_productivos, motivo_inicio
            )
            VALUES
            (
                @sesion_linea_id, @ahora_utc, @recursos_activos,
                @tiempo_nav, @capacidad,
                0, N'FIN_SUSTITUCION'
            );

            UPDATE prod.sesiones_linea
            SET estado = N'PRODUCIENDO'
            WHERE sesion_linea_id = @sesion_linea_id;

            IF @estado_linea IN (N'PRODUCIENDO', N'SIN_OPERARIOS')
                UPDATE prod.estados_linea
                SET estado = N'PRODUCIENDO',
                    motivo_bloqueo = NULL,
                    actualizado_utc = @ahora_utc
                WHERE linea_id = @linea_id
                  AND sesion_linea_id = @sesion_linea_id;
        END
        ELSE
        BEGIN
            UPDATE prod.sesiones_linea
            SET estado = N'SIN_OPERARIOS'
            WHERE sesion_linea_id = @sesion_linea_id;

            IF @estado_linea IN (N'PRODUCIENDO', N'SIN_OPERARIOS')
                UPDATE prod.estados_linea
                SET estado = N'SIN_OPERARIOS',
                    motivo_bloqueo = NULL,
                    actualizado_utc = @ahora_utc
                WHERE linea_id = @linea_id
                  AND sesion_linea_id = @sesion_linea_id;
        END;

        SELECT @valor_nuevo =
        (
            SELECT
                @ahora_utc AS fin_utc,
                N'FINALIZADA' AS estado,
                @motivo AS motivo_fin,
                @supervisor_id AS finalizada_por_supervisor_id,
                @recursos_activos AS recursos_activos
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC aud.registrar_evento
            @tipo_evento = N'SUSTITUCION_CAPACIDAD_FINALIZADA',
            @empleado_id = @supervisor_id,
            @rol_usado = N'SUPERVISOR',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'prod.sustituciones_capacidad',
            @entidad_id = @sustitucion_capacidad_id,
            @valor_anterior = @valor_anterior,
            @valor_nuevo = @valor_nuevo,
            @motivo = @motivo,
            @correlacion_id = @correlacion_id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        SET @recursos_activos = NULL;
        THROW;
    END CATCH;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NOT NULL
    GRANT EXECUTE ON OBJECT::prod.finalizar_sustitucion_capacidad TO mes_runtime;
GO
