SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id bigint,
    @estado_nuevo nvarchar(20),
    @empleado_id bigint,
    @comentario nvarchar(500) = NULL,
    @correlacion_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @estado_nuevo = UPPER(NULLIF(LTRIM(RTRIM(@estado_nuevo)), N''));
    SET @comentario = NULLIF(LTRIM(RTRIM(@comentario)), N'');

    IF @solicitud_id IS NULL
        THROW 55300, 'La solicitud es obligatoria.', 1;

    IF @estado_nuevo IS NULL
       OR @estado_nuevo NOT IN
          (N'ACEPTADA', N'EN_CAMINO', N'ENTREGADA', N'RECHAZADA', N'CANCELADA')
        THROW 55301, 'El estado destino no es valido.', 1;

    IF @empleado_id IS NULL
        THROW 55302, 'El aprovisionador es obligatorio.', 1;

    IF @estado_nuevo IN (N'RECHAZADA', N'CANCELADA')
       AND @comentario IS NULL
        THROW 55303, 'El rechazo o la cancelacion requieren motivo.', 1;

    IF @correlacion_id IS NULL
        THROW 55304, 'La correlacion es obligatoria.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @resultado_bloqueo int,
            @recurso_bloqueo nvarchar(255),
            @evento_existente_id bigint,
            @evento_existente_tipo nvarchar(80),
            @evento_existente_empleado_id bigint,
            @evento_existente_motivo nvarchar(1000),
            @orden_id bigint,
            @linea_id bigint,
            @sesion_linea_id bigint,
            @componente_orden_id bigint,
            @cantidad_solicitada int,
            @estado_anterior nvarchar(20),
            @asignada_a_empleado_id bigint,
            @estado_permitido bit,
            @tipo_evento nvarchar(80),
            @fecha_utc datetime2(3),
            @valor_anterior nvarchar(max),
            @valor_nuevo nvarchar(max);

        SET @recurso_bloqueo =
            CONCAT(N'MES:CORRELACION:', CONVERT(nvarchar(36), @correlacion_id));

        EXEC @resultado_bloqueo = sys.sp_getapplock
            @Resource = @recurso_bloqueo,
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000,
            @DbPrincipal = N'public';

        IF @resultado_bloqueo < 0
            THROW 55305, 'No se pudo obtener el bloqueo de idempotencia.', 1;

        SELECT TOP (1)
            @evento_existente_id = entidad_id,
            @evento_existente_tipo = tipo_evento,
            @evento_existente_empleado_id = empleado_id,
            @evento_existente_motivo = motivo
        FROM aud.eventos WITH (UPDLOCK, HOLDLOCK)
        WHERE correlacion_id = @correlacion_id
        ORDER BY evento_auditoria_id;

        SET @tipo_evento =
            CASE @estado_nuevo
                WHEN N'ACEPTADA' THEN N'REAPROVISIONAMIENTO_ACEPTADO'
                WHEN N'EN_CAMINO' THEN N'REAPROVISIONAMIENTO_EN_CAMINO'
                WHEN N'ENTREGADA' THEN N'REAPROVISIONAMIENTO_ENTREGADO'
                WHEN N'RECHAZADA' THEN N'REAPROVISIONAMIENTO_RECHAZADO'
                WHEN N'CANCELADA' THEN N'REAPROVISIONAMIENTO_CANCELADO'
            END;

        IF @evento_existente_tipo IS NOT NULL
        BEGIN
            IF @evento_existente_tipo <> @tipo_evento
               OR @evento_existente_id <> @solicitud_id
               OR @evento_existente_empleado_id <> @empleado_id
               OR NOT
                  (
                      @evento_existente_motivo = @comentario
                      OR
                      (
                          @evento_existente_motivo IS NULL
                          AND @comentario IS NULL
                      )
                  )
                THROW 55306, 'La correlacion ya se uso con parametros diferentes.', 1;

            COMMIT TRANSACTION;
            RETURN;
        END;

        SELECT
            @orden_id = s.orden_id,
            @linea_id = s.linea_id,
            @sesion_linea_id = s.sesion_linea_id,
            @componente_orden_id = s.componente_orden_id,
            @cantidad_solicitada = s.cantidad_solicitada,
            @estado_anterior = s.estado,
            @asignada_a_empleado_id = s.asignada_a_empleado_id
        FROM [log].solicitudes_reaprovisionamiento s
             WITH (UPDLOCK, HOLDLOCK)
        WHERE s.solicitud_id = @solicitud_id;

        IF @orden_id IS NULL
            THROW 55307, 'La solicitud no existe.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM seg.empleados e WITH (UPDLOCK, HOLDLOCK)
            JOIN seg.empleados_roles er
              ON er.empleado_id = e.empleado_id
             AND er.hasta_utc IS NULL
            JOIN seg.roles r
              ON r.rol_id = er.rol_id
             AND r.activo = 1
            WHERE e.empleado_id = @empleado_id
              AND e.activo_nav = 1
              AND e.activo_mes = 1
              AND r.codigo = N'APROVISIONADOR'
        )
            THROW 55308, 'La transicion requiere aprovisionador activo.', 1;

        IF @estado_anterior IN (N'ENTREGADA', N'RECHAZADA', N'CANCELADA')
            THROW 55309, 'La solicitud ya se encuentra en un estado terminal.', 1;

        IF @estado_anterior <> N'PENDIENTE'
           AND @asignada_a_empleado_id <> @empleado_id
            THROW 55310, 'La solicitud debe continuarla el aprovisionador asignado.', 1;

        SET @estado_permitido =
            CASE
                WHEN @estado_anterior = N'PENDIENTE'
                 AND @estado_nuevo IN (N'ACEPTADA', N'RECHAZADA', N'CANCELADA')
                    THEN 1
                WHEN @estado_anterior = N'ACEPTADA'
                 AND @estado_nuevo IN (N'EN_CAMINO', N'RECHAZADA', N'CANCELADA')
                    THEN 1
                WHEN @estado_anterior = N'EN_CAMINO'
                 AND @estado_nuevo IN (N'ENTREGADA', N'CANCELADA')
                    THEN 1
                ELSE 0
            END;

        IF @estado_permitido = 0
            THROW 55311, 'La transicion de estado no esta permitida.', 1;

        SET @fecha_utc = SYSUTCDATETIME();

        SELECT @valor_anterior =
        (
            SELECT
                @estado_anterior AS estado,
                @asignada_a_empleado_id AS asignada_a_empleado_id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        UPDATE [log].solicitudes_reaprovisionamiento
        SET estado = @estado_nuevo,
            asignada_a_empleado_id =
                CASE WHEN @estado_nuevo = N'ACEPTADA'
                     THEN @empleado_id
                     ELSE asignada_a_empleado_id
                END,
            aceptada_utc =
                CASE WHEN @estado_nuevo = N'ACEPTADA'
                     THEN @fecha_utc
                     ELSE aceptada_utc
                END,
            en_camino_utc =
                CASE WHEN @estado_nuevo = N'EN_CAMINO'
                     THEN @fecha_utc
                     ELSE en_camino_utc
                END,
            entregada_utc =
                CASE WHEN @estado_nuevo = N'ENTREGADA'
                     THEN @fecha_utc
                     ELSE entregada_utc
                END,
            rechazada_utc =
                CASE WHEN @estado_nuevo = N'RECHAZADA'
                     THEN @fecha_utc
                     ELSE rechazada_utc
                END,
            cancelada_utc =
                CASE WHEN @estado_nuevo = N'CANCELADA'
                     THEN @fecha_utc
                     ELSE cancelada_utc
                END,
            motivo_rechazo =
                CASE WHEN @estado_nuevo = N'RECHAZADA'
                     THEN @comentario
                     ELSE motivo_rechazo
                END,
            motivo_cancelacion =
                CASE WHEN @estado_nuevo = N'CANCELADA'
                     THEN @comentario
                     ELSE motivo_cancelacion
                END
        WHERE solicitud_id = @solicitud_id;

        INSERT [log].historial_solicitudes
        (
            solicitud_id, estado_anterior, estado_nuevo,
            empleado_id, fecha_utc, comentario
        )
        VALUES
        (
            @solicitud_id, @estado_anterior, @estado_nuevo,
            @empleado_id, @fecha_utc, @comentario
        );

        SELECT @valor_nuevo =
        (
            SELECT
                @estado_nuevo AS estado,
                CASE WHEN @estado_nuevo = N'ACEPTADA'
                     THEN @empleado_id
                     ELSE @asignada_a_empleado_id
                END AS asignada_a_empleado_id,
                @componente_orden_id AS componente_orden_id,
                @cantidad_solicitada AS cantidad_solicitada,
                @fecha_utc AS fecha_transicion_utc,
                @comentario AS comentario
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC aud.registrar_evento
            @tipo_evento = @tipo_evento,
            @empleado_id = @empleado_id,
            @rol_usado = N'APROVISIONADOR',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'log.solicitudes_reaprovisionamiento',
            @entidad_id = @solicitud_id,
            @valor_anterior = @valor_anterior,
            @valor_nuevo = @valor_nuevo,
            @motivo = @comentario,
            @correlacion_id = @correlacion_id;

        COMMIT TRANSACTION;
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
    GRANT EXECUTE
        ON OBJECT::[log].transicionar_solicitud_reaprovisionamiento
        TO mes_runtime;
GO
