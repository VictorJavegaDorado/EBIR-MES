/*
Paquete 011C - Salida productiva y recalculo de capacidad.
Estado: preparado para revision; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.registrar_salida_productiva
    @sesion_linea_id bigint,
    @empleado_id bigint,
    @correlacion_id uniqueidentifier,
    @recursos_activos int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @recursos_activos = NULL;

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
        @capacidad decimal(18,4);

    /* Mantiene el mismo orden global de bloqueos que la entrada:
       orden -> sesion -> linea -> fichajes -> tramos. */
    SELECT
        @orden_id = orden_id,
        @linea_id = linea_id
    FROM prod.sesiones_linea
    WHERE sesion_linea_id = @sesion_linea_id;

    IF @orden_id IS NULL
        THROW 51900, 'Sesion no encontrada.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @orden_bloqueada_id = orden_id,
            @tiempo_nav = tiempo_ejecucion_nav_min
        FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
        WHERE orden_id = @orden_id;

        IF @orden_bloqueada_id IS NULL
            THROW 51901, 'Orden no encontrada.', 1;

        SELECT
            @sesion_orden_id = orden_id,
            @sesion_linea_bloqueada_id = linea_id,
            @estado_sesion = estado
        FROM prod.sesiones_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND finalizada_utc IS NULL;

        IF @sesion_orden_id IS NULL
            THROW 51902, 'La sesion no esta activa.', 1;

        IF @sesion_orden_id <> @orden_id
           OR @sesion_linea_bloqueada_id <> @linea_id
            THROW 51903, 'La sesion cambio durante la operacion.', 1;

        IF @estado_sesion NOT IN (N'PRODUCIENDO', N'SIN_OPERARIOS', N'BLOQUEADA')
            THROW 51904, 'El estado de la sesion no admite salida productiva.', 1;

        SELECT
            @estado_linea = estado,
            @sesion_estado_linea_id = sesion_linea_id
        FROM prod.estados_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE linea_id = @linea_id;

        IF @sesion_estado_linea_id <> @sesion_linea_id
            THROW 51905, 'La linea no corresponde a la sesion activa.', 1;

        IF @estado_linea NOT IN
           (N'PRODUCIENDO', N'SIN_OPERARIOS', N'PENDIENTE_NAV', N'BLOQUEADA')
            THROW 51906, 'La linea no admite una salida productiva.', 1;

        SELECT @fichaje_id = fichaje_id
        FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND empleado_id = @empleado_id
          AND salida_utc IS NULL;

        IF @fichaje_id IS NULL
            THROW 51907, 'No existe un fichaje productivo abierto para el empleado.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.paros_operario WITH (UPDLOCK, HOLDLOCK)
            WHERE fichaje_id = @fichaje_id
              AND fin_utc IS NULL
        )
            THROW 51908, 'El empleado tiene un paro abierto; debe resolverse antes de salir.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.sustituciones_capacidad WITH (UPDLOCK, HOLDLOCK)
            WHERE fin_utc IS NULL
              AND
              (
                  operario_sustituido_id = @empleado_id
                  OR supervisor_sustituto_id = @empleado_id
              )
        )
            THROW 51909, 'El empleado participa en una sustitucion activa.', 1;

        UPDATE prod.fichajes
        SET salida_utc = @ahora_utc,
            estado = N'CERRADO'
        WHERE fichaje_id = @fichaje_id;

        SELECT @recursos_activos = COUNT(*)
        FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND salida_utc IS NULL;

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
                0, N'SALIDA_RECURSO'
            );

            UPDATE prod.sesiones_linea
            SET estado = N'PRODUCIENDO'
            WHERE sesion_linea_id = @sesion_linea_id;

            IF @estado_linea NOT IN (N'PENDIENTE_NAV', N'BLOQUEADA')
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

            IF @estado_linea NOT IN (N'PENDIENTE_NAV', N'BLOQUEADA')
                UPDATE prod.estados_linea
                SET estado = N'SIN_OPERARIOS',
                    motivo_bloqueo = NULL,
                    actualizado_utc = @ahora_utc
                WHERE linea_id = @linea_id
                  AND sesion_linea_id = @sesion_linea_id;
        END;

        EXEC aud.registrar_evento
            @tipo_evento = N'FICHAJE_SALIDA_PRODUCTIVA',
            @empleado_id = @empleado_id,
            @rol_usado = N'OPERARIO',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'prod.fichajes',
            @entidad_id = @fichaje_id,
            @valor_anterior = NULL,
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
    GRANT EXECUTE ON OBJECT::prod.registrar_salida_productiva TO mes_runtime;
GO
