/*
Pruebas funcionales 012 - Paros individuales y retornos.
Requiere 00_PREVUELO_Y_FIXTURES_012.sql ejecutado previamente.
Estado: preparado para revision estatica; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 54100, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

DECLARE
    @orden_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ12-FL-NORMAL'),
    @linea_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ12-L01'),
    @formato_id bigint,
    @supervisor_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-SUP'),
    @operario_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-OP1'),
    @operario_2_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-OP2'),
    @operario_3_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-OP3'),
    @sesion_id bigint,
    @fichaje_1_id bigint,
    @fichaje_2_id bigint,
    @reserva_id bigint,
    @paro_1_id bigint,
    @paro_2_id bigint,
    @sustitucion_id bigint,
    @recursos int,
    @error int,
    @trancount_despues int,
    @xact_state_despues int;

SELECT @formato_id = formato_palet_orden_id
FROM prod.formatos_palet_orden
WHERE orden_id = @orden_id
  AND activo = 1;

IF @orden_id IS NULL OR @linea_id IS NULL OR @formato_id IS NULL
 OR @supervisor_id IS NULL OR @operario_1_id IS NULL
 OR @operario_2_id IS NULL OR @operario_3_id IS NULL
    THROW 54101, 'Faltan fixtures requeridos para 01.', 1;

IF EXISTS
(
    SELECT 1
    FROM prod.sesiones_linea
    WHERE linea_id = @linea_id
      AND finalizada_utc IS NULL
)
BEGIN
    SELECT @sesion_id = s.sesion_linea_id
    FROM prod.sesiones_linea s
    WHERE s.linea_id = @linea_id
      AND s.orden_id = @orden_id
      AND s.finalizada_utc IS NULL;

    SELECT @fichaje_1_id = fichaje_id
    FROM prod.fichajes
    WHERE sesion_linea_id = @sesion_id
      AND empleado_id = @operario_1_id
      AND salida_utc IS NULL;

    SELECT @fichaje_2_id = fichaje_id
    FROM prod.fichajes
    WHERE sesion_linea_id = @sesion_id
      AND empleado_id = @operario_2_id
      AND salida_utc IS NULL;

    SELECT
        @paro_1_id = po.paro_operario_id,
        @recursos = r.recursos_activos
    FROM prod.paros_operario po
    JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
    CROSS APPLY prod.recursos_efectivos_sesion(@sesion_id) r
    WHERE f.fichaje_id = @fichaje_1_id
      AND po.motivo = N'WC'
      AND po.fin_utc IS NULL;

    IF @sesion_id IS NULL OR @fichaje_1_id IS NULL OR @fichaje_2_id IS NULL
     OR @paro_1_id IS NULL OR @recursos <> 1
     OR
     (
         SELECT COUNT(*)
         FROM prod.paros_operario po
         JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
         WHERE f.sesion_linea_id = @sesion_id
           AND po.fin_utc IS NULL
     ) <> 1
        THROW 54102, 'El estado existente de L01 no es el parcial exacto P02.', 1;

    GOTO REANUDAR_P03;
END;

/* P01: apertura y dos entradas ordinarias dejan dos recursos. */
EXEC prod.abrir_sesion_linea
    @orden_id = @orden_id,
    @linea_id = @linea_id,
    @formato_palet_orden_id = @formato_id,
    @supervisor_id = @supervisor_id,
    @inicio_fuera_horario_confirmado = 1,
    @correlacion_id = '12010000-0000-0000-0000-000000000001',
    @sesion_linea_id = @sesion_id OUTPUT;

EXEC prod.registrar_entrada_productiva
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_1_id,
    @correlacion_id = '12010000-0000-0000-0000-000000000002',
    @fichaje_id = @fichaje_1_id OUTPUT,
    @reserva_palet_id = @reserva_id OUTPUT;

EXEC prod.registrar_entrada_productiva
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_2_id,
    @correlacion_id = '12010000-0000-0000-0000-000000000003',
    @fichaje_id = @fichaje_2_id OUTPUT,
    @reserva_palet_id = @reserva_id OUTPUT;

SELECT @recursos = recursos_activos
FROM prod.recursos_efectivos_sesion(@sesion_id);

IF @sesion_id IS NULL OR @fichaje_1_id IS NULL OR @fichaje_2_id IS NULL
 OR @recursos <> 2
    THROW 54103, 'P01: la preparacion no dejo dos recursos efectivos.', 1;

