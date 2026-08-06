/*
Paquete 030A - Recuperacion del identificador externo de la operacion 32.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV ni reenvia la salida. Vincula exclusivamente la operacion 32
con la fila OData 26838 observada despues del intento 2, para que el Worker
entre unicamente por reconciliacion y nunca repita RegistrarSalidaFabricacion.
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
    THROW 51064, 'El paquete 030A requiere 028A, 029A y la auditoria MES.', 1;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones n
    JOIN prod.palets p
      ON p.palet_id = n.palet_id
     AND p.orden_id = n.orden_id
    JOIN prod.ordenes o ON o.orden_id = n.orden_id
    WHERE n.operacion_nav_id = 32
      AND n.tipo = N'SALIDA_PALET'
      AND n.estado = N'ERROR_DEFINITIVO'
      AND n.numero_intentos = 2
      AND n.identificador_externo IS NULL
      AND n.reservado_utc IS NULL
      AND n.reservado_por IS NULL
      AND o.numero_orden = N'FL26-00003'
      AND o.producto_codigo = N'27920LG'
      AND p.palet_id = 22
      AND p.numero_palet = 2
      AND p.cantidad_buena = 20
      AND p.es_ultimo = 0
      AND p.estado = N'CERRADO'
)
    THROW 51065, 'La operacion 32 no cumple el estado exacto posterior al intento 2.', 1;
GO

IF (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id = 32) <> 2
 OR NOT EXISTS
(
    SELECT 1
    FROM nav.intentos_operacion
    WHERE operacion_nav_id = 32
      AND numero_intento = 2
      AND resultado = N'ERROR_DEFINITIVO'
      AND codigo_http = 200
      AND error_normalizado = N'ERROR_DEFINITIVO'
      AND JSON_VALUE(respuesta, '$.adapter') = N'NavisionSoapPalletOutputSender'
      AND JSON_VALUE(respuesta, '$.outcome') = N'PermanentFailure'
      AND JSON_VALUE(respuesta, '$.reason') = N'CodeunitReturnedFalse'
      AND TRY_CONVERT(int, JSON_VALUE(respuesta, '$.baselineMaximumId')) = 26837
)
    THROW 51066, 'El intento 2 no coincide con la respuesta false observada.', 1;
GO

IF (SELECT COUNT(*)
    FROM aud.eventos
    WHERE tipo_evento = N'NAV_SALIDA_REENCOLADA'
      AND entidad = N'NAV_OPERACION'
      AND entidad_id = 32) <> 1
    THROW 51067, 'No existe una unica reencolacion 029A para la operacion 32.', 1;
GO

IF EXISTS
(
    SELECT 1
    FROM aud.eventos
    WHERE tipo_evento = N'NAV_SALIDA_IDENTIFICADOR_RECUPERADO'
      AND entidad = N'NAV_OPERACION'
      AND entidad_id = 32
)
    THROW 51068, 'El identificador de la operacion 32 ya fue recuperado.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @orden_id bigint =
    (
        SELECT orden_id
        FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
        WHERE operacion_nav_id = 32
          AND tipo = N'SALIDA_PALET'
          AND estado = N'ERROR_DEFINITIVO'
          AND numero_intentos = 2
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL
          AND reservado_por IS NULL
    );

    IF @orden_id IS NULL
        THROW 51069, 'La operacion cambio durante la recuperacion 030A.', 1;

    UPDATE nav.operaciones
    SET estado = N'RESULTADO_DESCONOCIDO',
        identificador_externo = N'26838',
        proximo_intento_utc = SYSUTCDATETIME(),
        procesada_utc = NULL,
        reservado_utc = NULL,
        reservado_por = NULL
    WHERE operacion_nav_id = 32
      AND estado = N'ERROR_DEFINITIVO'
      AND numero_intentos = 2
      AND identificador_externo IS NULL
      AND reservado_utc IS NULL
      AND reservado_por IS NULL;

    IF @@ROWCOUNT <> 1
        THROW 51070, 'No se recupero exactamente una operacion.', 1;

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
        N'NAV_SALIDA_IDENTIFICADOR_RECUPERADO',
        SUSER_SNAME(),
        @orden_id,
        N'NAV_OPERACION',
        32,
        N'{"estado":"ERROR_DEFINITIVO","numero_intentos":2,"codigo_http":200,"identificador_externo":null}',
        N'{"estado":"RESULTADO_DESCONOCIDO","numero_intentos":2,"identificador_externo":"26838","modo":"RECONCILIACION"}',
        N'Recuperacion supervisada de la unica salida OData creada por el intento 2; prohibido reenviar el codeunit.',
        NEWID()
    );

    IF NOT EXISTS
    (
        SELECT 1
        FROM nav.operaciones
        WHERE operacion_nav_id = 32
          AND estado = N'RESULTADO_DESCONOCIDO'
          AND numero_intentos = 2
          AND identificador_externo = N'26838'
          AND proximo_intento_utc IS NOT NULL
          AND procesada_utc IS NULL
          AND reservado_utc IS NULL
          AND reservado_por IS NULL
    )
     OR (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id = 32) <> 2
     OR (SELECT COUNT(*)
         FROM aud.eventos
         WHERE tipo_evento = N'NAV_SALIDA_IDENTIFICADOR_RECUPERADO'
           AND entidad = N'NAV_OPERACION'
           AND entidad_id = 32
           AND orden_id = @orden_id) <> 1
        THROW 51071, 'La validacion final de 030A no es correcta.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
