/*
Paquete 026B - Reencolacion supervisada del primer ensayo de salida NAV.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV. Reencola exclusivamente la operacion 31 despues de demostrar
que el intento 1 fue rechazado con HTTP 405, sin identificador externo y sin
reserva activa. Conserva el intento fallido y registra auditoria.
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
    THROW 51046, 'El paquete 026B requiere 026A y la auditoria MES.', 1;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones n
    JOIN prod.palets p
      ON p.palet_id = n.palet_id
     AND p.orden_id = n.orden_id
    JOIN prod.ordenes o ON o.orden_id = n.orden_id
    WHERE n.operacion_nav_id = 31
      AND n.tipo = N'SALIDA_PALET'
      AND n.estado = N'ERROR_DEFINITIVO'
      AND n.numero_intentos = 1
      AND n.identificador_externo IS NULL
      AND n.reservado_utc IS NULL
      AND n.reservado_por IS NULL
      AND o.numero_orden = N'FL26-00003'
      AND o.producto_codigo = N'27920LG'
      AND p.cantidad_buena = 20
      AND p.cerrado_utc IS NOT NULL
)
    THROW 51047, 'La operacion 31 no cumple el estado exacto de reconciliacion.', 1;
GO

IF (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id = 31) <> 1
 OR NOT EXISTS
(
    SELECT 1
    FROM nav.intentos_operacion
    WHERE operacion_nav_id = 31
      AND numero_intento = 1
      AND resultado = N'ERROR_DEFINITIVO'
      AND codigo_http = 405
      AND JSON_VALUE(respuesta, '$.outcome') = N'PermanentFailure'
      AND JSON_VALUE(respuesta, '$.adapter') = N'NavisionODataV4PalletOutputSender'
)
    THROW 51048, 'El intento 405 original no coincide con la evidencia esperada.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @orden_id bigint =
    (
        SELECT orden_id
        FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
        WHERE operacion_nav_id = 31
          AND tipo = N'SALIDA_PALET'
          AND estado = N'ERROR_DEFINITIVO'
          AND numero_intentos = 1
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL
          AND reservado_por IS NULL
    );

    IF @orden_id IS NULL
        THROW 51049, 'La operacion cambio durante la reconciliacion.', 1;

    UPDATE nav.operaciones
    SET estado = N'PENDIENTE',
        proximo_intento_utc = NULL,
        procesada_utc = NULL,
        reservado_utc = NULL,
        reservado_por = NULL
    WHERE operacion_nav_id = 31
      AND estado = N'ERROR_DEFINITIVO'
      AND numero_intentos = 1
      AND identificador_externo IS NULL;

    IF @@ROWCOUNT <> 1
        THROW 51050, 'No se reencolo exactamente una operacion.', 1;

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
        31,
        N'{"estado":"ERROR_DEFINITIVO","numero_intentos":1,"codigo_http":405}',
        N'{"estado":"PENDIENTE","numero_intentos":1,"siguiente_intento":2}',
        N'Reencolacion supervisada tras rechazo ODataV4 405; envio corregido a SOAP Create.',
        NEWID()
    );

    IF NOT EXISTS
    (
        SELECT 1
        FROM nav.operaciones
        WHERE operacion_nav_id = 31
          AND estado = N'PENDIENTE'
          AND numero_intentos = 1
          AND proximo_intento_utc IS NULL
          AND procesada_utc IS NULL
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL
          AND reservado_por IS NULL
    )
     OR (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id = 31) <> 1
     OR NOT EXISTS
    (
        SELECT 1
        FROM aud.eventos
        WHERE tipo_evento = N'NAV_SALIDA_REENCOLADA'
          AND entidad = N'NAV_OPERACION'
          AND entidad_id = 31
          AND orden_id = @orden_id
    )
        THROW 51051, 'La validacion final de 026B no es correcta.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
