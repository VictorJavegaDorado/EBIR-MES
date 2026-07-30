/*
Paquete 012C - Inicio supervisado de sustitucion de capacidad.
Estado: preparado para revision estatica; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.iniciar_sustitucion_capacidad
    @sesion_linea_id bigint,
    @operario_sustituido_id bigint,
    @supervisor_sustituto_id bigint,
    @motivo nvarchar(250),
    @correlacion_id uniqueidentifier,
    @sustitucion_capacidad_id bigint OUTPUT,
    @fichaje_supervisor_id bigint OUTPUT,
    @recursos_activos int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @sustitucion_capacidad_id = NULL;
    SET @fichaje_supervisor_id = NULL;
    SET @recursos_activos = NULL;
    SET @motivo = NULLIF(LTRIM(RTRIM(@motivo)), N'');

    IF @correlacion_id IS NULL
        THROW 52400, 'La correlacion es obligatoria.', 1;

    IF @motivo IS NULL
        THROW 52401, 'El motivo de la sustitucion es obligatorio.', 1;

    IF @operario_sustituido_id = @supervisor_sustituto_id
        THROW 52402, 'El operario y el supervisor deben ser distintos.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM seg.empleados e
        JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
        JOIN seg.roles r ON r.rol_id = er.rol_id
        WHERE e.empleado_id = @operario_sustituido_id
          AND e.activo_nav = 1
          AND e.activo_mes = 1
          AND e.anonimizado_utc IS NULL
          AND er.hasta_utc IS NULL
          AND r.codigo = N'OPERARIO'
          AND r.es_productivo = 1
          AND r.activo = 1
    )
        THROW 52403, 'El empleado sustituido no es un operario activo.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM seg.empleados e
        JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
        JOIN seg.roles r ON r.rol_id = er.rol_id
        WHERE e.empleado_id = @supervisor_sustituto_id
          AND e.activo_nav = 1
          AND e.activo_mes = 1
          AND e.anonimizado_utc IS NULL
          AND er.hasta_utc IS NULL
          AND r.codigo = N'SUPERVISOR'
          AND r.activo = 1
    )
        THROW 52404, 'La sustitucion requiere un supervisor activo.', 1;

    DECLARE
        @ahora_utc datetime2(3) = SYSUTCDATETIME(),
        @orden_id bigint,
        @linea_id bigint,
        @orden_bloqueada_id bigint,
        @sesion_orden_id bigint,
        @sesion_linea_bloqueada_id bigint,
        @estado_sesion nvarchar(30),
        @estado_linea nvarchar(30),
        @sesion_estado_linea_id bigint,
        @tiempo_nav decimal(12,1),
        @fichaje_operario_id bigint,
        @paro_operario_id bigint,
        @recursos_antes int,
        @capacidad decimal(18,4),
        @valor_nuevo nvarchar(max);

    /*
    Lectura inicial sin bloqueo para mantener el orden global:
    orden -> sesion -> linea -> fichajes -> paros -> sustituciones -> tramos.
    */
    SELECT
        @orden_id = orden_id,
        @linea_id = linea_id
    FROM prod.sesiones_linea
    WHERE sesion_linea_id = @sesion_linea_id;

    IF @orden_id IS NULL
        THROW 52405, 'Sesion no encontrada.', 1;

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
            THROW 52406, 'La orden no admite iniciar una sustitucion.', 1;

        SELECT
            @sesion_orden_id = orden_id,
            @sesion_linea_bloqueada_id = linea_id,
            @estado_sesion = estado
        FROM prod.sesiones_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND finalizada_utc IS NULL;

        IF @sesion_orden_id IS NULL
            THROW 52407, 'La sesion no esta activa.', 1;

        IF @sesion_orden_id <> @orden_id
           OR @sesion_linea_bloqueada_id <> @linea_id
            THROW 52408, 'La sesion cambio durante la operacion.', 1;

        IF @estado_sesion NOT IN (N'PRODUCIENDO', N'SIN_OPERARIOS')
            THROW 52409, 'El estado de la sesion no admite la sustitucion.', 1;

        SELECT
            @estado_linea = estado,
            @sesion_estado_linea_id = sesion_linea_id
        FROM prod.estados_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE linea_id = @linea_id;

        IF @sesion_estado_linea_id <> @sesion_linea_id
            THROW 52410, 'La linea no corresponde a la sesion activa.', 1;

        IF @estado_linea NOT IN
           (N'PRODUCIENDO', N'SIN_OPERARIOS', N'PENDIENTE_NAV', N'BLOQUEADA')
            THROW 52411, 'El estado de la linea no admite la sustitucion.', 1;

        SELECT @fichaje_operario_id = fichaje_id
        FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND linea_id = @linea_id
          AND empleado_id = @operario_sustituido_id
          AND salida_utc IS NULL;

        IF @fichaje_operario_id IS NULL
            THROW 52412, 'El operario no tiene un fichaje abierto en la sesion.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
            WHERE empleado_id = @supervisor_sustituto_id
              AND salida_utc IS NULL
        )
            THROW 52413, 'El supervisor ya tiene un fichaje productivo abierto.', 1;

        SELECT @paro_operario_id = paro_operario_id
        FROM prod.paros_operario WITH (UPDLOCK, HOLDLOCK)
        WHERE fichaje_id = @fichaje_operario_id
          AND fin_utc IS NULL;

        IF @paro_operario_id IS NULL
            THROW 52414, 'La sustitucion requiere un paro abierto del operario.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.sustituciones_capacidad WITH (UPDLOCK, HOLDLOCK)
            WHERE fin_utc IS NULL
              AND
              (
                  operario_sustituido_id = @operario_sustituido_id
                  OR supervisor_sustituto_id = @supervisor_sustituto_id
              )
        )
            THROW 52415, 'El operario o el supervisor ya participa en otra sustitucion.', 1;

        /* Revalida y bloquea ambas identidades dentro de la transaccion. */
        IF NOT EXISTS
        (
            SELECT 1
            FROM seg.empleados e WITH (UPDLOCK, HOLDLOCK)
            JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
            JOIN seg.roles r ON r.rol_id = er.rol_id
            WHERE e.empleado_id = @operario_sustituido_id
              AND e.activo_nav = 1
              AND e.activo_mes = 1
              AND e.anonimizado_utc IS NULL
              AND er.hasta_utc IS NULL
              AND r.codigo = N'OPERARIO'
              AND r.es_productivo = 1
              AND r.activo = 1
        )
            THROW 52416, 'El empleado sustituido dejo de ser operario activo.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM seg.empleados e WITH (UPDLOCK, HOLDLOCK)
            JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
            JOIN seg.roles r ON r.rol_id = er.rol_id
            WHERE e.empleado_id = @supervisor_sustituto_id
              AND e.activo_nav = 1
              AND e.activo_mes = 1
              AND e.anonimizado_utc IS NULL
              AND er.hasta_utc IS NULL
              AND r.codigo = N'SUPERVISOR'
              AND r.activo = 1
        )
            THROW 52417, 'El sustituto dejo de ser supervisor activo.', 1;

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

        UPDATE prod.tramos_capacidad
        SET fin_utc = @ahora_utc,
            segundos_productivos =
                DATEDIFF(SECOND, inicio_utc, @ahora_utc)
        WHERE sesion_linea_id = @sesion_linea_id
          AND fin_utc IS NULL;

        INSERT prod.fichajes
        (
            sesion_linea_id, linea_id, empleado_id,
            entrada_utc, estado, cerrado_por_sistema
        )
        VALUES
        (
            @sesion_linea_id, @linea_id, @supervisor_sustituto_id,
            @ahora_utc, N'ABIERTO', 0
        );

        SET @fichaje_supervisor_id = SCOPE_IDENTITY();

        INSERT prod.sustituciones_capacidad
        (
            sesion_linea_id, operario_sustituido_id,
            supervisor_sustituto_id, fichaje_operario_id,
            fichaje_supervisor_id, inicio_utc, estado, motivo
        )
        VALUES
        (
            @sesion_linea_id, @operario_sustituido_id,
            @supervisor_sustituto_id, @fichaje_operario_id,
            @fichaje_supervisor_id, @ahora_utc, N'ACTIVA', @motivo
        );

        SET @sustitucion_capacidad_id = SCOPE_IDENTITY();

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

        IF @recursos_activos <> @recursos_antes + 1
            THROW 52418, 'La sustitucion no restauro exactamente un recurso.', 1;

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
            0, N'INICIO_SUSTITUCION'
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

        SELECT @valor_nuevo =
        (
            SELECT
                @operario_sustituido_id AS operario_sustituido_id,
                @supervisor_sustituto_id AS supervisor_sustituto_id,
                @fichaje_operario_id AS fichaje_operario_id,
                @fichaje_supervisor_id AS fichaje_supervisor_id,
                @paro_operario_id AS paro_operario_id,
                @ahora_utc AS inicio_utc,
                @recursos_activos AS recursos_activos
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC aud.registrar_evento
            @tipo_evento = N'SUSTITUCION_CAPACIDAD_INICIADA',
            @empleado_id = @supervisor_sustituto_id,
            @rol_usado = N'SUPERVISOR',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'prod.sustituciones_capacidad',
            @entidad_id = @sustitucion_capacidad_id,
            @valor_anterior = NULL,
            @valor_nuevo = @valor_nuevo,
            @motivo = @motivo,
            @correlacion_id = @correlacion_id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        SET @sustitucion_capacidad_id = NULL;
        SET @fichaje_supervisor_id = NULL;
        SET @recursos_activos = NULL;
        THROW;
    END CATCH;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NOT NULL
    GRANT EXECUTE ON OBJECT::prod.iniciar_sustitucion_capacidad TO mes_runtime;
GO
