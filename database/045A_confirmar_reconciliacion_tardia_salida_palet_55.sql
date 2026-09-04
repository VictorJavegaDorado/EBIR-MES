/*
Paquete 045A - Confirmacion supervisada de la salida de palet 55, cuya fila
NAV 26859 fue observada como Registrado. Base exclusiva: EBIR_MES_TEST.
No contacta NAV ni reenvia la salida; habilita una unica etiqueta original.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'nav.operaciones',N'U') IS NULL
 OR OBJECT_ID(N'nav.intentos_operacion',N'U') IS NULL
 OR OBJECT_ID(N'nav.confirmar_salida_palet',N'P') IS NULL
 OR OBJECT_ID(N'prod.ordenes',N'U') IS NULL
 OR OBJECT_ID(N'prod.palets',N'U') IS NULL
 OR OBJECT_ID(N'imp.etiquetas',N'U') IS NULL
 OR OBJECT_ID(N'imp.trabajos_impresion',N'U') IS NULL
    THROW 51170, 'El paquete 045A requiere la cola e impresion MES.', 1;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones n
    JOIN prod.palets p ON p.palet_id=n.palet_id AND p.orden_id=n.orden_id
    JOIN prod.ordenes o ON o.orden_id=n.orden_id
    WHERE n.operacion_nav_id=55 AND n.tipo=N'SALIDA_PALET'
      AND n.estado=N'RESULTADO_DESCONOCIDO' AND n.numero_intentos=12
      AND n.identificador_externo=N'26859'
      AND n.proximo_intento_utc IS NULL AND n.procesada_utc IS NOT NULL
      AND n.reservado_utc IS NULL AND n.reservado_por IS NULL
      AND o.orden_id=38 AND o.numero_orden=N'FL26-00009'
      AND o.producto_codigo=N'27920LG' AND o.estado=N'ABIERTA'
      AND o.cantidad_objetivo=80 AND o.cantidad_buena_acumulada=20
      AND o.cantidad_reservada_activa=20
      AND p.palet_id=44 AND p.numero_palet=1 AND p.cantidad_buena=20
      AND p.es_ultimo=0 AND p.autorizado_por_supervisor_id IS NULL
      AND p.estado=N'CERRADO'
)
    THROW 51171, 'La operacion 55 no cumple el estado exacto observado.', 1;
GO

IF (SELECT COUNT(*) FROM nav.intentos_operacion WHERE operacion_nav_id=55) <> 12
 OR NOT EXISTS
(
    SELECT 1 FROM nav.intentos_operacion
    WHERE operacion_nav_id=55 AND numero_intento=12
      AND resultado=N'RESULTADO_DESCONOCIDO'
      AND error_normalizado=N'RESULTADO_DESCONOCIDO'
      AND JSON_VALUE(respuesta,'$.reason')=N'OutputStateNotRegistered'
)
 OR (SELECT COUNT(*) FROM imp.etiquetas
     WHERE etiqueta_id=46 AND orden_id=38 AND palet_id=44
       AND tipo=N'PALET' AND estado=N'PENDIENTE_NAV') <> 1
 OR EXISTS
(
    SELECT 1 FROM imp.etiquetas
    WHERE palet_id=44 AND etiqueta_id<>46
)
 OR EXISTS
(
    SELECT 1 FROM imp.trabajos_impresion WHERE etiqueta_id=46
)
    THROW 51172, 'Intentos, etiqueta o impresion de la operacion 55 cambiaron.', 1;
GO

IF
(
    SELECT COUNT(*)
    FROM prod.palets p
    JOIN prod.sesiones_linea s ON s.sesion_linea_id=p.sesion_linea_id
    JOIN cfg.lineas_impresoras li ON li.linea_id=s.linea_id
    JOIN cfg.impresoras i ON i.impresora_id=li.impresora_id
    WHERE p.palet_id=44 AND p.orden_id=38
      AND li.asignado_hasta_utc IS NULL AND li.es_principal=1 AND i.activa=1
) <> 1
    THROW 51173, 'La linea no tiene exactamente una impresora principal activa.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @correlacion_id uniqueidentifier=NEWID(),
            @sesion_linea_id bigint;

    SELECT @sesion_linea_id=p.sesion_linea_id
    FROM nav.operaciones n WITH (UPDLOCK,HOLDLOCK)
    JOIN prod.palets p WITH (UPDLOCK,HOLDLOCK)
      ON p.palet_id=n.palet_id AND p.orden_id=n.orden_id
    JOIN prod.ordenes o WITH (UPDLOCK,HOLDLOCK) ON o.orden_id=n.orden_id
    WHERE n.operacion_nav_id=55 AND n.tipo=N'SALIDA_PALET'
      AND n.estado=N'RESULTADO_DESCONOCIDO' AND n.numero_intentos=12
      AND n.identificador_externo=N'26859'
      AND n.proximo_intento_utc IS NULL AND n.procesada_utc IS NOT NULL
      AND n.reservado_utc IS NULL AND n.reservado_por IS NULL
      AND o.orden_id=38 AND o.numero_orden=N'FL26-00009'
      AND o.producto_codigo=N'27920LG' AND o.estado=N'ABIERTA'
      AND o.cantidad_objetivo=80 AND o.cantidad_buena_acumulada=20
      AND o.cantidad_reservada_activa=20
      AND p.palet_id=44 AND p.numero_palet=1 AND p.cantidad_buena=20
      AND p.es_ultimo=0 AND p.autorizado_por_supervisor_id IS NULL
      AND p.estado=N'CERRADO';

    IF @sesion_linea_id IS NULL
     OR (SELECT COUNT(*) FROM nav.intentos_operacion WITH (UPDLOCK,HOLDLOCK)
         WHERE operacion_nav_id=55) <> 12
     OR NOT EXISTS
    (
        SELECT 1 FROM nav.intentos_operacion WITH (UPDLOCK,HOLDLOCK)
        WHERE operacion_nav_id=55 AND numero_intento=12
          AND resultado=N'RESULTADO_DESCONOCIDO'
          AND error_normalizado=N'RESULTADO_DESCONOCIDO'
          AND JSON_VALUE(respuesta,'$.reason')=N'OutputStateNotRegistered'
    )
     OR (SELECT COUNT(*) FROM imp.etiquetas WITH (UPDLOCK,HOLDLOCK)
         WHERE etiqueta_id=46 AND orden_id=38 AND palet_id=44
           AND tipo=N'PALET' AND estado=N'PENDIENTE_NAV') <> 1
     OR EXISTS
    (
        SELECT 1 FROM imp.etiquetas WITH (UPDLOCK,HOLDLOCK)
        WHERE palet_id=44 AND etiqueta_id<>46
    )
     OR EXISTS
    (
        SELECT 1 FROM imp.trabajos_impresion WITH (UPDLOCK,HOLDLOCK)
        WHERE etiqueta_id=46
    )
        THROW 51174, 'El estado protegido cambio durante 045A.', 1;

    EXEC nav.confirmar_salida_palet
        @operacion_nav_id=55,
        @respuesta=N'{"adapter":"NavisionSoapPalletOutputSender","outcome":"Confirmed","reconciliationMode":"SUPERVISED_EXISTING_OUTPUT","observedNavState":"Registrado","externalIdentifier":"26859"}',
        @identificador_externo=N'26859',
        @correlacion_id=@correlacion_id;

    IF NOT EXISTS
    (
        SELECT 1 FROM nav.operaciones
        WHERE operacion_nav_id=55 AND orden_id=38 AND palet_id=44
          AND tipo=N'SALIDA_PALET' AND estado=N'CONFIRMADA'
          AND numero_intentos=13 AND identificador_externo=N'26859'
          AND proximo_intento_utc IS NULL AND procesada_utc IS NOT NULL
          AND reservado_utc IS NULL AND reservado_por IS NULL
    )
     OR (SELECT COUNT(*) FROM nav.intentos_operacion
         WHERE operacion_nav_id=55) <> 12
     OR (SELECT COUNT(*) FROM imp.etiquetas
         WHERE etiqueta_id=46 AND orden_id=38 AND palet_id=44
           AND tipo=N'PALET' AND estado=N'LISTA') <> 1
     OR (SELECT COUNT(*) FROM imp.trabajos_impresion
         WHERE etiqueta_id=46 AND es_reimpresion=0 AND estado=N'PENDIENTE') <> 1
        THROW 51175, 'La validacion final de 045A no es correcta.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
