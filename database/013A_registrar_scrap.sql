SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE [log].registrar_scrap
    @sesion_linea_id bigint,
    @componente_orden_id bigint,
    @motivo_scrap_id smallint,
    @cantidad int,
    @descripcion nvarchar(1000) = NULL,
    @registrado_por_empleado_id bigint,
    @correlacion_id uniqueidentifier,
    @scrap_id bigint OUTPUT,
    @operacion_nav_id bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @scrap_id = NULL;
    SET @operacion_nav_id = NULL;
    SET @descripcion = NULLIF(LTRIM(RTRIM(@descripcion)), N'');

    IF @sesion_linea_id IS NULL
        THROW 55000, 'La sesion de linea es obligatoria.', 1;

    IF @componente_orden_id IS NULL
        THROW 55001, 'El componente de la orden es obligatorio.', 1;

    IF @motivo_scrap_id IS NULL
        THROW 55002, 'El motivo de scrap es obligatorio.', 1;

    IF @cantidad IS NULL OR @cantidad <= 0
        THROW 55003, 'La cantidad de scrap debe ser positiva.', 1;

    IF @registrado_por_empleado_id IS NULL
        THROW 55004, 'El empleado que registra el scrap es obligatorio.', 1;

    IF @correlacion_id IS NULL
        THROW 55005, 'La correlacion es obligatoria.', 1;

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
            @scrap_uid uniqueidentifier,
            @componente_codigo nvarchar(50),
            @componente_descripcion nvarchar(250),
            @unidad_medida nvarchar(20),
            @motivo_codigo nvarchar(50),
            @motivo_descripcion nvarchar(150),
            @motivo_categoria nvarchar(20),
            @requiere_descripcion bit,
            @rol_usado nvarchar(30),
            @registrado_utc datetime2(3),
            @payload_nav nvarchar(max),
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
            THROW 55006, 'No se pudo obtener el bloqueo de idempotencia.', 1;

        SELECT TOP (1)
            @evento_existente_id = entidad_id,
            @evento_existente_tipo = tipo_evento
        FROM aud.eventos WITH (UPDLOCK, HOLDLOCK)
        WHERE correlacion_id = @correlacion_id
        ORDER BY evento_auditoria_id;

        IF @evento_existente_tipo IS NOT NULL
        BEGIN
            IF @evento_existente_tipo <> N'SCRAP_REGISTRADO'
               OR @evento_existente_id IS NULL
                THROW 55007, 'La correlacion ya pertenece a otra operacion.', 1;

            SET @scrap_id = @evento_existente_id;

            IF NOT EXISTS
            (
                SELECT 1
                FROM [log].scrap s WITH (UPDLOCK, HOLDLOCK)
                WHERE s.scrap_id = @scrap_id
                  AND s.sesion_linea_id = @sesion_linea_id
                  AND s.componente_orden_id = @componente_orden_id
                  AND s.motivo_scrap_id = @motivo_scrap_id
                  AND s.cantidad = @cantidad
                  AND s.registrado_por_empleado_id = @registrado_por_empleado_id
                  AND
                  (
                      s.descripcion = @descripcion
                      OR (s.descripcion IS NULL AND @descripcion IS NULL)
                  )
            )
                THROW 55016, 'La correlacion ya se uso con parametros diferentes.', 1;

            SELECT @operacion_nav_id = operacion_nav_id
            FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
            WHERE scrap_id = @scrap_id
              AND tipo = N'CONSUMO_SCRAP'
              AND revision_scrap_id IS NULL;

            IF @operacion_nav_id IS NULL
                THROW 55008, 'La operacion idempotente anterior esta incompleta.', 1;

            COMMIT TRANSACTION;
            RETURN;
        END;

        SELECT
            @orden_id = s.orden_id,
            @linea_id = s.linea_id,
            @estado_sesion = s.estado
        FROM prod.sesiones_linea s WITH (UPDLOCK, HOLDLOCK)
        WHERE s.sesion_linea_id = @sesion_linea_id
          AND s.finalizada_utc IS NULL;

        IF @orden_id IS NULL
            THROW 55009, 'La sesion no existe o ya esta finalizada.', 1;

        IF @estado_sesion NOT IN
           (N'CARGADA', N'PRODUCIENDO', N'SIN_OPERARIOS', N'STANDBY')
            THROW 55010, 'La sesion no admite registrar scrap en su estado actual.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
            WHERE orden_id = @orden_id
              AND estado IN (N'IMPORTADA', N'ABIERTA', N'PICO_PENDIENTE')
        )
            THROW 55011, 'La orden no admite registrar scrap en su estado actual.', 1;

        SELECT TOP (1)
            @rol_usado = r.codigo
        FROM seg.empleados e WITH (UPDLOCK, HOLDLOCK)
        JOIN seg.empleados_roles er
          ON er.empleado_id = e.empleado_id
         AND er.hasta_utc IS NULL
        JOIN seg.roles r
          ON r.rol_id = er.rol_id
         AND r.activo = 1
        WHERE e.empleado_id = @registrado_por_empleado_id
          AND e.activo_nav = 1
          AND e.activo_mes = 1
          AND r.codigo IN (N'OPERARIO', N'SUPERVISOR')
        ORDER BY CASE r.codigo WHEN N'SUPERVISOR' THEN 1 ELSE 2 END;

        IF @rol_usado IS NULL
            THROW 55012, 'El registro de scrap requiere operario o supervisor activo.', 1;

        SELECT
            @componente_codigo = c.codigo_componente,
            @componente_descripcion = c.descripcion,
            @unidad_medida = c.unidad_medida
        FROM nav.componentes_orden c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.componente_orden_id = @componente_orden_id
          AND c.orden_id = @orden_id;

        IF @componente_codigo IS NULL
            THROW 55013, 'El componente no existe o no pertenece a la orden de la sesion.', 1;

        SELECT
            @motivo_codigo = m.codigo,
            @motivo_descripcion = m.descripcion,
            @motivo_categoria = m.categoria,
            @requiere_descripcion = m.requiere_descripcion
        FROM [log].motivos_scrap m WITH (UPDLOCK, HOLDLOCK)
        WHERE m.motivo_scrap_id = @motivo_scrap_id
          AND m.activo = 1;

        IF @motivo_codigo IS NULL
            THROW 55014, 'El motivo de scrap no existe o no esta activo.', 1;

        IF @requiere_descripcion = 1 AND @descripcion IS NULL
            THROW 55015, 'El motivo de scrap seleccionado requiere descripcion.', 1;

        SET @scrap_uid = NEWID();
        SET @registrado_utc = SYSUTCDATETIME();

        INSERT [log].scrap
        (
            scrap_uid, orden_id, sesion_linea_id, linea_id,
            componente_orden_id, componente_codigo_snapshot,
            componente_descripcion_snapshot, motivo_scrap_id,
            cantidad, descripcion, registrado_por_empleado_id, registrado_utc
        )
        VALUES
        (
            @scrap_uid, @orden_id, @sesion_linea_id, @linea_id,
            @componente_orden_id, @componente_codigo,
            @componente_descripcion, @motivo_scrap_id,
            @cantidad, @descripcion, @registrado_por_empleado_id, @registrado_utc
        );

        SET @scrap_id = SCOPE_IDENTITY();

        UPDATE prod.ordenes
        SET cantidad_scrap_acumulada = cantidad_scrap_acumulada + @cantidad
        WHERE orden_id = @orden_id;

        SELECT @payload_nav =
        (
            SELECT
                @scrap_uid AS scrap_uid,
                @orden_id AS orden_id,
                @sesion_linea_id AS sesion_linea_id,
                @linea_id AS linea_id,
                @componente_orden_id AS componente_orden_id,
                @componente_codigo AS componente_codigo,
                @componente_descripcion AS componente_descripcion,
                @unidad_medida AS unidad_medida,
                @motivo_scrap_id AS motivo_scrap_id,
                @motivo_categoria AS motivo_categoria,
                @motivo_codigo AS motivo_codigo,
                @cantidad AS cantidad,
                @descripcion AS descripcion,
                @registrado_utc AS registrado_utc
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        INSERT nav.operaciones
        (
            clave_idempotencia, tipo, orden_id, scrap_id,
            estado, payload, proximo_intento_utc
        )
        VALUES
        (
            CONCAT(N'SCRAP:', CONVERT(nvarchar(36), @scrap_uid), N':R0'),
            N'CONSUMO_SCRAP', @orden_id, @scrap_id,
            N'PENDIENTE', @payload_nav, @registrado_utc
        );

        SET @operacion_nav_id = SCOPE_IDENTITY();

        SELECT @valor_nuevo =
        (
            SELECT
                @scrap_id AS scrap_id,
                @scrap_uid AS scrap_uid,
                @componente_orden_id AS componente_orden_id,
                @componente_codigo AS componente_codigo,
                @motivo_scrap_id AS motivo_scrap_id,
                @motivo_categoria AS motivo_categoria,
                @motivo_codigo AS motivo_codigo,
                @motivo_descripcion AS motivo_descripcion,
                @cantidad AS cantidad,
                @descripcion AS descripcion,
                @operacion_nav_id AS operacion_nav_id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC aud.registrar_evento
            @tipo_evento = N'SCRAP_REGISTRADO',
            @empleado_id = @registrado_por_empleado_id,
            @rol_usado = @rol_usado,
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'log.scrap',
            @entidad_id = @scrap_id,
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
    GRANT EXECUTE ON OBJECT::[log].registrar_scrap TO mes_runtime;
GO
