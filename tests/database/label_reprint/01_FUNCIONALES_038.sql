/* Prueba transaccional 038. No ejecutar sin autorizacion. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 57900, 'Prueba permitida unicamente en EBIR_MES_TEST.', 1;
IF OBJECT_ID(N'imp.solicitar_reimpresion_palet', N'P') IS NULL
    THROW 57901, 'El paquete 038A no esta instalado.', 1;
IF EXISTS (SELECT 1 FROM cfg.lineas WHERE codigo = N'ZZ38-REPRINT')
 OR EXISTS (SELECT 1 FROM seg.empleados WHERE codigo_nav = N'ZZ38-SUP')
 OR EXISTS (SELECT 1 FROM prod.ordenes WHERE numero_orden = N'ZZ38-ORDER')
    THROW 57902, 'Existen fixtures ZZ38 pendientes de revision.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE
        @entorno_id smallint =
            (SELECT entorno_nav_id FROM nav.entornos WHERE codigo = N'EBIRTEST'),
        @centro_id bigint =
            (SELECT TOP (1) centro_trabajo_id FROM cfg.centros_trabajo ORDER BY centro_trabajo_id),
        @turno_id smallint =
            (SELECT TOP (1) turno_id FROM cfg.turnos WHERE activo = 1 ORDER BY turno_id),
        @rol_supervisor_id smallint =
            (SELECT rol_id FROM seg.roles WHERE codigo = N'SUPERVISOR' AND activo = 1);
    IF @entorno_id IS NULL OR @centro_id IS NULL
       OR @turno_id IS NULL OR @rol_supervisor_id IS NULL
        THROW 57903, 'Faltan catalogos base para la prueba.', 1;

    INSERT nav.empresas (entorno_nav_id, codigo, nombre, activo)
    VALUES (@entorno_id, N'ZZTEST_038', N'ZZTEST 038', 1);
    DECLARE @empresa_id bigint = SCOPE_IDENTITY();

    INSERT cfg.lineas (centro_trabajo_id, codigo, nombre, descripcion, activa)
    VALUES (@centro_id, N'ZZ38-REPRINT', N'ZZTEST 038 reimpresion', N'Sintetica', 1);
    DECLARE @linea_id bigint = SCOPE_IDENTITY();

    INSERT cfg.impresoras
    (
        codigo, nombre, modelo, protocolo, resolucion_dpi, activa
    )
    VALUES
    (
        N'ZZ38-SIM', N'ZZTEST 038 simulada', N'SIMULADA', N'SIMULATED', 300, 1
    );
    DECLARE @impresora_id bigint = SCOPE_IDENTITY();

    INSERT seg.empleados
    (
        codigo_nav, nombre_completo, activo_nav, activo_mes, sincronizado_nav_utc
    )
    VALUES
    (
        N'ZZ38-SUP', N'ZZTEST 038 Supervisor', 1, 1, SYSUTCDATETIME()
    );
    DECLARE @supervisor_id bigint = SCOPE_IDENTITY();

    INSERT seg.empleados_roles
    (
        empleado_id, rol_id, desde_utc, asignado_por_cuenta, motivo
    )
    VALUES
    (
        @supervisor_id, @rol_supervisor_id, SYSUTCDATETIME(),
        N'ZZTEST_038', N'Fixture sintetico'
    );

    INSERT cfg.lineas_impresoras
    (
        linea_id, impresora_id, es_principal, asignado_desde_utc,
        asignado_por_cuenta, motivo
    )
    VALUES
    (
        @linea_id, @impresora_id, 1, SYSUTCDATETIME(),
        N'ZZTEST_038', N'Fixture sintetico'
    );

    INSERT prod.ordenes
    (
        empresa_nav_id, numero_orden, producto_codigo, producto_descripcion,
        producto_barcode, lote, cantidad_objetivo, tiempo_ejecucion_nav_min,
        modo_trabajo, estado, datos_nav_originales
    )
    VALUES
    (
        @empresa_id, N'ZZ38-ORDER', N'ZZ38-PRODUCT', N'ZZTEST 038 producto',
        N'ZZ38-BARCODE', N'ZZ38-LOT', 20, 1, N'NORMAL', N'ABIERTA',
        N'{"origen":"ZZTEST_038"}'
    );
    DECLARE @orden_id bigint = SCOPE_IDENTITY();

    INSERT prod.formatos_palet_orden
    (
        orden_id, codigo_formato, unidades_por_palet, descripcion,
        es_predeterminado_nav, datos_nav_originales, activo
    )
    VALUES
    (
        @orden_id, N'ZZ38-FMT', 20, N'ZZTEST 038 formato',
        1, N'{"origen":"ZZTEST_038"}', 1
    );
    DECLARE @formato_id bigint = SCOPE_IDENTITY();

    INSERT prod.sesiones_linea
    (
        orden_id, linea_id, turno_id, formato_palet_orden_id,
        fecha_operativa, estado, iniciada_utc, cargada_por_empleado_id
    )
    VALUES
    (
        @orden_id, @linea_id, @turno_id, @formato_id,
        CONVERT(date, SYSUTCDATETIME()), N'PRODUCIENDO',
        SYSUTCDATETIME(), @supervisor_id
    );
    DECLARE @sesion_id bigint = SCOPE_IDENTITY();

    INSERT prod.estados_linea (linea_id, sesion_linea_id, estado)
    VALUES (@linea_id, @sesion_id, N'PRODUCIENDO');

    INSERT prod.reservas_palet
    (
        orden_id, sesion_linea_id, cantidad_reservada, estado,
        creada_por_empleado_id, cerrada_utc
    )
    VALUES
    (
        @orden_id, @sesion_id, 20, N'CONSUMIDA',
        @supervisor_id, SYSUTCDATETIME()
    );
    DECLARE @reserva_id bigint = SCOPE_IDENTITY();

    INSERT prod.palets
    (
        orden_id, sesion_linea_id, reserva_palet_id, numero_palet,
        codigo_visible, cantidad_buena, es_parcial, es_ultimo,
        cerrado_por_empleado_id, supervisor_responsable_id, estado
    )
    VALUES
    (
        @orden_id, @sesion_id, @reserva_id, 1,
        N'ZZ38-ORDER/000001', 20, 0, 0,
        @supervisor_id, @supervisor_id, N'CERRADO'
    );
    DECLARE @palet_id bigint = SCOPE_IDENTITY();

    DECLARE @impresa_utc datetime2(3) = DATEADD(MINUTE, -1, SYSUTCDATETIME());
    INSERT imp.etiquetas
    (
        tipo, orden_id, palet_id, codigo_visible, plantilla_codigo,
        plantilla_version, datos_etiqueta, estado, numero_copias,
        habilitada_utc, impresa_utc
    )
    VALUES
    (
        N'PALET', @orden_id, @palet_id, N'ZZ38-ORDER/000001', N'PALET',
        1, N'{"origen":"ZZTEST_038"}', N'IMPRESA', 1,
        DATEADD(MINUTE, -2, @impresa_utc), @impresa_utc
    );
    DECLARE @etiqueta_id bigint = SCOPE_IDENTITY();

    INSERT imp.trabajos_impresion
    (
        etiqueta_id, impresora_solicitada_id, impresora_utilizada_id,
        clave_idempotencia, es_reimpresion, estado, procesado_utc
    )
    VALUES
    (
        @etiqueta_id, @impresora_id, @impresora_id,
        N'ZZ38:PRINT:ORIGINAL', 0, N'COMPLETADO', @impresa_utc
    );

    DECLARE
        @correlacion uniqueidentifier = NEWID(),
        @trabajo_id bigint,
        @trabajo_repetido_id bigint;
    EXEC imp.solicitar_reimpresion_palet
        @palet_id = @palet_id,
        @solicitado_por_supervisor_id = @supervisor_id,
        @motivo = N'  Etiqueta sintetica no legible  ',
        @correlacion_id = @correlacion,
        @trabajo_impresion_id = @trabajo_id OUTPUT;

    EXEC imp.solicitar_reimpresion_palet
        @palet_id = @palet_id,
        @solicitado_por_supervisor_id = @supervisor_id,
        @motivo = N'Etiqueta sintetica no legible',
        @correlacion_id = @correlacion,
        @trabajo_impresion_id = @trabajo_repetido_id OUTPUT;

    IF @trabajo_id IS NULL OR @trabajo_repetido_id <> @trabajo_id
       OR (SELECT COUNT(*) FROM imp.trabajos_impresion
           WHERE etiqueta_id = @etiqueta_id AND es_reimpresion = 1) <> 1
       OR NOT EXISTS
       (
           SELECT 1 FROM imp.trabajos_impresion
           WHERE trabajo_impresion_id = @trabajo_id
             AND estado = N'PENDIENTE'
             AND es_reimpresion = 1
             AND solicitado_por_empleado_id = @supervisor_id
             AND motivo = N'Etiqueta sintetica no legible'
       )
       OR NOT EXISTS
       (
           SELECT 1 FROM imp.etiquetas
           WHERE etiqueta_id = @etiqueta_id
             AND estado = N'IMPRESA'
             AND impresa_utc = @impresa_utc
       )
        THROW 57904, 'La solicitud no fue unica o altero la etiqueta original.', 1;

    DECLARE @reserva TABLE
    (
        trabajo_impresion_id bigint, trabajo_uid uniqueidentifier,
        etiqueta_id bigint, etiqueta_uid uniqueidentifier,
        impresora_solicitada_id bigint, impresora_codigo nvarchar(30),
        impresora_modelo nvarchar(100), plantilla_codigo nvarchar(50),
        plantilla_version int, datos_etiqueta nvarchar(max),
        numero_copias smallint, numero_intentos int
    );
    INSERT @reserva
        EXEC imp.reservar_siguiente_trabajo_impresion
            @worker_id = N'ZZ38-WORKER';

    IF NOT EXISTS
    (
        SELECT 1 FROM @reserva
        WHERE trabajo_impresion_id = @trabajo_id
          AND etiqueta_id = @etiqueta_id
          AND impresora_codigo = N'ZZ38-SIM'
          AND numero_copias = 1
          AND numero_intentos = 1
    )
        THROW 57905, 'El Worker no reservo la copia sobre la etiqueta IMPRESA.', 1;

    DECLARE @correlacion_worker uniqueidentifier = NEWID();
    EXEC imp.completar_trabajo_impresion
        @trabajo_impresion_id = @trabajo_id,
        @numero_intento = 1,
        @impresora_utilizada_id = @impresora_id,
        @correlacion_id = @correlacion_worker,
        @datos_tecnicos = N'{"adapter":"SimulatedPrinter","simulated":true}';

    IF NOT EXISTS
    (
        SELECT 1 FROM imp.trabajos_impresion
        WHERE trabajo_impresion_id = @trabajo_id
          AND estado = N'COMPLETADO'
          AND numero_intentos = 1
    )
     OR NOT EXISTS
    (
        SELECT 1 FROM imp.intentos_impresion
        WHERE trabajo_impresion_id = @trabajo_id
          AND numero_intento = 1
          AND resultado = N'COMPLETADO'
    )
     OR NOT EXISTS
    (
        SELECT 1 FROM imp.etiquetas
        WHERE etiqueta_id = @etiqueta_id
          AND estado = N'IMPRESA'
          AND impresa_utc = @impresa_utc
    )
     OR NOT EXISTS
    (
        SELECT 1 FROM prod.estados_linea
        WHERE linea_id = @linea_id AND estado = N'PRODUCIENDO'
    )
     OR NOT EXISTS
    (
        SELECT 1 FROM aud.eventos
        WHERE correlacion_id = @correlacion_worker
          AND tipo_evento = N'ETIQUETA_REIMPRESA'
          AND entidad_id = @trabajo_id
    )
        THROW 57906, 'La copia modifico el original o no quedo auditada.', 1;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

IF EXISTS (SELECT 1 FROM cfg.lineas WHERE codigo = N'ZZ38-REPRINT')
 OR EXISTS (SELECT 1 FROM seg.empleados WHERE codigo_nav = N'ZZ38-SUP')
 OR EXISTS (SELECT 1 FROM prod.ordenes WHERE numero_orden = N'ZZ38-ORDER')
    THROW 57907, 'La prueba 038 no revirtio todos sus fixtures.', 1;

PRINT N'PRUEBAS FUNCIONALES 038: OK';
