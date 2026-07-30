SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE [log].revisar_scrap
    @scrap_id bigint,
    @componente_orden_id bigint,
    @motivo_scrap_id smallint,
    @cantidad int,
    @descripcion nvarchar(1000) = NULL,
    @es_anulacion bit,
    @ajustado_por_supervisor_id bigint,
    @motivo_ajuste nvarchar(500),
    @correlacion_id uniqueidentifier,
    @revision_scrap_id bigint OUTPUT,
    @operacion_nav_id bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @revision_scrap_id = NULL;
    SET @operacion_nav_id = NULL;
    SET @descripcion = NULLIF(LTRIM(RTRIM(@descripcion)), N'');
    SET @motivo_ajuste = NULLIF(LTRIM(RTRIM(@motivo_ajuste)), N'');

    IF @scrap_id IS NULL
        THROW 55100, 'El scrap es obligatorio.', 1;

    IF @componente_orden_id IS NULL
        THROW 55101, 'El componente de la orden es obligatorio.', 1;

    IF @motivo_scrap_id IS NULL
        THROW 55102, 'El motivo de scrap es obligatorio.', 1;

    IF @es_anulacion IS NULL
        THROW 55103, 'Debe indicarse si la revision es una anulacion.', 1;

    IF (@es_anulacion = 1 AND (@cantidad IS NULL OR @cantidad <> 0))
       OR (@es_anulacion = 0 AND (@cantidad IS NULL OR @cantidad <= 0))
        THROW 55104, 'La anulacion requiere cantidad cero y la correccion cantidad positiva.', 1;

    IF @ajustado_por_supervisor_id IS NULL
        THROW 55105, 'El supervisor que ajusta el scrap es obligatorio.', 1;

    IF @motivo_ajuste IS NULL
        THROW 55106, 'La revision de scrap requiere motivo de ajuste.', 1;

    IF @correlacion_id IS NULL
        THROW 55107, 'La correlacion es obligatoria.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @resultado_bloqueo int,
            @recurso_bloqueo nvarchar(255),
            @evento_existente_id bigint,
            @evento_existente_tipo nvarchar(80),
            @orden_id bigint,
            @sesion_linea_id bigint,
            @linea_id bigint,
            @scrap_uid uniqueidentifier,
            @numero_revision int,
            @revision_uid uniqueidentifier,
            @componente_codigo nvarchar(50),
            @componente_descripcion nvarchar(250),
            @unidad_medida nvarchar(20),
            @motivo_codigo nvarchar(50),
            @motivo_descripcion nvarchar(150),
            @motivo_categoria nvarchar(20),
            @requiere_descripcion bit,
            @componente_anterior_id bigint,
            @componente_anterior_codigo nvarchar(50),
            @componente_anterior_descripcion nvarchar(250),
            @motivo_anterior_id smallint,
            @cantidad_anterior int,
            @descripcion_anterior nvarchar(1000),
            @es_anulacion_anterior bit,
            @delta int,
            @cantidad_scrap_acumulada int,
            @ultimo_estado_nav nvarchar(30),
            @ajustado_utc datetime2(3),
            @tipo_operacion_nav nvarchar(30),
            @tipo_evento nvarchar(80),
            @payload_nav nvarchar(max),
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
            THROW 55108, 'No se pudo obtener el bloqueo de idempotencia.', 1;

        SELECT TOP (1)
            @evento_existente_id = entidad_id,
            @evento_existente_tipo = tipo_evento
        FROM aud.eventos WITH (UPDLOCK, HOLDLOCK)
        WHERE correlacion_id = @correlacion_id
        ORDER BY evento_auditoria_id;

        IF @evento_existente_tipo IS NOT NULL
        BEGIN
            IF @evento_existente_tipo NOT IN (N'SCRAP_CORREGIDO', N'SCRAP_ANULADO')
               OR @evento_existente_id IS NULL
                THROW 55109, 'La correlacion ya pertenece a otra operacion.', 1;

            SET @revision_scrap_id = @evento_existente_id;

            IF @evento_existente_tipo <>
               CASE WHEN @es_anulacion = 1
                    THEN N'SCRAP_ANULADO'
                    ELSE N'SCRAP_CORREGIDO'
               END
               OR NOT EXISTS
               (
                   SELECT 1
                   FROM [log].revisiones_scrap r WITH (UPDLOCK, HOLDLOCK)
                   WHERE r.revision_scrap_id = @revision_scrap_id
                     AND r.scrap_id = @scrap_id
                     AND r.componente_orden_id = @componente_orden_id
                     AND r.motivo_scrap_id = @motivo_scrap_id
                     AND r.cantidad = @cantidad
                     AND r.es_anulacion = @es_anulacion
                     AND r.ajustado_por_supervisor_id = @ajustado_por_supervisor_id
                     AND r.motivo_ajuste = @motivo_ajuste
                     AND
                     (
                         r.descripcion = @descripcion
                         OR (r.descripcion IS NULL AND @descripcion IS NULL)
                     )
               )
                THROW 55110, 'La correlacion ya se uso con parametros diferentes.', 1;

            SELECT @operacion_nav_id = operacion_nav_id
            FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
            WHERE revision_scrap_id = @revision_scrap_id
              AND scrap_id = @scrap_id
              AND tipo IN (N'AJUSTE_CONSUMO_SCRAP', N'ANULACION_CONSUMO');

            IF @operacion_nav_id IS NULL
                THROW 55121, 'La operacion idempotente anterior no corresponde al scrap o esta incompleta.', 1;

            COMMIT TRANSACTION;
            RETURN;
        END;

        SET @recurso_bloqueo =
            CONCAT(N'MES:SCRAP:', CONVERT(nvarchar(20), @scrap_id));

        EXEC @resultado_bloqueo = sys.sp_getapplock
            @Resource = @recurso_bloqueo,
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000,
            @DbPrincipal = N'public';

        IF @resultado_bloqueo < 0
            THROW 55122, 'No se pudo obtener el bloqueo transaccional del scrap.', 1;

        SELECT
            @orden_id = s.orden_id,
            @sesion_linea_id = s.sesion_linea_id,
            @linea_id = s.linea_id,
            @scrap_uid = s.scrap_uid,
            @componente_anterior_id = s.componente_orden_id,
            @componente_anterior_codigo = s.componente_codigo_snapshot,
            @componente_anterior_descripcion = s.componente_descripcion_snapshot,
            @motivo_anterior_id = s.motivo_scrap_id,
            @cantidad_anterior = s.cantidad,
            @descripcion_anterior = s.descripcion,
            @es_anulacion_anterior = CONVERT(bit, 0)
        FROM [log].scrap s WITH (UPDLOCK, HOLDLOCK)
        WHERE s.scrap_id = @scrap_id;

        IF @orden_id IS NULL
            THROW 55111, 'El scrap no existe.', 1;

        SELECT TOP (1)
            @componente_anterior_id = r.componente_orden_id,
            @componente_anterior_codigo = r.componente_codigo_snapshot,
            @componente_anterior_descripcion = r.componente_descripcion_snapshot,
            @motivo_anterior_id = r.motivo_scrap_id,
            @cantidad_anterior = r.cantidad,
            @descripcion_anterior = r.descripcion,
            @es_anulacion_anterior = r.es_anulacion
        FROM [log].revisiones_scrap r WITH (UPDLOCK, HOLDLOCK)
        WHERE r.scrap_id = @scrap_id
        ORDER BY r.numero_revision DESC;

        SELECT
            @cantidad_scrap_acumulada = o.cantidad_scrap_acumulada
        FROM prod.ordenes o WITH (UPDLOCK, HOLDLOCK)
        WHERE o.orden_id = @orden_id;

        IF @cantidad_scrap_acumulada IS NULL
            THROW 55112, 'La orden asociada al scrap no existe.', 1;

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
            WHERE e.empleado_id = @ajustado_por_supervisor_id
              AND e.activo_nav = 1
              AND e.activo_mes = 1
              AND r.codigo = N'SUPERVISOR'
        )
            THROW 55113, 'La revision de scrap requiere supervisor activo.', 1;

        SELECT
            @componente_codigo = c.codigo_componente,
            @componente_descripcion = c.descripcion,
            @unidad_medida = c.unidad_medida
        FROM nav.componentes_orden c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.componente_orden_id = @componente_orden_id
          AND c.orden_id = @orden_id;

        IF @componente_codigo IS NULL
            THROW 55114, 'El componente no existe o no pertenece a la orden del scrap.', 1;

        SELECT
            @motivo_codigo = m.codigo,
            @motivo_descripcion = m.descripcion,
            @motivo_categoria = m.categoria,
            @requiere_descripcion = m.requiere_descripcion
        FROM [log].motivos_scrap m WITH (UPDLOCK, HOLDLOCK)
        WHERE m.motivo_scrap_id = @motivo_scrap_id
          AND m.activo = 1;

        IF @motivo_codigo IS NULL
            THROW 55115, 'El motivo de scrap no existe o no esta activo.', 1;

        IF @es_anulacion = 0
           AND @requiere_descripcion = 1
           AND @descripcion IS NULL
            THROW 55116, 'El motivo de scrap seleccionado requiere descripcion.', 1;

        IF @es_anulacion = @es_anulacion_anterior
           AND @componente_orden_id = @componente_anterior_id
           AND @motivo_scrap_id = @motivo_anterior_id
           AND @cantidad = @cantidad_anterior
           AND
           (
               @descripcion = @descripcion_anterior
               OR (@descripcion IS NULL AND @descripcion_anterior IS NULL)
           )
            THROW 55117, 'La revision no modifica el valor efectivo del scrap.', 1;

        SELECT TOP (1)
            @ultimo_estado_nav = n.estado
        FROM nav.operaciones n WITH (UPDLOCK, HOLDLOCK)
        WHERE n.scrap_id = @scrap_id
          AND n.tipo IN
              (N'CONSUMO_SCRAP', N'AJUSTE_CONSUMO_SCRAP', N'ANULACION_CONSUMO')
        ORDER BY n.operacion_nav_id DESC;

        IF @ultimo_estado_nav IS NULL
            THROW 55118, 'El scrap no tiene una operacion NAV de consumo asociada.', 1;

        IF @ultimo_estado_nav IN (N'PROCESANDO', N'RESULTADO_DESCONOCIDO')
            THROW 55119, 'No puede revisarse el scrap mientras su ultimo resultado NAV este en curso o sea incierto.', 1;

        SELECT @numero_revision = ISNULL(MAX(numero_revision), 0) + 1
        FROM [log].revisiones_scrap WITH (UPDLOCK, HOLDLOCK)
        WHERE scrap_id = @scrap_id;

        SET @delta = @cantidad - @cantidad_anterior;

        IF @cantidad_scrap_acumulada + @delta < 0
            THROW 55120, 'El ajuste produciria un acumulado de scrap negativo.', 1;

        SET @revision_uid = NEWID();
        SET @ajustado_utc = SYSUTCDATETIME();
        SET @tipo_operacion_nav =
            CASE WHEN @es_anulacion = 1
                 THEN N'ANULACION_CONSUMO'
                 ELSE N'AJUSTE_CONSUMO_SCRAP'
            END;
        SET @tipo_evento =
            CASE WHEN @es_anulacion = 1
                 THEN N'SCRAP_ANULADO'
                 ELSE N'SCRAP_CORREGIDO'
            END;

        INSERT [log].revisiones_scrap
        (
            revision_uid, scrap_id, orden_id, numero_revision,
            componente_orden_id, componente_codigo_snapshot,
            componente_descripcion_snapshot, motivo_scrap_id,
            cantidad, descripcion, es_anulacion,
            ajustado_por_supervisor_id, motivo_ajuste, ajustado_utc
        )
        VALUES
        (
            @revision_uid, @scrap_id, @orden_id, @numero_revision,
            @componente_orden_id, @componente_codigo,
            @componente_descripcion, @motivo_scrap_id,
            @cantidad, @descripcion, @es_anulacion,
            @ajustado_por_supervisor_id, @motivo_ajuste, @ajustado_utc
        );

        SET @revision_scrap_id = SCOPE_IDENTITY();

        UPDATE prod.ordenes
        SET cantidad_scrap_acumulada = cantidad_scrap_acumulada + @delta
        WHERE orden_id = @orden_id;

        SELECT @payload_nav =
        (
            SELECT
                @scrap_uid AS scrap_uid,
                @revision_uid AS revision_uid,
                @numero_revision AS numero_revision,
                @orden_id AS orden_id,
                @sesion_linea_id AS sesion_linea_id,
                @linea_id AS linea_id,
                @componente_anterior_id AS componente_anterior_id,
                @componente_anterior_codigo AS componente_anterior_codigo,
                @cantidad_anterior AS cantidad_anterior,
                @componente_orden_id AS componente_orden_id,
                @componente_codigo AS componente_codigo,
                @componente_descripcion AS componente_descripcion,
                @unidad_medida AS unidad_medida,
                @motivo_scrap_id AS motivo_scrap_id,
                @motivo_categoria AS motivo_categoria,
                @motivo_codigo AS motivo_codigo,
                @cantidad AS cantidad_nueva,
                @delta AS delta_consumo,
                @es_anulacion AS es_anulacion,
                @descripcion AS descripcion,
                @motivo_ajuste AS motivo_ajuste,
                @ajustado_utc AS ajustado_utc
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        INSERT nav.operaciones
        (
            clave_idempotencia, tipo, orden_id, scrap_id,
            revision_scrap_id, estado, payload, proximo_intento_utc
        )
        VALUES
        (
            CONCAT
            (
                N'SCRAP:', CONVERT(nvarchar(36), @scrap_uid),
                N':R', CONVERT(nvarchar(12), @numero_revision)
            ),
            @tipo_operacion_nav, @orden_id, @scrap_id,
            @revision_scrap_id, N'PENDIENTE', @payload_nav, @ajustado_utc
        );

        SET @operacion_nav_id = SCOPE_IDENTITY();

        SELECT @valor_anterior =
        (
            SELECT
                @componente_anterior_id AS componente_orden_id,
                @componente_anterior_codigo AS componente_codigo,
                @componente_anterior_descripcion AS componente_descripcion,
                @motivo_anterior_id AS motivo_scrap_id,
                @cantidad_anterior AS cantidad,
                @descripcion_anterior AS descripcion,
                @es_anulacion_anterior AS es_anulacion
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        SELECT @valor_nuevo =
        (
            SELECT
                @revision_scrap_id AS revision_scrap_id,
                @revision_uid AS revision_uid,
                @numero_revision AS numero_revision,
                @componente_orden_id AS componente_orden_id,
                @componente_codigo AS componente_codigo,
                @componente_descripcion AS componente_descripcion,
                @motivo_scrap_id AS motivo_scrap_id,
                @motivo_categoria AS motivo_categoria,
                @motivo_codigo AS motivo_codigo,
                @motivo_descripcion AS motivo_descripcion,
                @cantidad AS cantidad,
                @descripcion AS descripcion,
                @es_anulacion AS es_anulacion,
                @delta AS delta,
                @operacion_nav_id AS operacion_nav_id
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC aud.registrar_evento
            @tipo_evento = @tipo_evento,
            @empleado_id = @ajustado_por_supervisor_id,
            @rol_usado = N'SUPERVISOR',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'log.revisiones_scrap',
            @entidad_id = @revision_scrap_id,
            @valor_anterior = @valor_anterior,
            @valor_nuevo = @valor_nuevo,
            @motivo = @motivo_ajuste,
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
    GRANT EXECUTE ON OBJECT::[log].revisar_scrap TO mes_runtime;
GO
