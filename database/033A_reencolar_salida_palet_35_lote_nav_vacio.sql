/*
Paquete 033A - Reencolacion supervisada de la operacion 35.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV. Reencola exclusivamente la operacion 35 despues de demostrar
que el intento 1 solo leyo WS_CPP_OPLanzadas y fallo antes de cualquier llamada
SOAP porque NAV publico Cod_Lote_Salida vacio. El adaptador corregido conserva
el lote trazable MES cuando NAV no informa ese valor.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'nav.operaciones', N'U') IS NULL
 OR OBJECT_ID(N'nav.intentos_operacion', N'U') IS NULL
 OR OBJECT_ID(N'aud.eventos', N'U') IS NULL
 OR OBJECT_ID(N'prod.palets', N'U') IS NULL
 OR OBJECT_ID(N'prod.ordenes', N'U') IS NULL
 OR OBJECT_ID(N'nav.reservar_siguiente_salida_palet', N'P') IS NULL
    THROW 51086, 'El paquete 033A requiere 028A y la auditoria MES.', 1;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones n
    JOIN prod.palets p
      ON p.palet_id = n.palet_id
     AND p.orden_id = n.orden_id
    JOIN prod.ordenes o ON o.orden_id = n.orden_id
    WHERE n.operacion_nav_id = 35
      AND n.tipo = N'SALIDA_PALET'
      AND n.estado = N'ERROR_DEFINITIVO'
      AND n.numero_intentos = 1
      AND n.identificador_externo IS NULL
      AND n.reservado_utc IS NULL
      AND n.reservado_por IS NULL
      AND o.numero_orden = N'FL26-00003'
      AND o.producto_codigo = N'27920LG'
      AND p.palet_id = 25
      AND p.numero_palet = 5
      AND p.cantidad_buena = 20
      AND p.es_ultimo = 1
      AND p.autorizado_por_supervisor_id IS NOT NULL
      AND p.estado = N'CERRADO'
)
    THROW 51087, 'La operacion 35 no cumple el estado exacto de recuperacion.', 1;
GO

IF (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id = 35) <> 1
 OR NOT EXISTS
(
    SELECT 1
    FROM nav.intentos_operacion
    WHERE operacion_nav_id = 35
      AND numero_intento = 1
      AND resultado = N'ERROR_DEFINITIVO'
      AND codigo_http = 200
      AND error_normalizado = N'ERROR_DEFINITIVO'
      AND JSON_VALUE(respuesta, '$.adapter') = N'NavisionSoapPalletOutputSender'
      AND JSON_VALUE(respuesta, '$.outcome') = N'PermanentFailure'
      AND JSON_VALUE(respuesta, '$.reason') = N'ODataResponseInvalid'
      AND JSON_VALUE(respuesta, '$.baselineMaximumId') IS NULL
)
    THROW 51088, 'El intento original no coincide con el rechazo OData esperado.', 1;
GO

IF EXISTS
(
    SELECT 1
    FROM aud.eventos
    WHERE tipo_evento = N'NAV_SALIDA_REENCOLADA'
      AND entidad = N'NAV_OPERACION'
      AND entidad_id = 35
)
    THROW 51089, 'La operacion 35 ya tiene una reencolacion auditada.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @orden_id bigint =
    (
        SELECT orden_id
        FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
        WHERE operacion_nav_id = 35
          AND tipo = N'SALIDA_PALET'
          AND estado = N'ERROR_DEFINITIVO'
          AND numero_intentos = 1
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL
          AND reservado_por IS NULL
    );

    IF @orden_id IS NULL
        THROW 51090, 'La operacion cambio durante la recuperacion.', 1;

    UPDATE nav.operaciones
    SET estado = N'PENDIENTE',
        proximo_intento_utc = NULL,
        procesada_utc = NULL,
        reservado_utc = NULL,
        reservado_por = NULL
    WHERE operacion_nav_id = 35
      AND estado = N'ERROR_DEFINITIVO'
      AND numero_intentos = 1
      AND identificador_externo IS NULL;

    IF @@ROWCOUNT <> 1
        THROW 51091, 'No se reencolo exactamente una operacion.', 1;

    INSERT aud.eventos
    (
        tipo_evento,
        cuenta_dominio,
        orden_id,
        entidad,
        entidad_id,
        valor_anterior,
        valor_nuevo,
        motivo,
        correlacion_id
    )
    VALUES
    (
        N'NAV_SALIDA_REENCOLADA',
        SUSER_SNAME(),
        @orden_id,
        N'NAV_OPERACION',
        35,
        N'{"estado":"ERROR_DEFINITIVO","numero_intentos":1,"codigo_http":200,"motivo":"ODataResponseInvalid"}',
        N'{"estado":"PENDIENTE","numero_intentos":1,"siguiente_intento":2}',
        N'Reencolacion supervisada tras permitir Cod_Lote_Salida NAV vacio conservando el lote trazable MES; el intento anterior no escribio en NAV.',
        NEWID()
    );

    IF NOT EXISTS
    (
        SELECT 1
        FROM nav.operaciones
        WHERE operacion_nav_id = 35
          AND estado = N'PENDIENTE'
          AND numero_intentos = 1
          AND proximo_intento_utc IS NULL
          AND procesada_utc IS NULL
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL
          AND reservado_por IS NULL
    )
     OR (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id = 35) <> 1
     OR (SELECT COUNT(*)
         FROM aud.eventos
         WHERE tipo_evento = N'NAV_SALIDA_REENCOLADA'
           AND entidad = N'NAV_OPERACION'
           AND entidad_id = 35
           AND orden_id = @orden_id) <> 1
        THROW 51092, 'La validacion final de 033A no es correcta.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
