/*
Paquete 012B - Retorno de paro individual y fin automatico de sustitucion.
Estado: preparado para revision estatica; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.finalizar_paro_operario
    @sesion_linea_id bigint,
    @empleado_id bigint,
    @correlacion_id uniqueidentifier,
    @paro_operario_id bigint OUTPUT,
    @sustitucion_finalizada_id bigint OUTPUT,
    @recursos_activos int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @paro_operario_id = NULL;
    SET @sustitucion_finalizada_id = NULL;
    SET @recursos_activos = NULL;

    IF @correlacion_id IS NULL
        THROW 52300, 'La correlacion es obligatoria.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM seg.empleados e
        JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
        JOIN seg.roles r ON r.rol_id = er.rol_id
        WHERE e.empleado_id = @empleado_id
          AND e.activo_nav = 1
          AND e.activo_mes = 1
          AND e.anonimizado_utc IS NULL
          AND er.hasta_utc IS NULL
          AND r.codigo = N'OPERARIO'
          AND r.es_productivo = 1
          AND r.activo = 1
    )
        THROW 52301, 'El retorno requiere un operario activo.', 1;

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
        @fichaje_id bigint,
        @motivo nvarchar(30),
        @sustitucion_sesion_id bigint,
        @fichaje_operario_sustitucion_id bigint,
        @fichaje_supervisor_id bigint,
        @supervisor_sustituto_id bigint,
        @capacidad decimal(18,4),
        @motivo_tramo nvarchar(50),
        @valor_anterior nvarchar(max),
        @valor_nuevo nvarchar(max),
        @valor_sustitucion nvarchar(max);

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
        THROW 52302, 'Sesion no encontrada.', 1;

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
            THROW 52303, 'La orden no admite el retorno del paro.', 1;

        SELECT
            @sesion_orden_id = orden_id,
            @sesion_linea_bloqueada_id = linea_id,
            @estado_sesion = estado
        FROM prod.sesiones_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND finalizada_utc IS NULL;

        IF @sesion_orden_id IS NULL
            THROW 52304, 'La sesion no esta activa.', 1;

        IF @sesion_orden_id <> @orden_id
           OR @sesion_linea_bloqueada_id <> @linea_id
            THROW 52305, 'La sesion cambio durante la operacion.', 1;

        IF @estado_sesion NOT IN (N'PRODUCIENDO', N'SIN_OPERARIOS')
            THROW 52306, 'El estado de la sesion no admite el retorno.', 1;

        SELECT
            @estado_linea = estado,
            @sesion_estado_linea_id = sesion_linea_id
        FROM prod.estados_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE linea_id = @linea_id;

        IF @sesion_estado_linea_id <> @sesion_linea_id
            THROW 52307, 'La linea no corresponde a la sesion activa.', 1;

        IF @estado_linea NOT IN
           (N'PRODUCIENDO', N'SIN_OPERARIOS', N'PENDIENTE_NAV', N'BLOQUEADA')
            THROW 52308, 'El estado de la linea no admite el retorno.', 1;

        SELECT @fichaje_id = fichaje_id
        FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND linea_id = @linea_id
          AND empleado_id = @empleado_id
          AND salida_utc IS NULL;

        IF @fichaje_id IS NULL
            THROW 52309, 'El operario no tiene un fichaje abierto en la sesion.', 1;

        SELECT
            @paro_operario_id = paro_operario_id,
            @motivo = motivo
        FROM prod.paros_operario WITH (UPDLOCK, HOLDLOCK)
        WHERE fichaje_id = @fichaje_id
          AND fin_utc IS NULL;

        IF @paro_operario_id IS NULL
            THROW 52310, 'El operario no tiene un paro individual abierto.', 1;

        SELECT
            @sustitucion_finalizada_id = sustitucion_capacidad_id,
            @sustitucion_sesion_id = sesion_linea_id,
            @fichaje_operario_sustitucion_id = fichaje_operario_id,
            @fichaje_supervisor_id = fichaje_supervisor_id,
            @supervisor_sustituto_id = supervisor_sustituto_id
        FROM prod.sustituciones_capacidad WITH (UPDLOCK, HOLDLOCK)
        WHERE operario_sustituido_id = @empleado_id
          AND fin_utc IS NULL;

        IF @sustitucion_finalizada_id IS NOT NULL
           AND
           (
               @sustitucion_sesion_id <> @sesion_linea_id
               OR @fichaje_operario_sustitucion_id <> @fichaje_id
           )
            THROW 52311, 'La sustitucion activa no corresponde al paro actual.', 1;

        IF @sustitucion_finalizada_id IS NOT NULL
           AND NOT EXISTS
           (
               SELECT 1
               FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
               WHERE fichaje_id = @fichaje_supervisor_id
                 AND sesion_linea_id = @sesion_linea_id
                 AND empleado_id = @supervisor_sustituto_id
                 AND salida_utc IS NULL
           )
            THROW 52312, 'El fichaje del supervisor sustituto no esta abierto.', 1;

        /* Revalida y bloquea el operario dentro de la transaccion. */
        IF NOT EXISTS
        (
            SELECT 1
            FROM seg.empleados e WITH (UPDLOCK, HOLDLOCK)
            JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
            JOIN seg.roles r ON r.rol_id = er.rol_id
            WHERE e.empleado_id = @empleado_id
              AND e.activo_nav = 1
              AND e.activo_mes = 1
              AND e.anonimizado_utc IS NULL
              AND er.hasta_utc IS NULL
              AND r.codigo = N'OPERARIO'
              AND r.es_productivo = 1
              AND r.activo = 1
        )
            THROW 52313, 'El empleado dejo de ser un operario activo.', 1;

        SELECT @valor_anterior =
        (
            SELECT
                @fichaje_id AS fichaje_id,
                @motivo AS motivo,
                po.inicio_utc AS inicio_utc,
                po.estado AS estado
            FROM prod.paros_operario po
            WHERE po.paro_operario_id = @paro_operario_id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        UPDATE prod.tramos_capacidad
        SET fin_utc = @ahora_utc,
            segundos_productivos =
                DATEDIFF(SECOND, inicio_utc, @ahora_utc)
        WHERE sesion_linea_id = @sesion_linea_id
          AND fin_utc IS NULL;

        UPDATE prod.paros_operario
        SET fin_utc = @ahora_utc,
            estado = N'CERRADO'
        WHERE paro_operario_id = @paro_operario_id
          AND fin_utc IS NULL;

        IF @@ROWCOUNT <> 1
            THROW 52314, 'El paro cambio durante la operacion.', 1;

        IF @sustitucion_finalizada_id IS NOT NULL
        BEGIN
            UPDATE prod.sustituciones_capacidad
            SET fin_utc = @ahora_utc,
                estado = N'FINALIZADA'
            WHERE sustitucion_capacidad_id = @sustitucion_finalizada_id
              AND fin_utc IS NULL;

            IF @@ROWCOUNT <> 1
                THROW 52315, 'La sustitucion cambio durante la operacion.', 1;

            UPDATE prod.fichajes
            SET salida_utc = @ahora_utc,
                estado = N'CERRADO',
                cerrado_por_sistema = 1
            WHERE fichaje_id = @fichaje_supervisor_id
              AND salida_utc IS NULL;

            IF @@ROWCOUNT <> 1
                THROW 52316, 'No se pudo cerrar el fichaje del sustituto.', 1;

            SELECT @valor_sustitucion =
            (
                SELECT
                    @empleado_id AS operario_sustituido_id,
                    @supervisor_sustituto_id AS supervisor_sustituto_id,
                    @fichaje_supervisor_id AS fichaje_supervisor_id,
                    @ahora_utc AS fin_utc,
                    N'RETORNO_OPERARIO' AS motivo_fin
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            EXEC aud.registrar_evento
                @tipo_evento = N'SUSTITUCION_CAPACIDAD_FINALIZADA_AUTO',
                @empleado_id = @empleado_id,
                @rol_usado = N'OPERARIO',
                @linea_id = @linea_id,
                @orden_id = @orden_id,
                @sesion_linea_id = @sesion_linea_id,
                @entidad = N'prod.sustituciones_capacidad',
                @entidad_id = @sustitucion_finalizada_id,
                @valor_anterior = NULL,
                @valor_nuevo = @valor_sustitucion,
                @motivo = N'RETORNO_OPERARIO',
                @correlacion_id = @correlacion_id;
        END;

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

        IF @recursos_activos <= 0
            THROW 52317, 'El retorno no produjo ningun recurso efectivo.', 1;

        SET @capacidad =
            CONVERT(decimal(18,4),
                    (CONVERT(decimal(18,4), 60) / @tiempo_nav)
                    * @recursos_activos);

        SET @motivo_tramo =
            CASE WHEN @motivo = N'WC'
                 THEN N'RETORNO_WC'
                 ELSE N'RETORNO_PAUSA_CALOR' END;

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
            0, @motivo_tramo
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
                @fichaje_id AS fichaje_id,
                @motivo AS motivo,
                @ahora_utc AS fin_utc,
                @recursos_activos AS recursos_activos,
                @sustitucion_finalizada_id AS sustitucion_finalizada_id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC aud.registrar_evento
            @tipo_evento = N'PARO_OPERARIO_FINALIZADO',
            @empleado_id = @empleado_id,
            @rol_usado = N'OPERARIO',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'prod.paros_operario',
            @entidad_id = @paro_operario_id,
            @valor_anterior = @valor_anterior,
            @valor_nuevo = @valor_nuevo,
            @motivo = @motivo,
            @correlacion_id = @correlacion_id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        SET @paro_operario_id = NULL;
        SET @sustitucion_finalizada_id = NULL;
        SET @recursos_activos = NULL;
        THROW;
    END CATCH;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NOT NULL
    GRANT EXECUTE ON OBJECT::prod.finalizar_paro_operario TO mes_runtime;
GO
