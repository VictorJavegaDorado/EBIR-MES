/*
Paquete 040A - Retirada exacta de la intencion CIERRE_FL 42 obsoleta.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV ni imprime. Anula exclusivamente la operacion 42, que no tiene
adaptador ni contrato externo implementado, y devuelve la orden 31 al contrato
local PENDIENTE_CIERRE. La operacion heredada 39 es una precondicion inmutable.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'nav.operaciones', N'U') IS NULL
 OR OBJECT_ID(N'nav.intentos_operacion', N'U') IS NULL
 OR OBJECT_ID(N'prod.ordenes', N'U') IS NULL
 OR OBJECT_ID(N'prod.sesiones_linea', N'U') IS NULL
 OR OBJECT_ID(N'prod.estados_linea', N'U') IS NULL
 OR OBJECT_ID(N'prod.fichajes', N'U') IS NULL
 OR OBJECT_ID(N'prod.paros_operario', N'U') IS NULL
 OR OBJECT_ID(N'prod.tramos_capacidad', N'U') IS NULL
 OR OBJECT_ID(N'prod.reservas_palet', N'U') IS NULL
 OR OBJECT_ID(N'prod.palets', N'U') IS NULL
 OR OBJECT_ID(N'imp.etiquetas', N'U') IS NULL
 OR OBJECT_ID(N'imp.trabajos_impresion', N'U') IS NULL
 OR OBJECT_ID(N'aud.registrar_evento', N'P') IS NULL
    THROW 51130, 'El paquete 040A requiere 039A, produccion, NAV, impresion y auditoria.', 1;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones
    WHERE operacion_nav_id=42
      AND clave_idempotencia=N'MES:CIERRE_FL:31'
      AND tipo=N'CIERRE_FL' AND orden_id=31 AND palet_id IS NULL
      AND scrap_id IS NULL AND revision_scrap_id IS NULL
      AND estado=N'PENDIENTE' AND numero_intentos=0
      AND identificador_externo IS NULL AND respuesta IS NULL
      AND reservado_utc IS NULL AND reservado_por IS NULL
      AND TRY_CONVERT(bigint,JSON_VALUE(payload,'$.orden_id'))=31
      AND JSON_VALUE(payload,'$.numero_orden')=N'FL26-00004'
      AND NULLIF(JSON_VALUE(payload,'$.ultimo_palet_uid'),N'') IS NOT NULL
)
 OR EXISTS (SELECT 1 FROM nav.intentos_operacion WHERE operacion_nav_id=42)
    THROW 51131, 'La operacion CIERRE_FL 42 no cumple el estado exacto sin ejecutar.', 1;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones
    WHERE operacion_nav_id=39
      AND clave_idempotencia=N'MES:CIERRE_FL:30'
      AND tipo=N'CIERRE_FL' AND orden_id=30
      AND estado=N'PENDIENTE' AND numero_intentos=0
      AND identificador_externo IS NULL
      AND reservado_utc IS NULL AND reservado_por IS NULL
)
 OR EXISTS (SELECT 1 FROM nav.intentos_operacion WHERE operacion_nav_id=39)
    THROW 51132, 'La operacion heredada 39 no conserva su estado inmutable esperado.', 1;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM prod.ordenes o
    JOIN prod.sesiones_linea s ON s.orden_id=o.orden_id
    JOIN prod.estados_linea el ON el.linea_id=s.linea_id
    WHERE o.orden_id=31 AND o.numero_orden=N'FL26-00004'
      AND o.producto_codigo=N'27920LG' AND o.estado=N'PENDIENTE_NAV'
      AND o.cantidad_objetivo=100 AND o.cantidad_buena_acumulada=100
      AND o.cantidad_reservada_activa=0
      AND s.sesion_linea_id=35 AND s.estado=N'SIN_OPERARIOS'
      AND s.finalizada_utc IS NULL
      AND el.sesion_linea_id=35 AND el.estado=N'PENDIENTE_NAV'
      AND el.motivo_bloqueo=N'CIERRE_FL_PENDIENTE'
)
    THROW 51133, 'La orden, sesion o linea no cumplen el estado previo exacto.', 1;
GO

IF EXISTS
(
    SELECT 1 FROM prod.fichajes
    WHERE sesion_linea_id=35 AND salida_utc IS NULL
)
 OR EXISTS
(
    SELECT 1
    FROM prod.paros_operario po
    JOIN prod.fichajes f ON f.fichaje_id=po.fichaje_id
    WHERE f.sesion_linea_id=35 AND po.fin_utc IS NULL
)
 OR EXISTS
(
    SELECT 1 FROM prod.tramos_capacidad
    WHERE sesion_linea_id=35 AND fin_utc IS NULL
)
 OR EXISTS
(
    SELECT 1 FROM prod.reservas_palet
    WHERE sesion_linea_id=35 AND estado=N'ACTIVA'
)
    THROW 51134, 'La sesion 35 conserva recursos o reservas abiertos.', 1;
GO

IF (SELECT COUNT(*) FROM prod.palets
    WHERE orden_id=31 AND sesion_linea_id=35 AND estado=N'CERRADO') <> 5
 OR (SELECT SUM(cantidad_buena) FROM prod.palets
     WHERE orden_id=31 AND sesion_linea_id=35 AND estado=N'CERRADO') <> 100
 OR (SELECT COUNT(*) FROM prod.palets
     WHERE orden_id=31 AND sesion_linea_id=35 AND estado=N'CERRADO'
       AND es_ultimo=1 AND autorizado_por_supervisor_id=48) <> 1
 OR EXISTS
(
    SELECT p.palet_id
    FROM prod.palets p
    LEFT JOIN nav.operaciones n
      ON n.palet_id=p.palet_id AND n.orden_id=p.orden_id
     AND n.tipo=N'SALIDA_PALET'
    WHERE p.orden_id=31 AND p.sesion_linea_id=35 AND p.estado=N'CERRADO'
    GROUP BY p.palet_id
    HAVING COUNT(n.operacion_nav_id)<>1
        OR SUM(CASE WHEN n.estado=N'CONFIRMADA' THEN 1 ELSE 0 END)<>1
)
 OR EXISTS
(
    SELECT p.palet_id
    FROM prod.palets p
    LEFT JOIN imp.etiquetas e
      ON e.palet_id=p.palet_id AND e.orden_id=p.orden_id AND e.tipo=N'PALET'
    WHERE p.orden_id=31 AND p.sesion_linea_id=35 AND p.estado=N'CERRADO'
    GROUP BY p.palet_id
    HAVING COUNT(e.etiqueta_id)<>1
        OR SUM(CASE WHEN e.estado=N'IMPRESA' THEN 1 ELSE 0 END)<>1
)
 OR (SELECT COUNT(*) FROM imp.trabajos_impresion
     WHERE trabajo_impresion_id=23 AND etiqueta_id=33
       AND estado=N'COMPLETADO' AND es_reimpresion=0) <> 1
    THROW 51135, 'Los palets, salidas NAV o etiquetas no cumplen el cierre completo.', 1;
GO

IF EXISTS
(
    SELECT 1 FROM aud.eventos
    WHERE tipo_evento=N'CIERRE_FL_OBSOLETO_ANULADO'
      AND entidad=N'nav.operaciones' AND entidad_id=42
)
    THROW 51136, 'La operacion 42 ya fue retirada por 040A.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE
        @ahora_utc datetime2(3)=SYSUTCDATETIME(),
        @correlacion_id uniqueidentifier=NEWID();

    IF NOT EXISTS
    (
        SELECT 1
        FROM nav.operaciones WITH (UPDLOCK,HOLDLOCK)
        WHERE operacion_nav_id=42
          AND clave_idempotencia=N'MES:CIERRE_FL:31'
          AND tipo=N'CIERRE_FL' AND orden_id=31
          AND estado=N'PENDIENTE' AND numero_intentos=0
          AND identificador_externo IS NULL AND respuesta IS NULL
          AND reservado_utc IS NULL AND reservado_por IS NULL
          AND TRY_CONVERT(bigint,JSON_VALUE(payload,'$.orden_id'))=31
          AND JSON_VALUE(payload,'$.numero_orden')=N'FL26-00004'
          AND NULLIF(JSON_VALUE(payload,'$.ultimo_palet_uid'),N'') IS NOT NULL
    )
     OR EXISTS
    (
        SELECT 1 FROM nav.intentos_operacion WITH (UPDLOCK,HOLDLOCK)
        WHERE operacion_nav_id=42
    )
     OR NOT EXISTS
    (
        SELECT 1
        FROM nav.operaciones WITH (UPDLOCK,HOLDLOCK)
        WHERE operacion_nav_id=39
          AND clave_idempotencia=N'MES:CIERRE_FL:30'
          AND tipo=N'CIERRE_FL' AND orden_id=30
          AND estado=N'PENDIENTE' AND numero_intentos=0
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL AND reservado_por IS NULL
    )
     OR EXISTS
    (
        SELECT 1 FROM nav.intentos_operacion WITH (UPDLOCK,HOLDLOCK)
        WHERE operacion_nav_id=39
    )
        THROW 51137, 'Las operaciones 42 o 39 cambiaron durante 040A.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM prod.ordenes o WITH (UPDLOCK,HOLDLOCK)
        JOIN prod.sesiones_linea s WITH (UPDLOCK,HOLDLOCK) ON s.orden_id=o.orden_id
        JOIN prod.estados_linea el WITH (UPDLOCK,HOLDLOCK) ON el.linea_id=s.linea_id
        WHERE o.orden_id=31 AND o.numero_orden=N'FL26-00004'
          AND o.estado=N'PENDIENTE_NAV'
          AND o.cantidad_objetivo=100 AND o.cantidad_buena_acumulada=100
          AND o.cantidad_reservada_activa=0
          AND s.sesion_linea_id=35 AND s.estado=N'SIN_OPERARIOS'
          AND s.finalizada_utc IS NULL
          AND el.sesion_linea_id=35 AND el.estado=N'PENDIENTE_NAV'
          AND el.motivo_bloqueo=N'CIERRE_FL_PENDIENTE'
    )
     OR EXISTS
    (
        SELECT 1 FROM prod.fichajes WITH (UPDLOCK,HOLDLOCK)
        WHERE sesion_linea_id=35 AND salida_utc IS NULL
    )
     OR EXISTS
    (
        SELECT 1 FROM prod.tramos_capacidad WITH (UPDLOCK,HOLDLOCK)
        WHERE sesion_linea_id=35 AND fin_utc IS NULL
    )
     OR EXISTS
    (
        SELECT 1 FROM prod.reservas_palet WITH (UPDLOCK,HOLDLOCK)
        WHERE sesion_linea_id=35 AND estado=N'ACTIVA'
    )
        THROW 51138, 'El estado productivo cambio durante 040A.', 1;

    UPDATE nav.operaciones
    SET estado=N'ANULADA',
        respuesta=N'{"reason":"CIERRE_FL_SUPERSEDED_BY_LOCAL_COMPLETION","navWriteOperations":0}',
        proximo_intento_utc=NULL,
        procesada_utc=@ahora_utc,
        reservado_utc=NULL,
        reservado_por=NULL
    WHERE operacion_nav_id=42 AND tipo=N'CIERRE_FL' AND orden_id=31
      AND estado=N'PENDIENTE' AND numero_intentos=0
      AND identificador_externo IS NULL
      AND reservado_utc IS NULL AND reservado_por IS NULL;
    IF @@ROWCOUNT<>1
        THROW 51139, 'No se anulo exactamente la operacion 42.', 1;

    UPDATE prod.ordenes
    SET estado=N'PENDIENTE_CIERRE'
    WHERE orden_id=31 AND estado=N'PENDIENTE_NAV'
      AND cantidad_objetivo=100 AND cantidad_buena_acumulada=100
      AND cantidad_reservada_activa=0;
    IF @@ROWCOUNT<>1
        THROW 51140, 'No se restauro exactamente la orden 31.', 1;

    UPDATE prod.estados_linea
    SET estado=N'SIN_OPERARIOS',
        motivo_bloqueo=NULL,
        actualizado_utc=@ahora_utc
    WHERE sesion_linea_id=35 AND estado=N'PENDIENTE_NAV'
      AND motivo_bloqueo=N'CIERRE_FL_PENDIENTE';
    IF @@ROWCOUNT<>1
        THROW 51141, 'No se restauro exactamente el estado de linea.', 1;

    EXEC aud.registrar_evento
        @tipo_evento=N'CIERRE_FL_OBSOLETO_ANULADO',
        @cuenta_dominio=N'MES',
        @rol_usado=N'SISTEMA',
        @linea_id=40,
        @orden_id=31,
        @sesion_linea_id=35,
        @entidad=N'nav.operaciones',
        @entidad_id=42,
        @valor_anterior=N'{"estado":"PENDIENTE","numero_intentos":0}',
        @valor_nuevo=N'{"estado":"ANULADA","orden_estado":"PENDIENTE_CIERRE","navWriteOperations":0}',
        @motivo=N'Intencion CIERRE_FL sin adaptador externo, sustituida por el contrato local de finalizacion.',
        @correlacion_id=@correlacion_id;

    IF NOT EXISTS
    (
        SELECT 1 FROM nav.operaciones
        WHERE operacion_nav_id=42 AND orden_id=31 AND tipo=N'CIERRE_FL'
          AND estado=N'ANULADA' AND numero_intentos=0
          AND identificador_externo IS NULL
          AND JSON_VALUE(respuesta,'$.reason')=N'CIERRE_FL_SUPERSEDED_BY_LOCAL_COMPLETION'
          AND TRY_CONVERT(int,JSON_VALUE(respuesta,'$.navWriteOperations'))=0
          AND procesada_utc IS NOT NULL AND proximo_intento_utc IS NULL
          AND reservado_utc IS NULL AND reservado_por IS NULL
    )
     OR NOT EXISTS
    (
        SELECT 1 FROM prod.ordenes
        WHERE orden_id=31 AND estado=N'PENDIENTE_CIERRE'
          AND cantidad_objetivo=100 AND cantidad_buena_acumulada=100
          AND cantidad_reservada_activa=0
    )
     OR NOT EXISTS
    (
        SELECT 1 FROM prod.sesiones_linea s
        JOIN prod.estados_linea el ON el.linea_id=s.linea_id
        WHERE s.sesion_linea_id=35 AND s.estado=N'SIN_OPERARIOS'
          AND s.finalizada_utc IS NULL
          AND el.sesion_linea_id=35 AND el.estado=N'SIN_OPERARIOS'
          AND el.motivo_bloqueo IS NULL
    )
     OR NOT EXISTS
    (
        SELECT 1 FROM nav.operaciones
        WHERE operacion_nav_id=39 AND orden_id=30 AND tipo=N'CIERRE_FL'
          AND estado=N'PENDIENTE' AND numero_intentos=0
          AND identificador_externo IS NULL
          AND reservado_utc IS NULL AND reservado_por IS NULL
    )
     OR EXISTS (SELECT 1 FROM nav.intentos_operacion WHERE operacion_nav_id IN(39,42))
     OR (SELECT COUNT(*) FROM aud.eventos
         WHERE tipo_evento=N'CIERRE_FL_OBSOLETO_ANULADO'
           AND entidad=N'nav.operaciones' AND entidad_id=42
           AND orden_id=31 AND sesion_linea_id=35)<>1
        THROW 51142, 'La validacion final de 040A no es correcta.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
