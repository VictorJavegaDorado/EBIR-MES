/*
Paquete 012G - Refuerzo de entrada productiva con recursos efectivos.
Estado: preparado para revision estatica; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.registrar_entrada_productiva
    @sesion_linea_id bigint,
    @empleado_id bigint,
    @correlacion_id uniqueidentifier,
    @fichaje_id bigint OUTPUT,
    @reserva_palet_id bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @fichaje_id = NULL;
    SET @reserva_palet_id = NULL;

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
          AND NOT EXISTS
          (
              SELECT 1
              FROM seg.empleados_roles ers
              JOIN seg.roles rs ON rs.rol_id = ers.rol_id
              WHERE ers.empleado_id = e.empleado_id
                AND ers.hasta_utc IS NULL
                AND rs.codigo = N'SUPERVISOR'
                AND rs.activo = 1
          )
    )
        THROW 51800, 'La entrada productiva ordinaria requiere operario activo.', 1;

    DECLARE
        @ahora_utc datetime2(3) = SYSUTCDATETIME(),
        @orden_id bigint,
        @linea_id bigint,
        @orden_bloqueada_id bigint,
        @sesion_orden_id bigint,
        @sesion_linea_bloqueada_id bigint,
        @estado_sesion nvarchar(30),
        @sesion_iniciada_utc datetime2(3),
        @es_primer_inicio bit,
        @estado_linea nvarchar(30),
        @sesion_estado_linea_id bigint,
        @tiempo_nav decimal(12,1),
        @objetivo int,
        @buenas int,
        @reservadas int,
        @unidades_formato int,
        @bloqueo_paros int,
        @recursos_antes int,
        @recursos_despues int,
        @capacidad decimal(18,4),
        @cantidad_primera_reserva int;

    /* Lectura inicial sin bloqueo para establecer el orden global de bloqueos:
       orden -> sesion -> linea -> fichajes -> tramos. */
    SELECT
        @orden_id = orden_id,
        @linea_id = linea_id
    FROM prod.sesiones_linea
    WHERE sesion_linea_id = @sesion_linea_id;

    IF @orden_id IS NULL
        THROW 51801, 'Sesion no encontrada.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @orden_bloqueada_id = orden_id,
            @tiempo_nav = tiempo_ejecucion_nav_min,
            @objetivo = cantidad_objetivo,
            @buenas = cantidad_buena_acumulada,
            @reservadas = cantidad_reservada_activa
        FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
        WHERE orden_id = @orden_id
          AND estado IN (N'IMPORTADA', N'ABIERTA', N'PICO_PENDIENTE');

        IF @orden_bloqueada_id IS NULL
            THROW 51802, 'La orden no admite entrada productiva.', 1;

        SELECT
            @sesion_orden_id = s.orden_id,
            @sesion_linea_bloqueada_id = s.linea_id,
            @estado_sesion = s.estado,
            @sesion_iniciada_utc = s.iniciada_utc,
            @unidades_formato = f.unidades_por_palet
        FROM prod.sesiones_linea s WITH (UPDLOCK, HOLDLOCK)
        JOIN prod.formatos_palet_orden f
          ON f.formato_palet_orden_id = s.formato_palet_orden_id
         AND f.orden_id = s.orden_id
         AND f.activo = 1
        WHERE s.sesion_linea_id = @sesion_linea_id
          AND s.finalizada_utc IS NULL;

        IF @sesion_orden_id IS NULL
            THROW 51803, 'La sesion no esta activa o su formato no esta disponible.', 1;

        IF @sesion_orden_id <> @orden_id
           OR @sesion_linea_bloqueada_id <> @linea_id
            THROW 51804, 'La sesion cambio durante la operacion.', 1;

        IF @estado_sesion NOT IN (N'CARGADA', N'PRODUCIENDO', N'SIN_OPERARIOS')
            THROW 51805, 'El estado de la sesion no admite entrada productiva.', 1;

        SELECT
            @estado_linea = estado,
            @sesion_estado_linea_id = sesion_linea_id
        FROM prod.estados_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE linea_id = @linea_id;

        IF @sesion_estado_linea_id <> @sesion_linea_id
            THROW 51806, 'La linea no corresponde a la sesion activa.', 1;

        IF @estado_linea NOT IN (N'ORDEN_CARGADA', N'PRODUCIENDO', N'SIN_OPERARIOS')
            THROW 51807, 'La linea no admite una entrada productiva.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
            WHERE empleado_id = @empleado_id
              AND salida_utc IS NULL
        )
            THROW 51808, 'El empleado ya tiene un fichaje productivo abierto.', 1;

        /* Revalida y bloquea la identidad operativa dentro de la transaccion. */
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
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM seg.empleados_roles ers
                  JOIN seg.roles rs ON rs.rol_id = ers.rol_id
                  WHERE ers.empleado_id = e.empleado_id
                    AND ers.hasta_utc IS NULL
                    AND rs.codigo = N'SUPERVISOR'
                    AND rs.activo = 1
              )
        )
            THROW 51810, 'El empleado dejo de ser un operario ordinario activo.', 1;

        /*
        Estabiliza los paros de todos los fichajes de la sesion antes de
        consumir la definicion comun de recursos efectivos.
        */
        SELECT @bloqueo_paros = COUNT(*)
        FROM prod.paros_operario po WITH (UPDLOCK, HOLDLOCK)
        JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
        WHERE f.sesion_linea_id = @sesion_linea_id
          AND po.fin_utc IS NULL;

        SELECT @recursos_antes = recursos_activos
        FROM prod.recursos_efectivos_sesion(@sesion_linea_id);

        SET @es_primer_inicio =
            CASE WHEN @sesion_iniciada_utc IS NULL THEN 1 ELSE 0 END;

        IF @es_primer_inicio = 1
        BEGIN
            SET @cantidad_primera_reserva =
                CASE
                    WHEN @objetivo - @buenas - @reservadas <= 0 THEN 0
                    WHEN @objetivo - @buenas - @reservadas < @unidades_formato
                        THEN @objetivo - @buenas - @reservadas
                    ELSE @unidades_formato
                END;

            IF @cantidad_primera_reserva <= 0
                THROW 51809, 'No queda pendiente global disponible para iniciar produccion.', 1;
        END;

        INSERT prod.fichajes
        (
            sesion_linea_id, linea_id, empleado_id,
            entrada_utc, estado, cerrado_por_sistema
        )
        VALUES
        (
            @sesion_linea_id, @linea_id, @empleado_id,
            @ahora_utc, N'ABIERTO', 0
        );

        SET @fichaje_id = SCOPE_IDENTITY();
        SET @recursos_despues = @recursos_antes + 1;

        UPDATE prod.tramos_capacidad
        SET fin_utc = @ahora_utc,
            segundos_productivos =
                DATEDIFF(SECOND, inicio_utc, @ahora_utc)
        WHERE sesion_linea_id = @sesion_linea_id
          AND fin_utc IS NULL;

        SET @capacidad =
            CONVERT(decimal(18,4),
                    (CONVERT(decimal(18,4), 60) / @tiempo_nav)
                    * @recursos_despues);

        INSERT prod.tramos_capacidad
        (
            sesion_linea_id, inicio_utc, recursos_activos,
            tiempo_nav_min_unidad, capacidad_teorica_hora,
            segundos_productivos, motivo_inicio
        )
        VALUES
        (
            @sesion_linea_id, @ahora_utc, @recursos_despues,
            @tiempo_nav, @capacidad,
            0, CASE WHEN @recursos_antes = 0
                    THEN CASE WHEN @es_primer_inicio = 1
                              THEN N'PRIMER_RECURSO'
                              ELSE N'RETORNO_RECURSO' END
                    ELSE N'ENTRADA_RECURSO' END
        );

        UPDATE prod.sesiones_linea
        SET estado = N'PRODUCIENDO',
            iniciada_utc = COALESCE(iniciada_utc, @ahora_utc)
        WHERE sesion_linea_id = @sesion_linea_id;

        UPDATE prod.estados_linea
        SET estado = N'PRODUCIENDO',
            motivo_bloqueo = NULL,
            actualizado_utc = @ahora_utc
        WHERE linea_id = @linea_id
          AND sesion_linea_id = @sesion_linea_id;

        IF @es_primer_inicio = 1
            EXEC prod.reservar_palet
                @orden_id = @orden_id,
                @sesion_linea_id = @sesion_linea_id,
                @cantidad = @cantidad_primera_reserva,
                @empleado_id = @empleado_id,
                @correlacion_id = @correlacion_id,
                @reserva_palet_id = @reserva_palet_id OUTPUT;

        EXEC aud.registrar_evento
            @tipo_evento = N'FICHAJE_ENTRADA_PRODUCTIVA',
            @empleado_id = @empleado_id,
            @rol_usado = N'OPERARIO',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'prod.fichajes',
            @entidad_id = @fichaje_id,
            @valor_nuevo = NULL,
            @motivo = NULL,
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
    GRANT EXECUTE ON OBJECT::prod.registrar_entrada_productiva TO mes_runtime;
GO
