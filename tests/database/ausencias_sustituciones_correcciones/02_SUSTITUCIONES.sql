/*
Pruebas funcionales 012 - Sustituciones de capacidad.
Requiere 00 y 01 ejecutados previamente.
Estado: preparado para revision estatica; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 54200, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

DECLARE
    @sesion_id bigint =
    (
        SELECT s.sesion_linea_id
        FROM prod.sesiones_linea s
        JOIN cfg.lineas l ON l.linea_id = s.linea_id
        WHERE l.codigo = N'ZZ12-L01'
          AND s.finalizada_utc IS NULL
    ),
    @operario_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-OP1'),
    @operario_2_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-OP2'),
    @supervisor_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-SUP'),
    @supervisor_2_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-SUP2'),
    @paro_1_id bigint,
    @paro_2_id bigint,
    @sustitucion_id bigint,
    @sustitucion_devuelta_id bigint,
    @fichaje_supervisor_id bigint,
    @recursos int,
    @error int,
    @trancount_despues int,
    @xact_state_despues int;

IF @sesion_id IS NULL OR @operario_1_id IS NULL OR @operario_2_id IS NULL
 OR @supervisor_id IS NULL OR @supervisor_2_id IS NULL
    THROW 54201, 'Faltan fixtures o estado previo de 01.', 1;

IF (SELECT recursos_activos FROM prod.recursos_efectivos_sesion(@sesion_id)) <> 2
    THROW 54202, '02 requiere dos recursos efectivos.', 1;

IF EXISTS
(
     SELECT 1
     FROM prod.sustituciones_capacidad
     WHERE sesion_linea_id = @sesion_id
       AND fin_utc IS NULL
)
BEGIN
    SELECT
        @sustitucion_id = sc.sustitucion_capacidad_id,
        @fichaje_supervisor_id = sc.fichaje_supervisor_id,
        @paro_1_id = po.paro_operario_id
    FROM prod.sustituciones_capacidad sc
    JOIN prod.paros_operario po
      ON po.fichaje_id = sc.fichaje_operario_id
     AND po.fin_utc IS NULL
    WHERE sc.sesion_linea_id = @sesion_id
      AND sc.operario_sustituido_id = @operario_1_id
      AND sc.supervisor_sustituto_id = @supervisor_id
      AND sc.fin_utc IS NULL;

    IF @sustitucion_id IS NULL OR @fichaje_supervisor_id IS NULL
     OR @paro_1_id IS NULL
     OR
     (
         SELECT COUNT(*)
         FROM prod.sustituciones_capacidad
         WHERE sesion_linea_id = @sesion_id
           AND fin_utc IS NULL
     ) <> 1
        THROW 54202, 'El estado existente no es el parcial exacto S01.', 1;

    GOTO REANUDAR_S02;
END;

/* S01: sustitucion valida restaura exactamente la plaza ausente. */
EXEC prod.iniciar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_1_id,
    @motivo = N'WC',
    @correlacion_id = '12020000-0000-0000-0000-000000000001',
    @paro_operario_id = @paro_1_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @recursos <> 1
    THROW 54203, 'S01: el paro previo no redujo la dotacion.', 1;

EXEC prod.iniciar_sustitucion_capacidad
    @sesion_linea_id = @sesion_id,
    @operario_sustituido_id = @operario_1_id,
    @supervisor_sustituto_id = @supervisor_id,
    @motivo = N'Cobertura WC',
    @correlacion_id = '12020000-0000-0000-0000-000000000002',
    @sustitucion_capacidad_id = @sustitucion_id OUTPUT,
    @fichaje_supervisor_id = @fichaje_supervisor_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @sustitucion_id IS NULL OR @fichaje_supervisor_id IS NULL OR @recursos <> 2
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.sustituciones_capacidad
     WHERE sustitucion_capacidad_id = @sustitucion_id
       AND operario_sustituido_id = @operario_1_id
       AND supervisor_sustituto_id = @supervisor_id
       AND fin_utc IS NULL
       AND estado = N'ACTIVA'
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.fichajes
     WHERE fichaje_id = @fichaje_supervisor_id
       AND empleado_id = @supervisor_id
       AND salida_utc IS NULL
 )
    THROW 54204, 'S01: la sustitucion valida no quedo activa.', 1;

/* S02: el mismo operario no admite una segunda sustitucion concurrente. */
REANUDAR_S02:
SET @sustitucion_devuelta_id = -1;
SET @recursos = -1;
SET @error = NULL;

BEGIN TRY
    EXEC prod.iniciar_sustitucion_capacidad
        @sesion_linea_id = @sesion_id,
        @operario_sustituido_id = @operario_1_id,
        @supervisor_sustituto_id = @supervisor_2_id,
        @motivo = N'Duplicada',
        @correlacion_id = '12020000-0000-0000-0000-000000000003',
        @sustitucion_capacidad_id = @sustitucion_devuelta_id OUTPUT,
        @fichaje_supervisor_id = @paro_2_id OUTPUT,
        @recursos_activos = @recursos OUTPUT;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;

SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error <> 52415 OR @sustitucion_devuelta_id <> -1
 OR @paro_2_id IS NOT NULL OR @recursos <> -1
 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
    THROW 54205, 'S02: la sustitucion duplicada no se rechazo limpiamente.', 1;

/* S03: el retorno finaliza automaticamente sustitucion y fichaje supervisor. */
SET @sustitucion_devuelta_id = NULL;

