/*
Paquete 029A - Reencolacion supervisada de la operacion 32.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV. Reencola exclusivamente la operacion 32 despues de demostrar
que el intento 1 recibio HTTP 500 sin crear una salida ni obtener identificador
externo porque RegistrarSalidaFabricacion encontro el bulto NAV cerrado. El
adaptador corregido comprueba, abre y cierra el bulto mediante el contrato NAV.
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
    THROW 51057, 'El paquete 029A requiere 028A y la auditoria MES.', 1;
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
      AND n.estado = N'RESULTADO_DESCONOCIDO'
      AND n.numero_intentos = 1
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
    THROW 51058, 'La operacion 32 no cumple el estado exacto de recuperacion.', 1;
GO

IF (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id = 32) <> 1
 OR NOT EXISTS
(
    SELECT 1
    FROM nav.intentos_operacion
    WHERE operacion_nav_id = 32
      AND numero_intento = 1
      AND resultado = N'RESULTADO_DESCONOCIDO'
      AND codigo_http = 500
      AND error_normalizado = N'RESULTADO_DESCONOCIDO'
      AND JSON_VALUE(respuesta, '$.adapter') = N'NavisionSoapPalletOutputSender'
      AND JSON_VALUE(respuesta, '$.outcome') = N'UnknownResult'
      AND JSON_VALUE(respuesta, '$.reason') = N'SoapHttpUncertain'
      AND TRY_CONVERT(int, JSON_VALUE(respuesta, '$.baselineMaximumId')) = 26837
)
    THROW 51059, 'El intento original no coincide con la evidencia HTTP 500 esperada.', 1;
GO

IF EXISTS
(
    SELECT 1
    FROM aud.eventos
    WHERE tipo_evento = N'NAV_SALIDA_REENCOLADA'
      AND entidad = N'NAV_OPERACION'
      AND entidad_id = 32
)
    THROW 51060, 'La operacion 32 ya tiene una reencolacion auditada.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @orden_id bigint =
    (
        SELECT orden_id
        FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
        WHERE operacion_nav_id = 32
          AND tipo = N'SALIDA_PALET'
          AND estado = N'RESULTADO_DESCONOCIDO'
          AND numero_intentos = 1
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL
          AND reservado_por IS NULL
    );

    IF @orden_id IS NULL
        THROW 51061, 'La operacion cambio durante la recuperacion.', 1;

    UPDATE nav.operaciones
    SET estado = N'PENDIENTE',
        proximo_intento_utc = NULL,
        procesada_utc = NULL,
        reservado_utc = NULL,
        reservado_por = NULL
    WHERE operacion_nav_id = 32
      AND estado = N'RESULTADO_DESCONOCIDO'
      AND numero_intentos = 1
      AND identificador_externo IS NULL;

    IF @@ROWCOUNT <> 1
        THROW 51062, 'No se reencolo exactamente una operacion.', 1;

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
        32,
        N'{"estado":"RESULTADO_DESCONOCIDO","numero_intentos":1,"codigo_http":500,"bulto_nav":"CERRADO"}',
        N'{"estado":"PENDIENTE","numero_intentos":1,"siguiente_intento":2}',
        N'Reencolacion supervisada tras incorporar el ciclo comprobado de apertura y cierre de bulto NAV.',
        NEWID()
    );

    IF NOT EXISTS
    (
        SELECT 1
        FROM nav.operaciones
        WHERE operacion_nav_id = 32
          AND estado = N'PENDIENTE'
          AND numero_intentos = 1
          AND proximo_intento_utc IS NULL
          AND procesada_utc IS NULL
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL
          AND reservado_por IS NULL
    )
     OR (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id = 32) <> 1
     OR (SELECT COUNT(*)
         FROM aud.eventos
         WHERE tipo_evento = N'NAV_SALIDA_REENCOLADA'
           AND entidad = N'NAV_OPERACION'
           AND entidad_id = 32
           AND orden_id = @orden_id) <> 1
        THROW 51063, 'La validacion final de 029A no es correcta.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
