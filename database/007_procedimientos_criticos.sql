SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE aud.registrar_evento
    @tipo_evento nvarchar(80),
    @empleado_id bigint = NULL,
    @cuenta_dominio nvarchar(256) = NULL,
    @rol_usado nvarchar(30) = NULL,
    @linea_id bigint = NULL,
    @orden_id bigint = NULL,
    @sesion_linea_id bigint = NULL,
    @entidad nvarchar(80),
    @entidad_id bigint = NULL,
    @valor_anterior nvarchar(max) = NULL,
    @valor_nuevo nvarchar(max) = NULL,
    @motivo nvarchar(1000) = NULL,
    @correlacion_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @empleado_id IS NULL AND @cuenta_dominio IS NULL
        THROW 51100, 'El evento de auditoria requiere autor.', 1;

    IF @valor_anterior IS NOT NULL AND ISJSON(@valor_anterior) <> 1
        THROW 51101, 'valor_anterior no es JSON valido.', 1;

    IF @valor_nuevo IS NOT NULL AND ISJSON(@valor_nuevo) <> 1
        THROW 51102, 'valor_nuevo no es JSON valido.', 1;

    INSERT aud.eventos
    (
        tipo_evento, empleado_id, cuenta_dominio, rol_usado,
        linea_id, orden_id, sesion_linea_id, entidad, entidad_id,
        valor_anterior, valor_nuevo, motivo, correlacion_id
    )
    VALUES
    (
        @tipo_evento, @empleado_id, @cuenta_dominio, @rol_usado,
        @linea_id, @orden_id, @sesion_linea_id, @entidad, @entidad_id,
        @valor_anterior, @valor_nuevo, @motivo, @correlacion_id
    );
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE nav.confirmar_salida_palet
    @operacion_nav_id bigint,
    @respuesta nvarchar(max) = NULL,
    @identificador_externo nvarchar(100) = NULL,
    @correlacion_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE
        @orden_id bigint,
        @palet_id bigint,
        @sesion_linea_id bigint,
        @linea_id bigint,
        @etiqueta_id bigint,
        @etiqueta_uid uniqueidentifier,
        @impresora_id bigint;

    SELECT
        @orden_id = orden_id,
        @palet_id = palet_id
    FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
    WHERE operacion_nav_id = @operacion_nav_id
      AND tipo = N'SALIDA_PALET'
      AND estado IN (N'PENDIENTE', N'PROCESANDO', N'ERROR_REINTENTABLE', N'RESULTADO_DESCONOCIDO');

    IF @palet_id IS NULL
        THROW 51500, 'Operacion NAV de salida de palet no encontrada o no confirmable.', 1;

    SELECT
        @sesion_linea_id = p.sesion_linea_id,
        @linea_id = s.linea_id
    FROM prod.palets p
    JOIN prod.sesiones_linea s ON s.sesion_linea_id = p.sesion_linea_id
    WHERE p.palet_id = @palet_id
      AND p.orden_id = @orden_id;

    SELECT
        @etiqueta_id = etiqueta_id,
        @etiqueta_uid = etiqueta_uid
    FROM imp.etiquetas WITH (UPDLOCK, HOLDLOCK)
    WHERE palet_id = @palet_id
      AND orden_id = @orden_id
      AND tipo = N'PALET'
      AND estado = N'PENDIENTE_NAV';

    IF @etiqueta_id IS NULL
        THROW 51501, 'No existe una etiqueta pendiente de NAV para el palet.', 1;

    UPDATE nav.operaciones
    SET estado = N'CONFIRMADA',
        respuesta = @respuesta,
        identificador_externo = @identificador_externo,
        numero_intentos = numero_intentos + 1,
        proximo_intento_utc = NULL,
        procesada_utc = SYSUTCDATETIME()
    WHERE operacion_nav_id = @operacion_nav_id;

    UPDATE imp.etiquetas
    SET estado = N'LISTA',
        habilitada_utc = SYSUTCDATETIME()
    WHERE etiqueta_id = @etiqueta_id;

    SELECT TOP (1) @impresora_id = li.impresora_id
    FROM cfg.lineas_impresoras li
    JOIN cfg.impresoras i ON i.impresora_id = li.impresora_id
    WHERE li.linea_id = @linea_id
      AND li.asignado_hasta_utc IS NULL
      AND li.es_principal = 1
      AND i.activa = 1
    ORDER BY li.asignado_desde_utc DESC;

    IF @impresora_id IS NULL
    BEGIN
        UPDATE imp.etiquetas
        SET estado = N'ERROR'
        WHERE etiqueta_id = @etiqueta_id;

        UPDATE prod.estados_linea
        SET estado = N'BLOQUEADA',
            motivo_bloqueo = N'IMPRESORA_PRINCIPAL_NO_DISPONIBLE',
            actualizado_utc = SYSUTCDATETIME()
        WHERE linea_id = @linea_id
          AND sesion_linea_id = @sesion_linea_id;
    END
    ELSE
    BEGIN
        INSERT imp.trabajos_impresion
        (
            etiqueta_id, impresora_solicitada_id, clave_idempotencia,
            es_reimpresion, estado
        )
        VALUES
        (
            @etiqueta_id, @impresora_id,
            CONCAT(N'MES:PRINT:', CONVERT(nvarchar(36), @etiqueta_uid), N':ORIGINAL'),
            0, N'PENDIENTE'
        );
    END;

    EXEC aud.registrar_evento
        @tipo_evento = N'SALIDA_PALET_NAV_CONFIRMADA',
        @cuenta_dominio = N'EBIR\MES$',
        @linea_id = @linea_id,
        @orden_id = @orden_id,
        @sesion_linea_id = @sesion_linea_id,
        @entidad = N'nav.operaciones',
        @entidad_id = @operacion_nav_id,
        @correlacion_id = @correlacion_id;

    COMMIT;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE imp.confirmar_trabajo_impresion
    @trabajo_impresion_id bigint,
    @impresora_utilizada_id bigint,
    @correlacion_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE
        @etiqueta_id bigint,
        @tipo_etiqueta nvarchar(30),
        @orden_id bigint,
        @palet_id bigint,
        @palet_uid uniqueidentifier,
        @es_ultimo bit,
        @sesion_linea_id bigint,
        @linea_id bigint,
        @numero_orden nvarchar(30),
        @payload_cierre nvarchar(max);

    SELECT @etiqueta_id = etiqueta_id
    FROM imp.trabajos_impresion WITH (UPDLOCK, HOLDLOCK)
    WHERE trabajo_impresion_id = @trabajo_impresion_id
      AND estado IN (N'PENDIENTE', N'PROCESANDO');

    IF @etiqueta_id IS NULL
        THROW 51600, 'Trabajo de impresion no encontrado o no confirmable.', 1;

    IF NOT EXISTS
    (
        SELECT 1 FROM cfg.impresoras
        WHERE impresora_id = @impresora_utilizada_id
          AND activa = 1
    )
        THROW 51601, 'La impresora utilizada no existe o no esta activa.', 1;

    SELECT
        @tipo_etiqueta = e.tipo,
        @orden_id = e.orden_id,
        @palet_id = e.palet_id
    FROM imp.etiquetas e WITH (UPDLOCK, HOLDLOCK)
    WHERE e.etiqueta_id = @etiqueta_id
      AND e.estado = N'LISTA';

    IF @tipo_etiqueta IS NULL
        THROW 51602, 'La etiqueta no esta lista para confirmar su impresion.', 1;

    UPDATE imp.trabajos_impresion
    SET impresora_utilizada_id = @impresora_utilizada_id,
        estado = N'COMPLETADO',
        procesado_utc = SYSUTCDATETIME()
    WHERE trabajo_impresion_id = @trabajo_impresion_id;

    UPDATE imp.etiquetas
    SET estado = N'IMPRESA',
        impresa_utc = SYSUTCDATETIME()
    WHERE etiqueta_id = @etiqueta_id;

    IF @tipo_etiqueta = N'PALET'
    BEGIN
        SELECT
            @palet_uid = p.palet_uid,
            @es_ultimo = p.es_ultimo,
            @sesion_linea_id = p.sesion_linea_id,
            @linea_id = s.linea_id,
            @numero_orden = o.numero_orden
        FROM prod.palets p
        JOIN prod.sesiones_linea s ON s.sesion_linea_id = p.sesion_linea_id
        JOIN prod.ordenes o ON o.orden_id = p.orden_id
        WHERE p.palet_id = @palet_id
          AND p.orden_id = @orden_id;

        IF @es_ultimo = 0
        BEGIN
            UPDATE prod.estados_linea
            SET estado = N'PRODUCIENDO',
                motivo_bloqueo = NULL,
                actualizado_utc = SYSUTCDATETIME()
            WHERE linea_id = @linea_id
              AND sesion_linea_id = @sesion_linea_id
              AND estado = N'PENDIENTE_NAV';
        END
        ELSE
        BEGIN
            SELECT @payload_cierre =
            (
                SELECT
                    @orden_id AS orden_id,
                    @numero_orden AS numero_orden,
                    @palet_uid AS ultimo_palet_uid
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            IF NOT EXISTS
            (
                SELECT 1 FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
                WHERE clave_idempotencia = CONCAT(N'MES:CIERRE_FL:', CONVERT(nvarchar(20), @orden_id))
            )
                INSERT nav.operaciones
                (
                    clave_idempotencia, tipo, orden_id, estado,
                    payload, proximo_intento_utc
                )
                VALUES
                (
                    CONCAT(N'MES:CIERRE_FL:', CONVERT(nvarchar(20), @orden_id)),
                    N'CIERRE_FL', @orden_id, N'PENDIENTE',
                    @payload_cierre, SYSUTCDATETIME()
                );

            UPDATE prod.ordenes
            SET estado = N'PENDIENTE_NAV'
            WHERE orden_id = @orden_id;

            UPDATE prod.estados_linea
            SET estado = N'PENDIENTE_NAV',
                motivo_bloqueo = N'CIERRE_FL_PENDIENTE',
                actualizado_utc = SYSUTCDATETIME()
            WHERE linea_id = @linea_id
              AND sesion_linea_id = @sesion_linea_id;
        END;
    END;

    EXEC aud.registrar_evento
        @tipo_evento = N'ETIQUETA_IMPRESA',
        @cuenta_dominio = N'EBIR\MES$',
        @linea_id = @linea_id,
        @orden_id = @orden_id,
        @sesion_linea_id = @sesion_linea_id,
        @entidad = N'imp.trabajos_impresion',
        @entidad_id = @trabajo_impresion_id,
        @correlacion_id = @correlacion_id;

    COMMIT;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.reservar_palet
    @orden_id bigint,
    @sesion_linea_id bigint,
    @cantidad int,
    @empleado_id bigint,
    @correlacion_id uniqueidentifier,
    @reserva_palet_id bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @cantidad <= 0
        THROW 51200, 'La cantidad reservada debe ser positiva.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM seg.empleados_roles er
        JOIN seg.roles r ON r.rol_id = er.rol_id
        WHERE er.empleado_id = @empleado_id
          AND er.hasta_utc IS NULL
          AND r.codigo IN (N'OPERARIO', N'SUPERVISOR')
          AND r.activo = 1
    )
        THROW 51206, 'La reserva requiere operario o supervisor activo.', 1;

    BEGIN TRANSACTION;

    DECLARE
        @objetivo int,
        @buenas int,
        @reservadas int,
        @estado nvarchar(30),
        @sesion_orden_id bigint,
        @linea_id bigint,
        @unidades_formato int,
        @cantidad_esperada int;

    SELECT
        @objetivo = cantidad_objetivo,
        @buenas = cantidad_buena_acumulada,
        @reservadas = cantidad_reservada_activa,
        @estado = estado
    FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
    WHERE orden_id = @orden_id;

    IF @objetivo IS NULL
        THROW 51201, 'Orden no encontrada.', 1;

    IF @estado NOT IN (N'IMPORTADA', N'ABIERTA', N'PICO_PENDIENTE')
        THROW 51202, 'La orden no admite nuevas reservas.', 1;

    SELECT
        @sesion_orden_id = s.orden_id,
        @linea_id = s.linea_id,
        @unidades_formato = f.unidades_por_palet
    FROM prod.sesiones_linea s WITH (UPDLOCK, HOLDLOCK)
    JOIN prod.formatos_palet_orden f
      ON f.formato_palet_orden_id = s.formato_palet_orden_id
     AND f.orden_id = s.orden_id
    WHERE s.sesion_linea_id = @sesion_linea_id
      AND s.finalizada_utc IS NULL;

    IF @sesion_orden_id IS NULL OR @sesion_orden_id <> @orden_id
        THROW 51203, 'La sesion no esta activa o no pertenece a la orden.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM prod.estados_linea
        WHERE linea_id = @linea_id
          AND estado IN (N'PENDIENTE_NAV', N'BLOQUEADA', N'FUERA_SERVICIO')
    )
        THROW 51208, 'La linea no admite nuevas reservas en su estado actual.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM prod.reservas_palet
        WHERE sesion_linea_id = @sesion_linea_id
          AND estado = N'ACTIVA'
    )
        THROW 51204, 'La sesion ya tiene una reserva activa.', 1;

    IF @buenas + @reservadas + @cantidad > @objetivo
        THROW 51205, 'La reserva supera el pendiente disponible global.', 1;

    SET @cantidad_esperada =
        CASE
            WHEN @objetivo - @buenas - @reservadas < @unidades_formato
                THEN @objetivo - @buenas - @reservadas
            ELSE @unidades_formato
        END;

    IF @cantidad <> @cantidad_esperada
        THROW 51207, 'La cantidad no coincide con el formato efectivo o el ultimo pendiente disponible.', 1;

    INSERT prod.reservas_palet
    (
        orden_id, sesion_linea_id, cantidad_reservada,
        estado, creada_por_empleado_id
    )
    VALUES
    (
        @orden_id, @sesion_linea_id, @cantidad,
        N'ACTIVA', @empleado_id
    );

    SET @reserva_palet_id = SCOPE_IDENTITY();

    UPDATE prod.ordenes
    SET cantidad_reservada_activa = cantidad_reservada_activa + @cantidad,
        estado = N'ABIERTA'
    WHERE orden_id = @orden_id;

    EXEC aud.registrar_evento
        @tipo_evento = N'RESERVA_PALET_CREADA',
        @empleado_id = @empleado_id,
        @rol_usado = NULL,
        @linea_id = @linea_id,
        @orden_id = @orden_id,
        @sesion_linea_id = @sesion_linea_id,
        @entidad = N'prod.reservas_palet',
        @entidad_id = @reserva_palet_id,
        @valor_nuevo = NULL,
        @correlacion_id = @correlacion_id;

    COMMIT;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.cancelar_reserva_palet
    @reserva_palet_id bigint,
    @supervisor_id bigint,
    @motivo nvarchar(500),
    @correlacion_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(RTRIM(@motivo)), N'') IS NULL
        THROW 51300, 'La cancelacion requiere motivo.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM seg.empleados_roles er
        JOIN seg.roles r ON r.rol_id = er.rol_id
        WHERE er.empleado_id = @supervisor_id
          AND er.hasta_utc IS NULL
          AND r.codigo = N'SUPERVISOR'
          AND r.activo = 1
    )
        THROW 51301, 'La cancelacion requiere supervisor activo.', 1;

    BEGIN TRANSACTION;

    DECLARE
        @orden_id bigint,
        @sesion_linea_id bigint,
        @cantidad int,
        @linea_id bigint;

    SELECT
        @orden_id = r.orden_id,
        @sesion_linea_id = r.sesion_linea_id,
        @cantidad = r.cantidad_reservada,
        @linea_id = s.linea_id
    FROM prod.reservas_palet r WITH (UPDLOCK, HOLDLOCK)
    JOIN prod.sesiones_linea s ON s.sesion_linea_id = r.sesion_linea_id
    WHERE r.reserva_palet_id = @reserva_palet_id
      AND r.estado = N'ACTIVA';

    IF @orden_id IS NULL
        THROW 51302, 'Reserva activa no encontrada.', 1;

    SELECT orden_id
    FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
    WHERE orden_id = @orden_id;

    UPDATE prod.reservas_palet
    SET estado = N'CANCELADA',
        cerrada_utc = SYSUTCDATETIME(),
        cancelada_por_empleado_id = @supervisor_id,
        motivo_cancelacion = @motivo
    WHERE reserva_palet_id = @reserva_palet_id;

    UPDATE prod.ordenes
    SET cantidad_reservada_activa = cantidad_reservada_activa - @cantidad
    WHERE orden_id = @orden_id;

    EXEC aud.registrar_evento
        @tipo_evento = N'RESERVA_PALET_CANCELADA',
        @empleado_id = @supervisor_id,
        @rol_usado = N'SUPERVISOR',
        @linea_id = @linea_id,
        @orden_id = @orden_id,
        @sesion_linea_id = @sesion_linea_id,
        @entidad = N'prod.reservas_palet',
        @entidad_id = @reserva_palet_id,
        @motivo = @motivo,
        @correlacion_id = @correlacion_id;

    COMMIT;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.cerrar_palet
    @reserva_palet_id bigint,
    @cantidad_buena int,
    @cerrado_por_empleado_id bigint,
    @supervisor_autorizador_id bigint = NULL,
    @es_parcial bit = 0,
    @motivo_parcial nvarchar(30) = NULL,
    @correlacion_id uniqueidentifier,
    @palet_id bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @cantidad_buena <= 0
        THROW 51400, 'La cantidad del palet debe ser positiva.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM seg.empleados_roles er
        JOIN seg.roles r ON r.rol_id = er.rol_id
        WHERE er.empleado_id = @cerrado_por_empleado_id
          AND er.hasta_utc IS NULL
          AND r.codigo IN (N'OPERARIO', N'SUPERVISOR')
          AND r.activo = 1
    )
        THROW 51401, 'El cierre requiere operario o supervisor activo.', 1;

    IF @es_parcial = 1 AND @motivo_parcial NOT IN (N'FIN_TURNO', N'FALTA_MATERIAL', N'ULTIMO_PALET')
        THROW 51402, 'El palet parcial requiere un motivo permitido.', 1;

    BEGIN TRANSACTION;

    DECLARE
        @orden_id bigint,
        @sesion_linea_id bigint,
        @cantidad_reservada int,
        @linea_id bigint,
        @supervisor_responsable_id bigint,
        @objetivo int,
        @buenas int,
        @reservadas int,
        @numero_palet int,
        @numero_orden nvarchar(30),
        @producto_codigo nvarchar(50),
        @producto_descripcion nvarchar(250),
        @producto_barcode nvarchar(100),
        @lote nvarchar(50),
        @linea_codigo nvarchar(20),
        @linea_nombre nvarchar(100),
        @turno_codigo nvarchar(20),
        @fecha_operativa date,
        @cerrado_nombre nvarchar(200),
        @supervisor_nombre nvarchar(200),
        @autorizador_nombre nvarchar(200),
        @cerrado_utc datetime2(3),
        @es_ultimo bit,
        @palet_uid uniqueidentifier,
        @codigo_visible nvarchar(100),
        @payload_nav nvarchar(max),
        @datos_etiqueta nvarchar(max),
        @unidades_formato int,
        @siguiente_reserva int,
        @nuevas_buenas int,
        @reservadas_tras_consumo int;

    SELECT
        @orden_id = r.orden_id,
        @sesion_linea_id = r.sesion_linea_id,
        @cantidad_reservada = r.cantidad_reservada,
        @linea_id = s.linea_id,
        @supervisor_responsable_id = s.cargada_por_empleado_id,
        @unidades_formato = f.unidades_por_palet,
        @linea_codigo = l.codigo,
        @linea_nombre = l.nombre,
        @turno_codigo = t.codigo,
        @fecha_operativa = s.fecha_operativa
    FROM prod.reservas_palet r WITH (UPDLOCK, HOLDLOCK)
    JOIN prod.sesiones_linea s ON s.sesion_linea_id = r.sesion_linea_id
    JOIN cfg.lineas l ON l.linea_id = s.linea_id
    JOIN cfg.turnos t ON t.turno_id = s.turno_id
    JOIN prod.formatos_palet_orden f
      ON f.formato_palet_orden_id = s.formato_palet_orden_id
     AND f.orden_id = s.orden_id
    WHERE r.reserva_palet_id = @reserva_palet_id
      AND r.estado = N'ACTIVA'
      AND s.finalizada_utc IS NULL;

    IF @orden_id IS NULL
        THROW 51403, 'Reserva activa no encontrada.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM prod.estados_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE linea_id = @linea_id
          AND sesion_linea_id = @sesion_linea_id
          AND estado NOT IN (N'PENDIENTE_NAV', N'BLOQUEADA', N'FUERA_SERVICIO')
    )
        THROW 51408, 'La linea no admite cierres o no corresponde a la sesion activa.', 1;

    IF @cantidad_buena > @cantidad_reservada
        THROW 51404, 'La cantidad buena supera la reserva.', 1;

    IF @cantidad_buena < @cantidad_reservada AND @es_parcial = 0
        THROW 51405, 'Una cantidad inferior a la reserva requiere cierre parcial.', 1;

    SELECT
        @objetivo = cantidad_objetivo,
        @buenas = cantidad_buena_acumulada,
        @reservadas = cantidad_reservada_activa,
        @numero_orden = numero_orden,
        @producto_codigo = producto_codigo,
        @producto_descripcion = producto_descripcion,
        @producto_barcode = producto_barcode,
        @lote = lote
    FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
    WHERE orden_id = @orden_id;

    IF @buenas + @cantidad_buena > @objetivo
        THROW 51406, 'El cierre supera el objetivo bueno.', 1;

    SET @es_ultimo = CASE WHEN @buenas + @cantidad_buena = @objetivo THEN 1 ELSE 0 END;

    IF @es_ultimo = 1 AND @reservadas <> @cantidad_reservada
        THROW 51409, 'No puede cerrarse el ultimo palet mientras existan reservas activas en otras lineas.', 1;

    IF (@es_ultimo = 1 OR @es_parcial = 1)
       AND NOT EXISTS
       (
           SELECT 1
           FROM seg.empleados_roles er
           JOIN seg.roles r ON r.rol_id = er.rol_id
           WHERE er.empleado_id = @supervisor_autorizador_id
             AND er.hasta_utc IS NULL
             AND r.codigo = N'SUPERVISOR'
             AND r.activo = 1
       )
        THROW 51407, 'El ultimo palet o un palet parcial requiere supervisor.', 1;

    SELECT @numero_palet = ISNULL(MAX(numero_palet), 0) + 1
    FROM prod.palets WITH (UPDLOCK, HOLDLOCK)
    WHERE orden_id = @orden_id;

    SET @palet_uid = NEWID();
    SET @codigo_visible = CONCAT(@numero_orden, N'/', RIGHT(N'000000' + CONVERT(nvarchar(12), @numero_palet), 6));
    SET @cerrado_utc = SYSUTCDATETIME();

    SELECT @cerrado_nombre = nombre_completo
    FROM seg.empleados WHERE empleado_id = @cerrado_por_empleado_id;

    SELECT @supervisor_nombre = nombre_completo
    FROM seg.empleados WHERE empleado_id = @supervisor_responsable_id;

    SELECT @autorizador_nombre = nombre_completo
    FROM seg.empleados WHERE empleado_id = @supervisor_autorizador_id;

    INSERT prod.palets
    (
        palet_uid, orden_id, sesion_linea_id, reserva_palet_id,
        numero_palet, codigo_visible, cantidad_buena,
        es_parcial, motivo_parcial, es_ultimo,
        cerrado_por_empleado_id, supervisor_responsable_id,
        autorizado_por_supervisor_id, cerrado_utc
    )
    VALUES
    (
        @palet_uid, @orden_id, @sesion_linea_id, @reserva_palet_id,
        @numero_palet, @codigo_visible, @cantidad_buena,
        @es_parcial, @motivo_parcial, @es_ultimo,
        @cerrado_por_empleado_id, @supervisor_responsable_id,
        @supervisor_autorizador_id, @cerrado_utc
    );

    SET @palet_id = SCOPE_IDENTITY();

    UPDATE prod.reservas_palet
    SET estado = N'CONSUMIDA',
        cerrada_utc = SYSUTCDATETIME()
    WHERE reserva_palet_id = @reserva_palet_id;

    SET @nuevas_buenas = @buenas + @cantidad_buena;
    SET @reservadas_tras_consumo = @reservadas - @cantidad_reservada;
    SET @siguiente_reserva = 0;

    IF @es_ultimo = 0 AND @es_parcial = 0
    BEGIN
        SET @siguiente_reserva =
            CASE
                WHEN @objetivo - @nuevas_buenas - @reservadas_tras_consumo <= 0 THEN 0
                WHEN @objetivo - @nuevas_buenas - @reservadas_tras_consumo < @unidades_formato
                    THEN @objetivo - @nuevas_buenas - @reservadas_tras_consumo
                ELSE @unidades_formato
            END;

        IF @siguiente_reserva > 0
            INSERT prod.reservas_palet
            (
                orden_id, sesion_linea_id, cantidad_reservada,
                estado, creada_por_empleado_id
            )
            VALUES
            (
                @orden_id, @sesion_linea_id, @siguiente_reserva,
                N'ACTIVA', @cerrado_por_empleado_id
            );
    END;

    UPDATE prod.ordenes
    SET cantidad_buena_acumulada = @nuevas_buenas,
        cantidad_reservada_activa = @reservadas_tras_consumo + @siguiente_reserva,
        estado = CASE WHEN @es_ultimo = 1 THEN N'PENDIENTE_CIERRE' ELSE N'ABIERTA' END
    WHERE orden_id = @orden_id;

    UPDATE prod.estados_linea
    SET estado = N'PENDIENTE_NAV',
        motivo_bloqueo = N'SALIDA_PALET_PENDIENTE',
        actualizado_utc = SYSUTCDATETIME()
    WHERE linea_id = @linea_id;

    SELECT @payload_nav =
    (
        SELECT
            @palet_uid AS palet_uid,
            @numero_orden AS numero_orden,
            @numero_palet AS numero_palet,
            @cantidad_buena AS cantidad_buena,
            @linea_id AS linea_id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    SELECT @datos_etiqueta =
    (
        SELECT
            @palet_uid AS palet_uid,
            @codigo_visible AS codigo_palet,
            @numero_palet AS numero_palet,
            @producto_codigo AS producto_codigo,
            @producto_descripcion AS producto_descripcion,
            @producto_barcode AS producto_barcode,
            @numero_orden AS numero_orden,
            @lote AS lote,
            @cantidad_buena AS cantidad,
            @linea_id AS linea_id,
            @linea_codigo AS linea_codigo,
            @linea_nombre AS linea_nombre,
            @turno_codigo AS turno_codigo,
            @fecha_operativa AS fecha_operativa,
            @cerrado_utc AS cerrado_utc,
            @cerrado_por_empleado_id AS cerrado_por_empleado_id,
            @cerrado_nombre AS cerrado_por,
            @supervisor_responsable_id AS supervisor_responsable_id,
            @supervisor_nombre AS supervisor_responsable,
            @supervisor_autorizador_id AS supervisor_autorizador_id,
            @autorizador_nombre AS supervisor_autorizador
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    INSERT nav.operaciones
    (
        clave_idempotencia, tipo, orden_id, palet_id,
        estado, payload, proximo_intento_utc
    )
    VALUES
    (
        CONCAT(N'MES:PALET:', CONVERT(nvarchar(36), @palet_uid)),
        N'SALIDA_PALET', @orden_id, @palet_id,
        N'PENDIENTE', @payload_nav, SYSUTCDATETIME()
    );

    INSERT imp.etiquetas
    (
        tipo, orden_id, palet_id, codigo_visible,
        plantilla_codigo, plantilla_version, datos_etiqueta,
        estado, numero_copias
    )
    VALUES
    (
        N'PALET', @orden_id, @palet_id, @codigo_visible,
        N'PALET', 1, @datos_etiqueta,
        N'PENDIENTE_NAV', 1
    );

    EXEC aud.registrar_evento
        @tipo_evento = N'PALET_CERRADO',
        @empleado_id = @cerrado_por_empleado_id,
        @rol_usado = NULL,
        @linea_id = @linea_id,
        @orden_id = @orden_id,
        @sesion_linea_id = @sesion_linea_id,
        @entidad = N'prod.palets',
        @entidad_id = @palet_id,
        @correlacion_id = @correlacion_id;

    COMMIT;
END;
GO