EXEC prod.finalizar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_1_id,
    @correlacion_id = '12020000-0000-0000-0000-000000000004',
    @paro_operario_id = @paro_2_id OUTPUT,
    @sustitucion_finalizada_id = @sustitucion_devuelta_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @paro_2_id <> @paro_1_id OR @sustitucion_devuelta_id <> @sustitucion_id
 OR @recursos <> 2
 OR EXISTS
 (
     SELECT 1 FROM prod.sustituciones_capacidad
     WHERE sustitucion_capacidad_id = @sustitucion_id
       AND fin_utc IS NULL
 )
 OR EXISTS
 (
     SELECT 1 FROM prod.fichajes
     WHERE fichaje_id = @fichaje_supervisor_id
       AND salida_utc IS NULL
 )
    THROW 54206, 'S03: el retorno no finalizo automaticamente la cobertura.', 1;

/* S04: finalizar antes mantiene el paro y reduce un recurso. */
EXEC prod.iniciar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_1_id,
    @motivo = N'PAUSA_CALOR',
    @correlacion_id = '12020000-0000-0000-0000-000000000005',
    @paro_operario_id = @paro_1_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

EXEC prod.iniciar_sustitucion_capacidad
    @sesion_linea_id = @sesion_id,
    @operario_sustituido_id = @operario_1_id,
    @supervisor_sustituto_id = @supervisor_id,
    @motivo = N'Cobertura calor',
    @correlacion_id = '12020000-0000-0000-0000-000000000006',
    @sustitucion_capacidad_id = @sustitucion_id OUTPUT,
    @fichaje_supervisor_id = @fichaje_supervisor_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

EXEC prod.finalizar_sustitucion_capacidad
    @sustitucion_capacidad_id = @sustitucion_id,
    @supervisor_id = @supervisor_2_id,
    @motivo = N'Fin anticipado de cobertura',
    @correlacion_id = '12020000-0000-0000-0000-000000000007',
    @recursos_activos = @recursos OUTPUT;

IF @recursos <> 1
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.paros_operario
     WHERE paro_operario_id = @paro_1_id
       AND fin_utc IS NULL
 )
 OR EXISTS
 (
     SELECT 1 FROM prod.sustituciones_capacidad
     WHERE sustitucion_capacidad_id = @sustitucion_id
       AND fin_utc IS NULL
 )
 OR EXISTS
 (
     SELECT 1 FROM prod.fichajes
     WHERE fichaje_id = @fichaje_supervisor_id
       AND salida_utc IS NULL
 )
    THROW 54207, 'S04: el fin anticipado no dejo el estado esperado.', 1;

/* S05: el retorno posterior recupera la plaza sin doble finalizacion. */
SET @sustitucion_devuelta_id = -1;

EXEC prod.finalizar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_1_id,
    @correlacion_id = '12020000-0000-0000-0000-000000000008',
    @paro_operario_id = @paro_2_id OUTPUT,
    @sustitucion_finalizada_id = @sustitucion_devuelta_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @paro_2_id <> @paro_1_id OR @sustitucion_devuelta_id IS NOT NULL
 OR @recursos <> 2
    THROW 54208, 'S05: el retorno posterior no recupero un recurso.', 1;

/* S06: no puede sustituirse un operario que no esta en paro. */
SET @sustitucion_id = -1;
SET @fichaje_supervisor_id = -1;
SET @recursos = -1;
SET @error = NULL;

BEGIN TRY
    EXEC prod.iniciar_sustitucion_capacidad
        @sesion_linea_id = @sesion_id,
        @operario_sustituido_id = @operario_2_id,
        @supervisor_sustituto_id = @supervisor_id,
        @motivo = N'Sin paro',
        @correlacion_id = '12020000-0000-0000-0000-000000000009',
        @sustitucion_capacidad_id = @sustitucion_id OUTPUT,
        @fichaje_supervisor_id = @fichaje_supervisor_id OUTPUT,
        @recursos_activos = @recursos OUTPUT;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;

SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error <> 52414 OR @sustitucion_id <> -1
 OR @fichaje_supervisor_id <> -1 OR @recursos <> -1
 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
    THROW 54209, 'S06: la sustitucion sin paro no se rechazo limpiamente.', 1;

IF EXISTS
(
    SELECT 1
    FROM prod.sustituciones_capacidad
    WHERE sesion_linea_id = @sesion_id
      AND fin_utc IS NULL
)
 OR EXISTS
(
    SELECT 1
    FROM prod.paros_operario po
    JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
    WHERE f.sesion_linea_id = @sesion_id
      AND po.fin_utc IS NULL
)
 OR (SELECT recursos_activos FROM prod.recursos_efectivos_sesion(@sesion_id)) <> 2
    THROW 54210, '02 no dejo el estado funcional limpio esperado.', 1;

IF
(
    SELECT COUNT(*)
    FROM aud.eventos
    WHERE sesion_linea_id = @sesion_id
      AND tipo_evento = N'SUSTITUCION_CAPACIDAD_INICIADA'
) <> 2
 OR
(
    SELECT COUNT(*)
    FROM aud.eventos
    WHERE sesion_linea_id = @sesion_id
      AND tipo_evento = N'SUSTITUCION_CAPACIDAD_FINALIZADA_AUTO'
) <> 1
 OR
(
    SELECT COUNT(*)
    FROM aud.eventos
    WHERE sesion_linea_id = @sesion_id
      AND tipo_evento = N'SUSTITUCION_CAPACIDAD_FINALIZADA'
) <> 1
    THROW 54211, 'La auditoria de sustituciones no tiene cardinalidad esperada.', 1;

SELECT
    @sesion_id AS sesion_linea_id,
    (SELECT recursos_activos FROM prod.recursos_efectivos_sesion(@sesion_id))
        AS recursos_finales,
    (SELECT COUNT(*) FROM prod.sustituciones_capacidad
     WHERE sesion_linea_id = @sesion_id) AS sustituciones_historicas;

PRINT N'02 SUSTITUCIONES COMPLETADO';
