/*
Paquete 043A - Confirmacion supervisada de la reconciliacion tardia de la
salida de palet 49, ya observada en NAV como Registrado.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV ni reenvia la salida. Confirma exclusivamente en MES la
operacion 49 vinculada a la fila NAV 26853 y habilita su unica etiqueta.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'nav.operaciones', N'U') IS NULL
 OR OBJECT_ID(N'nav.intentos_operacion', N'U') IS NULL
 OR OBJECT_ID(N'nav.confirmar_salida_palet', N'P') IS NULL
 OR OBJECT_ID(N'aud.registrar_evento', N'P') IS NULL
 OR OBJECT_ID(N'prod.palets', N'U') IS NULL
 OR OBJECT_ID(N'prod.ordenes', N'U') IS NULL
 OR OBJECT_ID(N'prod.sesiones_linea', N'U') IS NULL
 OR OBJECT_ID(N'imp.etiquetas', N'U') IS NULL
 OR OBJECT_ID(N'imp.trabajos_impresion', N'U') IS NULL
    THROW 51130, 'El paquete 043A requiere la cola, impresion y auditoria MES.', 1;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones n
    JOIN prod.palets p ON p.palet_id=n.palet_id AND p.orden_id=n.orden_id
    JOIN prod.ordenes o ON o.orden_id=n.orden_id
    WHERE n.operacion_nav_id=49 AND n.tipo=N'SALIDA_PALET'
      AND n.estado=N'RESULTADO_DESCONOCIDO' AND n.numero_intentos=12
      AND n.identificador_externo=N'26853'
      AND n.proximo_intento_utc IS NULL AND n.procesada_utc IS NOT NULL
      AND n.reservado_utc IS NULL AND n.reservado_por IS NULL
      AND o.orden_id=35 AND o.numero_orden=N'FL26-00007'
      AND o.producto_codigo=N'27920LG' AND o.estado=N'PENDIENTE_CIERRE'
      AND o.cantidad_objetivo=20 AND o.cantidad_buena_acumulada=20
      AND o.cantidad_reservada_activa=0
      AND p.palet_id=38 AND p.numero_palet=1 AND p.cantidad_buena=20
      AND p.es_ultimo=1 AND p.autorizado_por_supervisor_id=48
      AND p.estado=N'CERRADO'
)
    THROW 51131, 'La operacion 49 no cumple el estado exacto observado.', 1;
GO

IF (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id=49) <> 12
 OR NOT EXISTS
(
    SELECT 1 FROM nav.intentos_operacion
    WHERE operacion_nav_id=49 AND numero_intento=12
      AND resultado=N'RESULTADO_DESCONOCIDO'
      AND error_normalizado=N'RESULTADO_DESCONOCIDO'
      AND JSON_VALUE(respuesta,'$.reason')=N'OutputStateNotRegistered'
)
    THROW 51132, 'Los intentos agotados de la operacion 49 han cambiado.', 1;
GO

IF (SELECT COUNT(*) FROM imp.etiquetas
    WHERE etiqueta_id=40 AND orden_id=35 AND palet_id=38
      AND tipo=N'PALET' AND estado=N'PENDIENTE_NAV') <> 1
 OR EXISTS
(
    SELECT 1 FROM imp.etiquetas
    WHERE palet_id=38 AND etiqueta_id<>40
)
 OR EXISTS
(
    SELECT 1 FROM imp.trabajos_impresion WHERE etiqueta_id=40
)
    THROW 51133, 'La etiqueta 40 o sus trabajos no cumplen el estado previo.', 1;
GO

IF
(
    SELECT COUNT(*)
    FROM prod.palets p
    JOIN prod.sesiones_linea s ON s.sesion_linea_id=p.sesion_linea_id
    JOIN cfg.lineas_impresoras li ON li.linea_id=s.linea_id
    JOIN cfg.impresoras i ON i.impresora_id=li.impresora_id
    WHERE p.palet_id=38 AND p.orden_id=35
      AND li.asignado_hasta_utc IS NULL AND li.es_principal=1 AND i.activa=1
) <> 1
    THROW 51134, 'La linea no tiene exactamente una impresora principal activa.', 1;
GO

IF EXISTS
(
    SELECT 1 FROM aud.eventos
    WHERE tipo_evento=N'NAV_SALIDA_RECONCILIACION_SUPERVISADA'
      AND entidad=N'nav.operaciones' AND entidad_id=49
)
    THROW 51135, 'La reconciliacion supervisada de la operacion 49 ya existe.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @correlacion_id uniqueidentifier=NEWID(),
            @sesion_linea_id bigint,
            @linea_id bigint;

    SELECT @sesion_linea_id=p.sesion_linea_id, @linea_id=s.linea_id
    FROM nav.operaciones n WITH (UPDLOCK,HOLDLOCK)
    JOIN prod.palets p WITH (UPDLOCK,HOLDLOCK)
      ON p.palet_id=n.palet_id AND p.orden_id=n.orden_id
    JOIN prod.sesiones_linea s WITH (UPDLOCK,HOLDLOCK)
      ON s.sesion_linea_id=p.sesion_linea_id AND s.orden_id=p.orden_id
    JOIN prod.ordenes o WITH (UPDLOCK,HOLDLOCK) ON o.orden_id=n.orden_id
    WHERE n.operacion_nav_id=49 AND n.tipo=N'SALIDA_PALET'
      AND n.estado=N'RESULTADO_DESCONOCIDO' AND n.numero_intentos=12
      AND n.identificador_externo=N'26853'
      AND n.proximo_intento_utc IS NULL AND n.procesada_utc IS NOT NULL
      AND n.reservado_utc IS NULL AND n.reservado_por IS NULL
      AND o.orden_id=35 AND o.numero_orden=N'FL26-00007'
      AND o.producto_codigo=N'27920LG' AND o.estado=N'PENDIENTE_CIERRE'
      AND o.cantidad_objetivo=20 AND o.cantidad_buena_acumulada=20
      AND o.cantidad_reservada_activa=0
      AND p.palet_id=38 AND p.numero_palet=1 AND p.cantidad_buena=20
      AND p.es_ultimo=1 AND p.autorizado_por_supervisor_id=48
      AND p.estado=N'CERRADO';

    IF @sesion_linea_id IS NULL
     OR (SELECT COUNT(*) FROM nav.intentos_operacion WITH (UPDLOCK,HOLDLOCK)
         WHERE operacion_nav_id=49) <> 12
     OR NOT EXISTS
    (
        SELECT 1 FROM nav.intentos_operacion WITH (UPDLOCK,HOLDLOCK)
        WHERE operacion_nav_id=49 AND numero_intento=12
          AND resultado=N'RESULTADO_DESCONOCIDO'
          AND error_normalizado=N'RESULTADO_DESCONOCIDO'
          AND JSON_VALUE(respuesta,'$.reason')=N'OutputStateNotRegistered'
    )
     OR (SELECT COUNT(*) FROM imp.etiquetas WITH (UPDLOCK,HOLDLOCK)
         WHERE etiqueta_id=40 AND orden_id=35 AND palet_id=38
           AND tipo=N'PALET' AND estado=N'PENDIENTE_NAV') <> 1
     OR EXISTS
    (
        SELECT 1 FROM imp.etiquetas WITH (UPDLOCK,HOLDLOCK)
        WHERE palet_id=38 AND etiqueta_id<>40
    )
     OR EXISTS
    (
        SELECT 1 FROM imp.trabajos_impresion WITH (UPDLOCK,HOLDLOCK)
        WHERE etiqueta_id=40
    )
        THROW 51136, 'El estado protegido cambio durante la recuperacion 043A.', 1;

    EXEC nav.confirmar_salida_palet
        @operacion_nav_id=49,
        @respuesta=N'{"adapter":"NavisionSoapPalletOutputSender","outcome":"Confirmed","reconciliationMode":"SUPERVISED_EXISTING_OUTPUT","observedNavState":"Registrado","externalIdentifier":"26853"}',
        @identificador_externo=N'26853',
        @correlacion_id=@correlacion_id;

    EXEC aud.registrar_evento
        @tipo_evento=N'NAV_SALIDA_RECONCILIACION_SUPERVISADA',
        @cuenta_dominio=N'EBIR\MES$',
        @rol_usado=N'SISTEMA',
        @linea_id=@linea_id,
        @orden_id=35,
        @sesion_linea_id=@sesion_linea_id,
        @entidad=N'nav.operaciones',
        @entidad_id=49,
        @valor_anterior=N'{"estado":"RESULTADO_DESCONOCIDO","numero_intentos":12,"identificador_externo":"26853","etiqueta":"PENDIENTE_NAV"}',
        @valor_nuevo=N'{"estado":"CONFIRMADA","numero_intentos":13,"identificador_externo":"26853","etiqueta":"LISTA","modo":"RECONCILIACION_SUPERVISADA"}',
        @motivo=N'NAV EbirTest observado con una unica salida 26853 ya Registrada; no se reenvia el codeunit.',
        @correlacion_id=@correlacion_id;

    IF NOT EXISTS
    (
        SELECT 1 FROM nav.operaciones
        WHERE operacion_nav_id=49 AND orden_id=35 AND palet_id=38
          AND tipo=N'SALIDA_PALET' AND estado=N'CONFIRMADA'
          AND numero_intentos=13 AND identificador_externo=N'26853'
          AND proximo_intento_utc IS NULL AND procesada_utc IS NOT NULL
          AND reservado_utc IS NULL AND reservado_por IS NULL
    )
     OR (SELECT COUNT(*) FROM nav.intentos_operacion
         WHERE operacion_nav_id=49) <> 12
     OR (SELECT COUNT(*) FROM imp.etiquetas
         WHERE etiqueta_id=40 AND orden_id=35 AND palet_id=38
           AND tipo=N'PALET' AND estado=N'LISTA') <> 1
     OR (SELECT COUNT(*) FROM imp.trabajos_impresion
         WHERE etiqueta_id=40 AND es_reimpresion=0 AND estado=N'PENDIENTE') <> 1
     OR (SELECT COUNT(*) FROM aud.eventos
         WHERE tipo_evento=N'NAV_SALIDA_RECONCILIACION_SUPERVISADA'
           AND entidad=N'nav.operaciones' AND entidad_id=49
           AND orden_id=35 AND correlacion_id=@correlacion_id) <> 1
        THROW 51137, 'La validacion final de 043A no es correcta.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
