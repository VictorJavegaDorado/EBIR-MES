/*
Paquete 036A - Recuperacion del identificador externo de la operacion 36.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV ni reenvia la salida. Vincula exclusivamente la operacion 36
con la fila OData 26842 observada despues del intento 1, para que el Worker
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
    THROW 51100, 'El paquete 036A requiere 035A y la auditoria MES.', 1;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones n
    JOIN prod.palets p ON p.palet_id=n.palet_id AND p.orden_id=n.orden_id
    JOIN prod.ordenes o ON o.orden_id=n.orden_id
    WHERE n.operacion_nav_id=36 AND n.tipo=N'SALIDA_PALET'
      AND n.estado=N'RESULTADO_DESCONOCIDO' AND n.numero_intentos=1
      AND n.identificador_externo IS NULL
      AND n.reservado_utc IS NULL AND n.reservado_por IS NULL
      AND o.orden_id=31 AND o.numero_orden=N'FL26-00004'
      AND o.producto_codigo=N'27920LG'
      AND p.palet_id=26 AND p.numero_palet=1 AND p.cantidad_buena=20
      AND p.es_ultimo=0 AND p.autorizado_por_supervisor_id IS NULL
      AND p.estado=N'CERRADO'
)
    THROW 51101, 'La operacion 36 no cumple el estado exacto posterior al intento 1.', 1;
GO

IF (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id=36) <> 1
 OR NOT EXISTS
(
    SELECT 1 FROM nav.intentos_operacion
    WHERE operacion_nav_id=36 AND numero_intento=1
      AND resultado=N'RESULTADO_DESCONOCIDO' AND codigo_http=200
      AND error_normalizado=N'RESULTADO_DESCONOCIDO'
      AND JSON_VALUE(respuesta,'$.adapter')=N'NavisionSoapPalletOutputSender'
      AND JSON_VALUE(respuesta,'$.outcome')=N'UnknownResult'
      AND JSON_VALUE(respuesta,'$.reason')=N'CodeunitReturnedFalse'
      AND TRY_CONVERT(int,JSON_VALUE(respuesta,'$.baselineMaximumId'))=0
)
    THROW 51102, 'El intento de la operacion 36 no coincide con la salida observada.', 1;
GO

IF EXISTS
(
    SELECT 1 FROM aud.eventos
    WHERE tipo_evento=N'NAV_SALIDA_IDENTIFICADOR_RECUPERADO'
      AND entidad=N'NAV_OPERACION' AND entidad_id=36
)
    THROW 51103, 'El identificador de la operacion 36 ya fue recuperado.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @orden_id bigint =
    (
        SELECT orden_id FROM nav.operaciones WITH (UPDLOCK,HOLDLOCK)
        WHERE operacion_nav_id=36 AND tipo=N'SALIDA_PALET'
          AND estado=N'RESULTADO_DESCONOCIDO' AND numero_intentos=1
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL AND reservado_por IS NULL
    );
    IF @orden_id IS NULL
        THROW 51104, 'La operacion cambio durante la recuperacion 036A.', 1;

    UPDATE nav.operaciones
    SET identificador_externo=N'26842',
        proximo_intento_utc=SYSUTCDATETIME(),
        procesada_utc=NULL,reservado_utc=NULL,reservado_por=NULL
    WHERE operacion_nav_id=36 AND estado=N'RESULTADO_DESCONOCIDO'
      AND numero_intentos=1 AND identificador_externo IS NULL
      AND reservado_utc IS NULL AND reservado_por IS NULL;
    IF @@ROWCOUNT <> 1
        THROW 51105, 'No se recupero exactamente una operacion.', 1;

    INSERT aud.eventos
    (tipo_evento,cuenta_dominio,orden_id,entidad,entidad_id,
     valor_anterior,valor_nuevo,motivo,correlacion_id)
    VALUES
    (N'NAV_SALIDA_IDENTIFICADOR_RECUPERADO',SUSER_SNAME(),@orden_id,
     N'NAV_OPERACION',36,
     N'{"estado":"RESULTADO_DESCONOCIDO","numero_intentos":1,"identificador_externo":null}',
     N'{"estado":"RESULTADO_DESCONOCIDO","numero_intentos":1,"identificador_externo":"26842","modo":"RECONCILIACION"}',
     N'Recuperacion supervisada de la unica salida OData publicada tras la ventana del intento 1; prohibido reenviar el codeunit.',
     NEWID());

    IF NOT EXISTS
    (
        SELECT 1 FROM nav.operaciones
        WHERE operacion_nav_id=36 AND estado=N'RESULTADO_DESCONOCIDO'
          AND numero_intentos=1 AND identificador_externo=N'26842'
          AND proximo_intento_utc IS NOT NULL AND procesada_utc IS NULL
          AND reservado_utc IS NULL AND reservado_por IS NULL
    )
     OR (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id=36) <> 1
     OR (SELECT COUNT(*) FROM aud.eventos
         WHERE tipo_evento=N'NAV_SALIDA_IDENTIFICADOR_RECUPERADO'
           AND entidad=N'NAV_OPERACION' AND entidad_id=36
           AND orden_id=@orden_id) <> 1
        THROW 51106, 'La validacion final de 036A no es correcta.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
