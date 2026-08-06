/*
Paquete 026C - Reencolacion supervisada tras reparar el WSDL SOAP de TEST.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV. Reencola exclusivamente la operacion 31 despues de demostrar
que el intento 2 recibio HTTP 500 porque Create no estaba publicado, que la
reconciliacion OData posterior encontro cero filas y que el WSDL actual ya
publica Create. Conserva los dos intentos y registra auditoria.
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
    THROW 51052, 'El paquete 026C requiere 026A, 026B y la auditoria MES.', 1;
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
      AND n.estado = N'RESULTADO_DESCONOCIDO'
      AND n.numero_intentos = 2
      AND n.identificador_externo IS NULL
      AND n.reservado_utc IS NULL
      AND n.reservado_por IS NULL
      AND o.numero_orden = N'FL26-00003'
      AND o.producto_codigo = N'27920LG'
      AND p.cantidad_buena = 20
      AND p.cerrado_utc IS NOT NULL
)
    THROW 51053, 'La operacion 31 no cumple el estado exacto de reconciliacion.', 1;
GO

IF (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id = 31) <> 2
 OR NOT EXISTS
(
    SELECT 1
    FROM nav.intentos_operacion
    WHERE operacion_nav_id = 31
      AND numero_intento = 1
      AND resultado = N'ERROR_DEFINITIVO'
      AND codigo_http = 405
      AND JSON_VALUE(respuesta, '$.adapter') = N'NavisionODataV4PalletOutputSender'
      AND JSON_VALUE(respuesta, '$.outcome') = N'PermanentFailure'
)
 OR NOT EXISTS
(
    SELECT 1
    FROM nav.intentos_operacion
    WHERE operacion_nav_id = 31
      AND numero_intento = 2
      AND resultado = N'RESULTADO_DESCONOCIDO'
      AND codigo_http = 500
      AND JSON_VALUE(respuesta, '$.adapter') = N'NavisionSoapPalletOutputSender'
      AND JSON_VALUE(respuesta, '$.outcome') = N'UnknownResult'
)
 OR (SELECT COUNT(*) FROM aud.eventos
     WHERE tipo_evento = N'NAV_SALIDA_REENCOLADA'
       AND entidad = N'NAV_OPERACION'
       AND entidad_id = 31) <> 1
    THROW 51054, 'Los intentos o la auditoria previos no coinciden.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @orden_id bigint =
    (
        SELECT orden_id
        FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
        WHERE operacion_nav_id = 31
          AND tipo = N'SALIDA_PALET'
          AND estado = N'RESULTADO_DESCONOCIDO'
          AND numero_intentos = 2
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL
          AND reservado_por IS NULL
    );

    IF @orden_id IS NULL
        THROW 51055, 'La operacion cambio durante la reconciliacion.', 1;

    UPDATE nav.operaciones
    SET estado = N'PENDIENTE',
        proximo_intento_utc = NULL,
        procesada_utc = NULL,
        reservado_utc = NULL,
        reservado_por = NULL
    WHERE operacion_nav_id = 31
      AND estado = N'RESULTADO_DESCONOCIDO'
      AND numero_intentos = 2
      AND identificador_externo IS NULL;

    IF @@ROWCOUNT <> 1
        THROW 51056, 'No se reencolo exactamente una operacion.', 1;

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
        N'{"estado":"RESULTADO_DESCONOCIDO","numero_intentos":2,"codigo_http":500}',
        N'{"estado":"PENDIENTE","numero_intentos":2,"siguiente_intento":3}',
        N'Reencolacion supervisada tras publicar SOAP Create y reconciliar cero filas OData.',
        NEWID()
    );

    IF NOT EXISTS
    (
        SELECT 1
        FROM nav.operaciones
        WHERE operacion_nav_id = 31
          AND estado = N'PENDIENTE'
          AND numero_intentos = 2
          AND proximo_intento_utc IS NULL
          AND procesada_utc IS NULL
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL
          AND reservado_por IS NULL
    )
     OR (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id = 31) <> 2
     OR (SELECT COUNT(*) FROM aud.eventos
         WHERE tipo_evento = N'NAV_SALIDA_REENCOLADA'
           AND entidad = N'NAV_OPERACION'
           AND entidad_id = 31) <> 2
        THROW 51057, 'La validacion final de 026C no es correcta.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
