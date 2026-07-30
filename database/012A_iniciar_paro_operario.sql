/*
Paquete 012A - Inicio contextual de paro individual.
Estado: preparado para revision estatica; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.iniciar_paro_operario
    @sesion_linea_id bigint,
    @empleado_id bigint,
    @motivo nvarchar(30),
    @correlacion_id uniqueidentifier,
    @paro_operario_id bigint OUTPUT,
    @recursos_activos int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @paro_operario_id = NULL;
    SET @recursos_activos = NULL;
    SET @motivo = UPPER(LTRIM(RTRIM(@motivo)));

    IF @correlacion_id IS NULL
        THROW 52200, 'La correlacion es obligatoria.', 1;

    IF @motivo IS NULL
       OR @motivo NOT IN (N'WC', N'PAUSA_CALOR')
        THROW 52201, 'El motivo debe ser WC o PAUSA_CALOR.', 1;

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
        THROW 52202, 'El paro individual requiere un operario activo.', 1;

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
        @capacidad decimal(18,4),
        @motivo_tramo nvarchar(50),
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
        THROW 52203, 'Sesion no encontrada.', 1;

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
            THROW 52204, 'La orden no admite un paro individual.', 1;

        SELECT
            @sesion_orden_id = orden_id,
            @sesion_linea_bloqueada_id = linea_id,
            @estado_sesion = estado
        FROM prod.sesiones_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND finalizada_utc IS NULL;

        IF @sesion_orden_id IS NULL
            THROW 52205, 'La sesion no esta activa.', 1;

        IF @sesion_orden_id <> @orden_id
           OR @sesion_linea_bloqueada_id <> @linea_id
            THROW 52206, 'La sesion cambio durante la operacion.', 1;

        IF @estado_sesion <> N'PRODUCIENDO'
            THROW 52207, 'El estado de la sesion no admite iniciar el paro.', 1;

        SELECT
            @estado_linea = estado,
            @sesion_estado_linea_id = sesion_linea_id
        FROM prod.estados_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE linea_id = @linea_id;

        IF @sesion_estado_linea_id <> @sesion_linea_id
            THROW 52208, 'La linea no corresponde a la sesion activa.', 1;

        IF @estado_linea NOT IN
           (N'PRODUCIENDO', N'PENDIENTE_NAV', N'BLOQUEADA')
            THROW 52209, 'El estado de la linea no admite iniciar el paro.', 1;

        SELECT @fichaje_id = fichaje_id
        FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND linea_id = @linea_id
          AND empleado_id = @empleado_id
          AND salida_utc IS NULL;

        IF @fichaje_id IS NULL
            THROW 52210, 'El operario no tiene un fichaje abierto en la sesion.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.paros_operario WITH (UPDLOCK, HOLDLOCK)
            WHERE fichaje_id = @fichaje_id
              AND fin_utc IS NULL
        )
            THROW 52211, 'El fichaje ya tiene un paro individual abierto.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.sustituciones_capacidad WITH (UPDLOCK, HOLDLOCK)
            WHERE supervisor_sustituto_id = @empleado_id
              AND fin_utc IS NULL
        )
            THROW 52212, 'El empleado actua como supervisor sustituto.', 1;

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
            THROW 52213, 'El empleado dejo de ser un operario activo.', 1;

        INSERT prod.paros_operario
        (
            fichaje_id, motivo, inicio_utc, estado
        )
        VALUES
        (
            @fichaje_id, @motivo, @ahora_utc, N'ABIERTO'
        );

        SET @paro_operario_id = SCOPE_IDENTITY();

        /*
        La definicion comun excluye cualquier fichaje con paro abierto.
        El bloqueo sobre fichajes y paros estabiliza el recuento.
        */
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

        UPDATE prod.tramos_capacidad
        SET fin_utc = @ahora_utc,
            segundos_productivos =
                DATEDIFF(SECOND, inicio_utc, @ahora_utc)
        WHERE sesion_linea_id = @sesion_linea_id
          AND fin_utc IS NULL;

        IF @recursos_activos > 0
        BEGIN
            SET @capacidad =
                CONVERT(decimal(18,4),
                        (CONVERT(decimal(18,4), 60) / @tiempo_nav)
                        * @recursos_activos);

            SET @motivo_tramo =
                CASE WHEN @motivo = N'WC'
                     THEN N'PARO_WC'
                     ELSE N'PARO_PAUSA_CALOR' END;

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

            /*
            PENDIENTE_NAV y BLOQUEADA se conservan en la linea. La sesion
            continua productiva mientras exista al menos un recurso efectivo.
            */
            UPDATE prod.sesiones_linea
            SET estado = N'PRODUCIENDO'
            WHERE sesion_linea_id = @sesion_linea_id;

            IF @estado_linea = N'PRODUCIENDO'
                UPDATE prod.estados_linea
                SET actualizado_utc = @ahora_utc
                WHERE linea_id = @linea_id
                  AND sesion_linea_id = @sesion_linea_id;
        END
        ELSE
        BEGIN
            UPDATE prod.sesiones_linea
            SET estado = N'SIN_OPERARIOS'
            WHERE sesion_linea_id = @sesion_linea_id;

            IF @estado_linea = N'PRODUCIENDO'
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
                @fichaje_id AS fichaje_id,
                @motivo AS motivo,
                @ahora_utc AS inicio_utc,
                @recursos_activos AS recursos_activos
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC aud.registrar_evento
            @tipo_evento = N'PARO_OPERARIO_INICIADO',
            @empleado_id = @empleado_id,
            @rol_usado = N'OPERARIO',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'prod.paros_operario',
            @entidad_id = @paro_operario_id,
            @valor_anterior = NULL,
            @valor_nuevo = @valor_nuevo,
            @motivo = @motivo,
            @correlacion_id = @correlacion_id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        SET @paro_operario_id = NULL;
        SET @recursos_activos = NULL;
        THROW;
    END CATCH;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NOT NULL
    GRANT EXECUTE ON OBJECT::prod.iniciar_paro_operario TO mes_runtime;
GO
