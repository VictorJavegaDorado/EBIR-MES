SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 53800, 'Prueba permitida unicamente en EBIR_MES_TEST.', 1;
IF OBJECT_ID(N'imp.reservar_siguiente_trabajo_impresion', N'P') IS NULL
 OR OBJECT_ID(N'imp.completar_trabajo_impresion', N'P') IS NULL
 OR OBJECT_ID(N'imp.fallar_trabajo_impresion', N'P') IS NULL
    THROW 53801, 'El paquete 018 no esta instalado.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @orden_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'FL20-02277');
    IF @orden_id IS NULL
        THROW 53802, 'Falta la orden controlada FL20-02277.', 1;

    INSERT cfg.impresoras
    (
        codigo, nombre, modelo, nombre_red, direccion_ip,
        protocolo, resolucion_dpi, activa
    )
    VALUES
    (
        N'ZZ18-SIM', N'Impresora simulada 018', N'SIMULADA',
        NULL, NULL, N'SIMULATED', 300, 1
    );
    DECLARE @impresora_id bigint = SCOPE_IDENTITY();

    INSERT imp.etiquetas
    (
        tipo, orden_id, palet_id, codigo_visible, plantilla_codigo,
        plantilla_version, datos_etiqueta, estado, numero_copias,
        habilitada_utc
    )
    VALUES
    (
        N'SALIDA_FABRICA', @orden_id, NULL, N'ZZ18-LABEL', N'PALET',
        1,
        N'{"codigo_palet":"ZZ18-LABEL","numero_orden":"FL20-02277","producto_codigo":"27979CI","lote":"FL2002277","cantidad":10}',
        N'LISTA', 1, SYSUTCDATETIME()
    );
    DECLARE @etiqueta_id bigint = SCOPE_IDENTITY();

    INSERT imp.trabajos_impresion
    (
        etiqueta_id, impresora_solicitada_id, clave_idempotencia,
        es_reimpresion, estado
    )
    VALUES
    (
        @etiqueta_id, @impresora_id, N'ZZ18:PRINT:ORIGINAL', 0, N'PENDIENTE'
    );
    DECLARE @trabajo_id bigint = SCOPE_IDENTITY();

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
        EXEC imp.reservar_siguiente_trabajo_impresion @worker_id = N'ZZ18-WORKER';

    IF NOT EXISTS
    (
        SELECT 1 FROM @reserva
        WHERE trabajo_impresion_id = @trabajo_id
          AND impresora_codigo = N'ZZ18-SIM'
          AND JSON_VALUE(datos_etiqueta, '$.lote') = N'FL2002277'
          AND numero_intentos = 1
    )
        THROW 53803, 'La reserva no devolvio la etiqueta y el lote esperados.', 1;

    DECLARE @correlacion uniqueidentifier = NEWID();
    EXEC imp.completar_trabajo_impresion
        @trabajo_impresion_id = @trabajo_id,
        @numero_intento = 1,
        @impresora_utilizada_id = @impresora_id,
        @correlacion_id = @correlacion,
        @datos_tecnicos = N'{"adapter":"SimulatedPrinter","simulated":true}';

    IF NOT EXISTS
    (
        SELECT 1 FROM imp.trabajos_impresion
        WHERE trabajo_impresion_id = @trabajo_id
          AND estado = N'COMPLETADO'
          AND numero_intentos = 1
          AND reservado_utc IS NULL
          AND reservado_por IS NULL
    )
     OR NOT EXISTS
    (
        SELECT 1 FROM imp.etiquetas
        WHERE etiqueta_id = @etiqueta_id AND estado = N'IMPRESA'
    )
     OR NOT EXISTS
    (
        SELECT 1 FROM imp.intentos_impresion
        WHERE trabajo_impresion_id = @trabajo_id
          AND numero_intento = 1 AND resultado = N'COMPLETADO'
          AND JSON_VALUE(datos_tecnicos, '$.simulated') = N'true'
    )
     OR NOT EXISTS
    (
        SELECT 1 FROM aud.eventos
        WHERE correlacion_id = @correlacion
          AND tipo_evento = N'ETIQUETA_IMPRESA'
    )
        THROW 53804, 'La confirmacion simulada no quedo trazada correctamente.', 1;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

IF EXISTS (SELECT 1 FROM cfg.impresoras WHERE codigo = N'ZZ18-SIM')
 OR EXISTS (SELECT 1 FROM imp.etiquetas WHERE codigo_visible = N'ZZ18-LABEL')
 OR EXISTS (SELECT 1 FROM imp.trabajos_impresion WHERE clave_idempotencia = N'ZZ18:PRINT:ORIGINAL')
    THROW 53805, 'La prueba 018 no revirtio todos los fixtures.', 1;

PRINT N'PRUEBAS FUNCIONALES 018: OK';
