/*
Paquete 037A - Recuperacion del identificador externo de la operacion 37.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV ni reenvia la salida. Vincula exclusivamente la operacion 37
con la fila OData 26843 ya observada despues del intento 1, para que el Worker
entre unicamente por reconciliacion y nunca repita el envio del codeunit.
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
 OR OBJECT_ID(N'imp.etiquetas', N'U') IS NULL
 OR OBJECT_ID(N'imp.trabajos_impresion', N'U') IS NULL
 OR OBJECT_ID(N'nav.reservar_siguiente_salida_palet', N'P') IS NULL
    THROW 51107, 'El paquete 037A requiere 036A, impresion y la auditoria MES.', 1;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones n
    JOIN prod.palets p ON p.palet_id=n.palet_id AND p.orden_id=n.orden_id
    JOIN prod.ordenes o ON o.orden_id=n.orden_id
    WHERE n.operacion_nav_id=37 AND n.tipo=N'SALIDA_PALET'
      AND n.estado=N'RESULTADO_DESCONOCIDO' AND n.numero_intentos=1
      AND n.identificador_externo IS NULL
      AND n.reservado_utc IS NULL AND n.reservado_por IS NULL
      AND o.orden_id=31 AND o.numero_orden=N'FL26-00004'
      AND o.producto_codigo=N'27920LG'
      AND p.palet_id=27 AND p.numero_palet=2 AND p.cantidad_buena=20
      AND p.es_ultimo=0 AND p.autorizado_por_supervisor_id IS NULL
      AND p.estado=N'CERRADO'
)
    THROW 51108, 'La operacion 37 no cumple el estado exacto posterior al intento 1.', 1;
GO

IF (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id=37) <> 1
 OR NOT EXISTS
(
    SELECT 1 FROM nav.intentos_operacion
    WHERE operacion_nav_id=37 AND numero_intento=1
      AND resultado=N'RESULTADO_DESCONOCIDO' AND codigo_http=200
      AND error_normalizado=N'RESULTADO_DESCONOCIDO'
      AND JSON_VALUE(respuesta,'$.adapter')=N'NavisionSoapPalletOutputSender'
      AND JSON_VALUE(respuesta,'$.outcome')=N'UnknownResult'
      AND JSON_VALUE(respuesta,'$.reason')=N'CodeunitReturnedFalse'
      AND TRY_CONVERT(int,JSON_VALUE(respuesta,'$.baselineMaximumId'))=26842
)
    THROW 51109, 'El intento de la operacion 37 no coincide con la salida observada.', 1;
GO

IF (SELECT COUNT(*) FROM imp.etiquetas
    WHERE etiqueta_id=29 AND orden_id=31 AND palet_id=27
      AND tipo=N'PALET' AND estado=N'PENDIENTE_NAV') <> 1
 OR EXISTS
(
    SELECT 1 FROM imp.etiquetas
    WHERE palet_id=27 AND etiqueta_id<>29
)
 OR EXISTS
(
    SELECT 1 FROM imp.trabajos_impresion WHERE etiqueta_id=29
)
    THROW 51110, 'La etiqueta 29 o sus trabajos no cumplen el estado exacto previo.', 1;
GO

IF EXISTS
(
    SELECT 1 FROM aud.eventos
    WHERE tipo_evento=N'NAV_SALIDA_IDENTIFICADOR_RECUPERADO'
      AND entidad=N'NAV_OPERACION' AND entidad_id=37
)
    THROW 51111, 'El identificador de la operacion 37 ya fue recuperado.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @orden_id bigint =
    (
        SELECT orden_id FROM nav.operaciones WITH (UPDLOCK,HOLDLOCK)
        WHERE operacion_nav_id=37 AND tipo=N'SALIDA_PALET'
          AND estado=N'RESULTADO_DESCONOCIDO' AND numero_intentos=1
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL AND reservado_por IS NULL
    );
    IF @orden_id IS NULL
        THROW 51112, 'La operacion cambio durante la recuperacion 037A.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM prod.palets p WITH (UPDLOCK,HOLDLOCK)
        JOIN prod.ordenes o WITH (UPDLOCK,HOLDLOCK) ON o.orden_id=p.orden_id
        WHERE p.palet_id=27 AND p.orden_id=@orden_id AND p.numero_palet=2
          AND p.cantidad_buena=20 AND p.es_ultimo=0
          AND p.autorizado_por_supervisor_id IS NULL AND p.estado=N'CERRADO'
          AND o.orden_id=31 AND o.numero_orden=N'FL26-00004'
          AND o.producto_codigo=N'27920LG'
    )
     OR (SELECT COUNT(*) FROM nav.intentos_operacion WITH (UPDLOCK,HOLDLOCK)
         WHERE operacion_nav_id=37) <> 1
     OR NOT EXISTS
    (
        SELECT 1 FROM nav.intentos_operacion WITH (UPDLOCK,HOLDLOCK)
        WHERE operacion_nav_id=37 AND numero_intento=1
          AND resultado=N'RESULTADO_DESCONOCIDO' AND codigo_http=200
          AND error_normalizado=N'RESULTADO_DESCONOCIDO'
          AND JSON_VALUE(respuesta,'$.adapter')=N'NavisionSoapPalletOutputSender'
          AND JSON_VALUE(respuesta,'$.outcome')=N'UnknownResult'
          AND JSON_VALUE(respuesta,'$.reason')=N'CodeunitReturnedFalse'
          AND TRY_CONVERT(int,JSON_VALUE(respuesta,'$.baselineMaximumId'))=26842
    )
     OR (SELECT COUNT(*) FROM imp.etiquetas WITH (UPDLOCK,HOLDLOCK)
         WHERE etiqueta_id=29 AND orden_id=31 AND palet_id=27
           AND tipo=N'PALET' AND estado=N'PENDIENTE_NAV') <> 1
     OR EXISTS
    (
        SELECT 1 FROM imp.etiquetas WITH (UPDLOCK,HOLDLOCK)
        WHERE palet_id=27 AND etiqueta_id<>29
    )
     OR EXISTS
    (
        SELECT 1 FROM imp.trabajos_impresion WITH (UPDLOCK,HOLDLOCK)
        WHERE etiqueta_id=29
    )
        THROW 51113, 'El palet, intento, etiqueta o cola cambiaron durante 037A.', 1;

    UPDATE nav.operaciones
    SET identificador_externo=N'26843',
        proximo_intento_utc=SYSUTCDATETIME(),
        procesada_utc=NULL,reservado_utc=NULL,reservado_por=NULL
    WHERE operacion_nav_id=37 AND estado=N'RESULTADO_DESCONOCIDO'
      AND numero_intentos=1 AND identificador_externo IS NULL
      AND reservado_utc IS NULL AND reservado_por IS NULL;
    IF @@ROWCOUNT <> 1
        THROW 51114, 'No se recupero exactamente una operacion.', 1;

    INSERT aud.eventos
    (tipo_evento,cuenta_dominio,orden_id,entidad,entidad_id,
     valor_anterior,valor_nuevo,motivo,correlacion_id)
    VALUES
    (N'NAV_SALIDA_IDENTIFICADOR_RECUPERADO',SUSER_SNAME(),@orden_id,
     N'NAV_OPERACION',37,
     N'{"estado":"RESULTADO_DESCONOCIDO","numero_intentos":1,"identificador_externo":null}',
     N'{"estado":"RESULTADO_DESCONOCIDO","numero_intentos":1,"identificador_externo":"26843","modo":"RECONCILIACION"}',
     N'Recuperacion supervisada de la unica salida OData publicada tras la ventana del intento 1; prohibido reenviar el codeunit.',
     NEWID());

    IF NOT EXISTS
    (
        SELECT 1 FROM nav.operaciones
        WHERE operacion_nav_id=37 AND orden_id=31 AND palet_id=27
          AND estado=N'RESULTADO_DESCONOCIDO' AND numero_intentos=1
          AND identificador_externo=N'26843'
          AND proximo_intento_utc IS NOT NULL AND procesada_utc IS NULL
          AND reservado_utc IS NULL AND reservado_por IS NULL
    )
     OR (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id=37) <> 1
     OR (SELECT COUNT(*) FROM imp.etiquetas
         WHERE etiqueta_id=29 AND orden_id=31 AND palet_id=27
           AND tipo=N'PALET' AND estado=N'PENDIENTE_NAV') <> 1
     OR EXISTS (SELECT 1 FROM imp.trabajos_impresion WHERE etiqueta_id=29)
     OR (SELECT COUNT(*) FROM aud.eventos
         WHERE tipo_evento=N'NAV_SALIDA_IDENTIFICADOR_RECUPERADO'
           AND entidad=N'NAV_OPERACION' AND entidad_id=37
           AND orden_id=@orden_id) <> 1
        THROW 51115, 'La validacion final de 037A no es correcta.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