/* P02: WC excluye solo al operario afectado. */
EXEC prod.iniciar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_1_id,
    @motivo = N'WC',
    @correlacion_id = '12010000-0000-0000-0000-000000000004',
    @paro_operario_id = @paro_1_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @paro_1_id IS NULL OR @recursos <> 1
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.paros_operario
     WHERE paro_operario_id = @paro_1_id
       AND fichaje_id = @fichaje_1_id
       AND motivo = N'WC'
       AND fin_utc IS NULL
       AND estado = N'ABIERTO'
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_id
       AND fin_utc IS NULL
       AND recursos_activos = 1
       AND motivo_inicio = N'PARO_WC'
 )
    THROW 54104, 'P02: el WC no produjo el estado esperado.', 1;

/* P03: doble paro rechazado, sin salida transaccional ni OUTPUT residual. */
REANUDAR_P03:
SET @paro_2_id = -1;
SET @recursos = -1;
SET @error = NULL;

BEGIN TRY
    EXEC prod.iniciar_paro_operario
        @sesion_linea_id = @sesion_id,
        @empleado_id = @operario_1_id,
        @motivo = N'WC',
        @correlacion_id = '12010000-0000-0000-0000-000000000005',
        @paro_operario_id = @paro_2_id OUTPUT,
        @recursos_activos = @recursos OUTPUT;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;

SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error <> 52211 OR @paro_2_id <> -1 OR @recursos <> -1
 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
 OR
 (
     SELECT COUNT(*)
     FROM prod.paros_operario
     WHERE fichaje_id = @fichaje_1_id
       AND fin_utc IS NULL
 ) <> 1
    THROW 54105, 'P03: el doble paro no se rechazo limpiamente.', 1;

/* P04: el retorno de WC recupera el segundo recurso. */
SET @paro_2_id = NULL;
SET @sustitucion_id = NULL;

EXEC prod.finalizar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_1_id,
    @correlacion_id = '12010000-0000-0000-0000-000000000006',
    @paro_operario_id = @paro_2_id OUTPUT,
    @sustitucion_finalizada_id = @sustitucion_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @paro_2_id <> @paro_1_id OR @sustitucion_id IS NOT NULL OR @recursos <> 2
 OR EXISTS
 (
     SELECT 1 FROM prod.paros_operario
     WHERE paro_operario_id = @paro_1_id
       AND fin_utc IS NULL
 )
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_id
       AND fin_utc IS NULL
       AND recursos_activos = 2
       AND motivo_inicio = N'RETORNO_WC'
 )
    THROW 54106, 'P04: el retorno de WC no recupero la capacidad.', 1;

/* P05: PAUSA_CALOR usa su motivo y tramo propios. */
EXEC prod.iniciar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_2_id,
    @motivo = N' pausa_calor ',
    @correlacion_id = '12010000-0000-0000-0000-000000000007',
    @paro_operario_id = @paro_2_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @recursos <> 1
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.paros_operario
     WHERE paro_operario_id = @paro_2_id
       AND motivo = N'PAUSA_CALOR'
       AND fin_utc IS NULL
 )
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_id
       AND fin_utc IS NULL
       AND motivo_inicio = N'PARO_PAUSA_CALOR'
 )
    THROW 54107, 'P05: la pausa de calor no quedo normalizada.', 1;

EXEC prod.finalizar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_2_id,
    @correlacion_id = '12010000-0000-0000-0000-000000000008',
    @paro_operario_id = @paro_2_id OUTPUT,
    @sustitucion_finalizada_id = @sustitucion_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @recursos <> 2
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_id
       AND fin_utc IS NULL
       AND motivo_inicio = N'RETORNO_PAUSA_CALOR'
 )
    THROW 54108, 'P05: el retorno de pausa de calor no fue correcto.', 1;

/* P06: motivos ajenos al catalogo se rechazan sin mutacion. */
SET @paro_1_id = -1;
SET @recursos = -1;
SET @error = NULL;

BEGIN TRY
    EXEC prod.iniciar_paro_operario
        @sesion_linea_id = @sesion_id,
        @empleado_id = @operario_1_id,
        @motivo = N'OTRO',
        @correlacion_id = '12010000-0000-0000-0000-000000000009',
        @paro_operario_id = @paro_1_id OUTPUT,
        @recursos_activos = @recursos OUTPUT;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;

SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error <> 52201 OR @paro_1_id <> -1 OR @recursos <> -1
 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
    THROW 54109, 'P06: el motivo invalido no se rechazo limpiamente.', 1;

/* P07: los dos operarios ausentes dejan SIN_OPERARIOS y sin tramo abierto. */
EXEC prod.iniciar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_1_id,
    @motivo = N'WC',
    @correlacion_id = '12010000-0000-0000-0000-000000000010',
    @paro_operario_id = @paro_1_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @recursos <> 1
    THROW 54110, 'P07: el primer paro no dejo un recurso.', 1;

EXEC prod.iniciar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_2_id,
    @motivo = N'PAUSA_CALOR',
    @correlacion_id = '12010000-0000-0000-0000-000000000011',
    @paro_operario_id = @paro_2_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @recursos <> 0
 OR (SELECT estado FROM prod.sesiones_linea WHERE sesion_linea_id = @sesion_id)
       <> N'SIN_OPERARIOS'
 OR (SELECT estado FROM prod.estados_linea WHERE linea_id = @linea_id)
       <> N'SIN_OPERARIOS'
 OR EXISTS
 (
     SELECT 1 FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_id
       AND fin_utc IS NULL
 )
    THROW 54111, 'P07: la ausencia total no dejo SIN_OPERARIOS.', 1;

/* P08: el primer retorno reabre produccion y el segundo restaura dos recursos. */
EXEC prod.finalizar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_1_id,
    @correlacion_id = '12010000-0000-0000-0000-000000000012',
    @paro_operario_id = @paro_1_id OUTPUT,
    @sustitucion_finalizada_id = @sustitucion_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @recursos <> 1
 OR (SELECT estado FROM prod.sesiones_linea WHERE sesion_linea_id = @sesion_id)
       <> N'PRODUCIENDO'
 OR (SELECT estado FROM prod.estados_linea WHERE linea_id = @linea_id)
       <> N'PRODUCIENDO'
    THROW 54112, 'P08: el primer retorno no reabrio produccion.', 1;

EXEC prod.finalizar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_2_id,
    @correlacion_id = '12010000-0000-0000-0000-000000000013',
    @paro_operario_id = @paro_2_id OUTPUT,
    @sustitucion_finalizada_id = @sustitucion_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @recursos <> 2
 OR EXISTS
 (
     SELECT 1
     FROM prod.paros_operario po
     JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
     WHERE f.sesion_linea_id = @sesion_id
       AND po.fin_utc IS NULL
 )
 OR
 (
     SELECT COUNT(*)
     FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_id
       AND fin_utc IS NULL
 ) <> 1
    THROW 54113, 'P08: el estado final de retornos no es correcto.', 1;

/* P09: un empleado sin fichaje no puede iniciar un paro. */
SET @paro_1_id = -1;
SET @recursos = -1;
SET @error = NULL;

BEGIN TRY
    EXEC prod.iniciar_paro_operario
        @sesion_linea_id = @sesion_id,
        @empleado_id = @operario_3_id,
        @motivo = N'WC',
        @correlacion_id = '12010000-0000-0000-0000-000000000014',
        @paro_operario_id = @paro_1_id OUTPUT,
        @recursos_activos = @recursos OUTPUT;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;

SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error <> 52210 OR @paro_1_id <> -1 OR @recursos <> -1
 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
    THROW 54114, 'P09: el empleado sin fichaje no se rechazo limpiamente.', 1;

IF
(
    SELECT COUNT(*)
    FROM aud.eventos
    WHERE sesion_linea_id = @sesion_id
      AND tipo_evento = N'PARO_OPERARIO_INICIADO'
) <> 4
 OR
(
    SELECT COUNT(*)
    FROM aud.eventos
    WHERE sesion_linea_id = @sesion_id
      AND tipo_evento = N'PARO_OPERARIO_FINALIZADO'
) <> 4
    THROW 54115, 'La auditoria de paros y retornos no tiene cardinalidad esperada.', 1;

SELECT
    @sesion_id AS sesion_linea_id,
    @fichaje_1_id AS fichaje_operario_1,
    @fichaje_2_id AS fichaje_operario_2,
    @recursos AS recursos_finales,
    (SELECT estado FROM prod.sesiones_linea WHERE sesion_linea_id = @sesion_id)
        AS estado_sesion,
    (SELECT estado FROM prod.estados_linea WHERE linea_id = @linea_id)
        AS estado_linea;

PRINT N'01 PAROS Y RETORNOS COMPLETADO';
