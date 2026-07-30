SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE [log].crear_solicitud_reaprovisionamiento
    @sesion_linea_id bigint,
    @componente_orden_id bigint,
    @cantidad_solicitada int,
    @solicitada_por_empleado_id bigint,
    @scrap_id bigint = NULL,
    @correlacion_id uniqueidentifier,
    @solicitud_id bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @solicitud_id = NULL;

    IF @sesion_linea_id IS NULL
        THROW 55200, 'La sesion de linea es obligatoria.', 1;

    IF @componente_orden_id IS NULL
        THROW 55201, 'El componente de la orden es obligatorio.', 1;

    IF @cantidad_solicitada IS NULL OR @cantidad_solicitada <= 0
        THROW 55202, 'La cantidad solicitada debe ser positiva.', 1;

    IF @solicitada_por_empleado_id IS NULL
        THROW 55203, 'El empleado solicitante es obligatorio.', 1;

    IF @correlacion_id IS NULL
        THROW 55204, 'La correlacion es obligatoria.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @resultado_bloqueo int,
            @recurso_bloqueo nvarchar(255),
            @evento_existente_id bigint,
            @evento_existente_tipo nvarchar(80),
            @orden_id bigint,
            @linea_id bigint,
            @estado_sesion nvarchar(30),
            @componente_codigo nvarchar(50),
            @componente_descripcion nvarchar(250),
            @rol_usado nvarchar(30),
            @scrap_orden_id bigint,
            @scrap_sesion_linea_id bigint,
            @scrap_linea_id bigint,
            @scrap_componente_efectivo_id bigint,
            @scrap_cantidad_efectiva int,
            @scrap_anulado bit,
            @solicitada_utc datetime2(3),
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
            THROW 55205, 'No se pudo obtener el bloqueo de idempotencia.', 1;

        SELECT TOP (1)
            @evento_existente_id = entidad_id,
            @evento_existente_tipo = tipo_evento
        FROM aud.eventos WITH (UPDLOCK, HOLDLOCK)
        WHERE correlacion_id = @correlacion_id
        ORDER BY evento_auditoria_id;

        IF @evento_existente_tipo IS NOT NULL
        BEGIN
            IF @evento_existente_tipo <> N'REAPROVISIONAMIENTO_SOLICITADO'
               OR @evento_existente_id IS NULL
                THROW 55206, 'La correlacion ya pertenece a otra operacion.', 1;

            IF NOT EXISTS
            (
                SELECT 1
                FROM [log].solicitudes_reaprovisionamiento s
                     WITH (UPDLOCK, HOLDLOCK)
                WHERE s.solicitud_id = @evento_existente_id
                  AND s.sesion_linea_id = @sesion_linea_id
                  AND s.componente_orden_id = @componente_orden_id
                  AND s.cantidad_solicitada = @cantidad_solicitada
                  AND s.solicitada_por_empleado_id = @solicitada_por_empleado_id
                  AND
                  (
                      s.scrap_id = @scrap_id
                      OR (s.scrap_id IS NULL AND @scrap_id IS NULL)
                  )
            )
                THROW 55207, 'La correlacion ya se uso con parametros diferentes.', 1;

            SET @solicitud_id = @evento_existente_id;
            COMMIT TRANSACTION;
            RETURN;
        END;

        IF @scrap_id IS NOT NULL
        BEGIN
            SET @recurso_bloqueo =
                CONCAT(N'MES:SCRAP:', CONVERT(nvarchar(20), @scrap_id));

            EXEC @resultado_bloqueo = sys.sp_getapplock
                @Resource = @recurso_bloqueo,
                @LockMode = N'Exclusive',
                @LockOwner = N'Transaction',
                @LockTimeout = 10000,
                @DbPrincipal = N'public';

            IF @resultado_bloqueo < 0
                THROW 55217, 'No se pudo obtener el bloqueo transaccional del scrap.', 1;
        END;

        SELECT
            @orden_id = s.orden_id,
            @linea_id = s.linea_id,
            @estado_sesion = s.estado
        FROM prod.sesiones_linea s WITH (UPDLOCK, HOLDLOCK)
        WHERE s.sesion_linea_id = @sesion_linea_id
          AND s.finalizada_utc IS NULL;

        IF @orden_id IS NULL
            THROW 55208, 'La sesion no existe o ya esta finalizada.', 1;

        IF @estado_sesion NOT IN
           (N'CARGADA', N'PRODUCIENDO', N'SIN_OPERARIOS', N'STANDBY',
            N'PICO_PENDIENTE')
            THROW 55209, 'La sesion no admite solicitudes en su estado actual.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
            WHERE orden_id = @orden_id
              AND estado IN (N'IMPORTADA', N'ABIERTA', N'PICO_PENDIENTE')
        )
            THROW 55210, 'La orden no admite solicitudes en su estado actual.', 1;

        SELECT TOP (1)
            @rol_usado = r.codigo
        FROM seg.empleados e WITH (UPDLOCK, HOLDLOCK)
        JOIN seg.empleados_roles er
          ON er.empleado_id = e.empleado_id
         AND er.hasta_utc IS NULL
        JOIN seg.roles r
          ON r.rol_id = er.rol_id
         AND r.activo = 1
        WHERE e.empleado_id = @solicitada_por_empleado_id
          AND e.activo_nav = 1
          AND e.activo_mes = 1
          AND r.codigo IN (N'OPERARIO', N'SUPERVISOR')
        ORDER BY CASE r.codigo WHEN N'SUPERVISOR' THEN 1 ELSE 2 END;

        IF @rol_usado IS NULL
            THROW 55211, 'La solicitud requiere operario o supervisor activo.', 1;

        SELECT
            @componente_codigo = c.codigo_componente,
            @componente_descripcion = c.descripcion
        FROM nav.componentes_orden c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.componente_orden_id = @componente_orden_id
          AND c.orden_id = @orden_id;

        IF @componente_codigo IS NULL
            THROW 55212, 'El componente no existe o no pertenece a la orden de la sesion.', 1;

        IF @scrap_id IS NOT NULL
        BEGIN
            SELECT
                @scrap_orden_id = s.orden_id,
                @scrap_sesion_linea_id = s.sesion_linea_id,
                @scrap_linea_id = s.linea_id,
                @scrap_componente_efectivo_id = s.componente_orden_id,
                @scrap_cantidad_efectiva = s.cantidad,
                @scrap_anulado = CONVERT(bit, 0)
            FROM [log].scrap s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.scrap_id = @scrap_id;

            IF @scrap_orden_id IS NULL
                THROW 55213, 'El scrap vinculado no existe.', 1;

            SELECT TOP (1)
                @scrap_componente_efectivo_id = r.componente_orden_id,
                @scrap_cantidad_efectiva = r.cantidad,
                @scrap_anulado = r.es_anulacion
            FROM [log].revisiones_scrap r WITH (UPDLOCK, HOLDLOCK)
            WHERE r.scrap_id = @scrap_id
            ORDER BY r.numero_revision DESC;

            IF @scrap_orden_id <> @orden_id
               OR @scrap_sesion_linea_id <> @sesion_linea_id
               OR @scrap_linea_id <> @linea_id
                THROW 55214, 'El scrap no pertenece a la misma orden, sesion y linea.', 1;

            IF @scrap_anulado = 1 OR @scrap_cantidad_efectiva <= 0
                THROW 55215, 'No puede solicitarse reaprovisionamiento para un scrap anulado.', 1;

            IF @scrap_componente_efectivo_id <> @componente_orden_id
                THROW 55216, 'El componente solicitado no coincide con el componente efectivo del scrap.', 1;
        END;

        SET @solicitada_utc = SYSUTCDATETIME();

        INSERT [log].solicitudes_reaprovisionamiento
        (
            orden_id, linea_id, sesion_linea_id, scrap_id,
            componente_orden_id, cantidad_solicitada, estado,
            solicitada_por_empleado_id, solicitada_utc
        )
        VALUES
        (
            @orden_id, @linea_id, @sesion_linea_id, @scrap_id,
            @componente_orden_id, @cantidad_solicitada, N'PENDIENTE',
            @solicitada_por_empleado_id, @solicitada_utc
        );

        SET @solicitud_id = SCOPE_IDENTITY();

        INSERT [log].historial_solicitudes
        (
            solicitud_id, estado_anterior, estado_nuevo,
            empleado_id, fecha_utc, comentario
        )
        VALUES
        (
            @solicitud_id, NULL, N'PENDIENTE',
            @solicitada_por_empleado_id, @solicitada_utc, NULL
        );

        SELECT @valor_nuevo =
        (
            SELECT
                @solicitud_id AS solicitud_id,
                N'PENDIENTE' AS estado,
                @scrap_id AS scrap_id,
                @componente_orden_id AS componente_orden_id,
                @componente_codigo AS componente_codigo,
                @componente_descripcion AS componente_descripcion,
                @cantidad_solicitada AS cantidad_solicitada,
                @solicitada_utc AS solicitada_utc
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC aud.registrar_evento
            @tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO',
            @empleado_id = @solicitada_por_empleado_id,
            @rol_usado = @rol_usado,
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'log.solicitudes_reaprovisionamiento',
            @entidad_id = @solicitud_id,
            @valor_nuevo = @valor_nuevo,
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
    GRANT EXECUTE ON OBJECT::[log].crear_solicitud_reaprovisionamiento
        TO mes_runtime;
GO
