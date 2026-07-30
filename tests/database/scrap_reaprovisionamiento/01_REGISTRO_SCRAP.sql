/*
Pruebas funcionales 013 — registro de scrap.
Requiere 00 ejecutado y paquete 013 instalado.
Estado: preparado para revision estatica; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 56100, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF (SELECT COUNT(*) FROM nav.empresas WHERE codigo = N'ZZTEST_013') <> 1
 OR (SELECT COUNT(*) FROM cfg.lineas WHERE codigo LIKE N'ZZ13-%') <> 4
 OR (SELECT COUNT(*) FROM seg.empleados WHERE codigo_nav LIKE N'ZZ13-%') <> 7
 OR (SELECT COUNT(*) FROM prod.ordenes WHERE numero_orden LIKE N'ZZ13-%') <> 3
    THROW 56101, 'Los fixtures 013 no estan completos.', 1;

IF OBJECT_ID(N'log.registrar_scrap', N'P') IS NULL
    THROW 56102, 'El procedimiento log.registrar_scrap no esta instalado.', 1;

DECLARE
    @supervisor_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-SUP1'),
    @operario_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-OP1'),
    @sin_rol_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-SINROL'),
    @linea_1_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ13-L01'),
    @linea_2_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ13-L02'),
    @linea_3_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ13-L03'),
    @linea_4_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ13-L04'),
    @orden_main_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-MAIN'),
    @orden_aux_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-AUX'),
    @orden_conc_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-CONC'),
    @motivo_componente_id smallint =
        (SELECT motivo_scrap_id FROM [log].motivos_scrap
         WHERE categoria = N'COMPONENTE' AND codigo = N'ROTO_PROCESO'),
    @motivo_otros_id smallint =
        (SELECT motivo_scrap_id FROM [log].motivos_scrap
         WHERE categoria = N'LUNA' AND codigo = N'OTROS');

DECLARE
    @formato_main_id bigint =
        (SELECT formato_palet_orden_id FROM prod.formatos_palet_orden
         WHERE orden_id = @orden_main_id AND codigo_formato = N'ZZ13-FMT-20'),
    @formato_aux_id bigint =
        (SELECT formato_palet_orden_id FROM prod.formatos_palet_orden
         WHERE orden_id = @orden_aux_id AND codigo_formato = N'ZZ13-FMT-20'),
    @formato_conc_id bigint =
        (SELECT formato_palet_orden_id FROM prod.formatos_palet_orden
         WHERE orden_id = @orden_conc_id AND codigo_formato = N'ZZ13-FMT-20'),
    @componente_main_a_id bigint =
        (SELECT componente_orden_id FROM nav.componentes_orden
         WHERE orden_id = @orden_main_id AND codigo_componente LIKE N'ZZ13-COMP-A-%'),
    @componente_main_b_id bigint =
        (SELECT componente_orden_id FROM nav.componentes_orden
         WHERE orden_id = @orden_main_id AND codigo_componente LIKE N'ZZ13-COMP-B-%'),
    @componente_aux_a_id bigint =
        (SELECT componente_orden_id FROM nav.componentes_orden
         WHERE orden_id = @orden_aux_id AND codigo_componente LIKE N'ZZ13-COMP-A-%'),
    @componente_conc_a_id bigint =
        (SELECT componente_orden_id FROM nav.componentes_orden
         WHERE orden_id = @orden_conc_id AND codigo_componente LIKE N'ZZ13-COMP-A-%');

IF @supervisor_1_id IS NULL OR @operario_1_id IS NULL OR @sin_rol_id IS NULL
 OR @linea_1_id IS NULL OR @linea_2_id IS NULL
 OR @linea_3_id IS NULL OR @linea_4_id IS NULL
 OR @orden_main_id IS NULL OR @orden_aux_id IS NULL OR @orden_conc_id IS NULL
 OR @formato_main_id IS NULL OR @formato_aux_id IS NULL OR @formato_conc_id IS NULL
 OR @componente_main_a_id IS NULL OR @componente_main_b_id IS NULL
 OR @componente_aux_a_id IS NULL OR @componente_conc_a_id IS NULL
 OR @motivo_componente_id IS NULL OR @motivo_otros_id IS NULL
    THROW 56103, 'Faltan identificadores sinteticos requeridos.', 1;

DECLARE
    @sesion_main_id bigint =
        (SELECT sesion_linea_id FROM prod.sesiones_linea
         WHERE orden_id = @orden_main_id AND linea_id = @linea_1_id
           AND finalizada_utc IS NULL),
    @sesion_aux_id bigint =
        (SELECT sesion_linea_id FROM prod.sesiones_linea
         WHERE orden_id = @orden_aux_id AND linea_id = @linea_2_id
           AND finalizada_utc IS NULL),
    @sesion_conc_a_id bigint =
        (SELECT sesion_linea_id FROM prod.sesiones_linea
         WHERE orden_id = @orden_conc_id AND linea_id = @linea_3_id
           AND finalizada_utc IS NULL),
    @sesion_conc_b_id bigint =
        (SELECT sesion_linea_id FROM prod.sesiones_linea
         WHERE orden_id = @orden_conc_id AND linea_id = @linea_4_id
           AND finalizada_utc IS NULL);

IF @sesion_main_id IS NULL
    EXEC prod.abrir_sesion_linea
        @orden_id = @orden_main_id,
        @linea_id = @linea_1_id,
        @formato_palet_orden_id = @formato_main_id,
        @supervisor_id = @supervisor_1_id,
        @inicio_fuera_horario_confirmado = 1,
        @correlacion_id = '13010000-0000-0000-0000-000000000001',
        @sesion_linea_id = @sesion_main_id OUTPUT;

IF @sesion_aux_id IS NULL
    EXEC prod.abrir_sesion_linea
        @orden_id = @orden_aux_id,
        @linea_id = @linea_2_id,
        @formato_palet_orden_id = @formato_aux_id,
        @supervisor_id = @supervisor_1_id,
        @inicio_fuera_horario_confirmado = 1,
        @correlacion_id = '13010000-0000-0000-0000-000000000002',
        @sesion_linea_id = @sesion_aux_id OUTPUT;

IF @sesion_conc_a_id IS NULL
    EXEC prod.abrir_sesion_linea
        @orden_id = @orden_conc_id,
        @linea_id = @linea_3_id,
        @formato_palet_orden_id = @formato_conc_id,
        @supervisor_id = @supervisor_1_id,
        @inicio_fuera_horario_confirmado = 1,
        @correlacion_id = '13010000-0000-0000-0000-000000000003',
        @sesion_linea_id = @sesion_conc_a_id OUTPUT;

IF @sesion_conc_b_id IS NULL
    EXEC prod.abrir_sesion_linea
        @orden_id = @orden_conc_id,
        @linea_id = @linea_4_id,
        @formato_palet_orden_id = @formato_conc_id,
        @supervisor_id = @supervisor_1_id,
        @inicio_fuera_horario_confirmado = 1,
        @correlacion_id = '13010000-0000-0000-0000-000000000004',
        @sesion_linea_id = @sesion_conc_b_id OUTPUT;

IF @sesion_main_id IS NULL OR @sesion_aux_id IS NULL
 OR @sesion_conc_a_id IS NULL OR @sesion_conc_b_id IS NULL
    THROW 56104, 'No se abrieron las cuatro sesiones sinteticas.', 1;

/* R01: alta valida por operario. */
DECLARE
    @scrap_operario_id bigint,
    @operacion_operario_id bigint;

EXEC [log].registrar_scrap
    @sesion_linea_id = @sesion_main_id,
    @componente_orden_id = @componente_main_a_id,
    @motivo_scrap_id = @motivo_componente_id,
    @cantidad = 2,
    @descripcion = N'ZZTEST 013 alta por operario',
    @registrado_por_empleado_id = @operario_1_id,
    @correlacion_id = '13010100-0000-0000-0000-000000000001',
    @scrap_id = @scrap_operario_id OUTPUT,
    @operacion_nav_id = @operacion_operario_id OUTPUT;

IF @scrap_operario_id IS NULL OR @operacion_operario_id IS NULL
    THROW 56105, 'R01 no devolvio scrap y operacion NAV.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM [log].scrap s
    JOIN nav.componentes_orden c
      ON c.componente_orden_id = s.componente_orden_id
     AND c.orden_id = s.orden_id
    WHERE s.scrap_id = @scrap_operario_id
      AND s.orden_id = @orden_main_id
      AND s.sesion_linea_id = @sesion_main_id
      AND s.linea_id = @linea_1_id
      AND s.cantidad = 2
      AND s.componente_codigo_snapshot = c.codigo_componente
      AND s.componente_descripcion_snapshot = c.descripcion
)
    THROW 56106, 'R01 no persistio contexto y snapshots correctos.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones
    WHERE operacion_nav_id = @operacion_operario_id
      AND tipo = N'CONSUMO_SCRAP'
      AND scrap_id = @scrap_operario_id
      AND revision_scrap_id IS NULL
      AND estado = N'PENDIENTE'
      AND ISJSON(payload) = 1
      AND JSON_VALUE(payload, '$.scrap_uid') IS NOT NULL
      AND TRY_CONVERT(int, JSON_VALUE(payload, '$.cantidad')) = 2
)
    THROW 56107, 'R01 no creo la operacion local CONSUMO_SCRAP esperada.', 1;

/* R02: alta valida por supervisor y motivo con descripcion obligatoria. */
DECLARE
    @scrap_supervisor_id bigint,
    @operacion_supervisor_id bigint;

EXEC [log].registrar_scrap
    @sesion_linea_id = @sesion_main_id,
    @componente_orden_id = @componente_main_b_id,
    @motivo_scrap_id = @motivo_otros_id,
    @cantidad = 1,
    @descripcion = N'ZZTEST 013 motivo otros descrito',
    @registrado_por_empleado_id = @supervisor_1_id,
    @correlacion_id = '13010200-0000-0000-0000-000000000001',
    @scrap_id = @scrap_supervisor_id OUTPUT,
    @operacion_nav_id = @operacion_supervisor_id OUTPUT;

IF @scrap_supervisor_id IS NULL OR @operacion_supervisor_id IS NULL
    THROW 56108, 'R02 no devolvio scrap y operacion NAV.', 1;

IF (SELECT cantidad_scrap_acumulada FROM prod.ordenes
    WHERE orden_id = @orden_main_id) <> 3
 OR (SELECT cantidad_objetivo FROM prod.ordenes
     WHERE orden_id = @orden_main_id) <> 100
 OR (SELECT cantidad_buena_acumulada FROM prod.ordenes
     WHERE orden_id = @orden_main_id) <> 0
    THROW 56109, 'R01-R02 alteraron incorrectamente cantidades de la orden.', 1;

/* R03: repeticion idempotente exacta. */
DECLARE
    @scrap_repetido_id bigint = -1,
    @operacion_repetida_id bigint = -1,
    @scrap_antes int =
        (SELECT COUNT(*) FROM [log].scrap WHERE orden_id = @orden_main_id),
    @operaciones_antes int =
        (SELECT COUNT(*) FROM nav.operaciones
         WHERE orden_id = @orden_main_id AND tipo = N'CONSUMO_SCRAP'),
    @auditoria_antes int =
        (SELECT COUNT(*) FROM aud.eventos
         WHERE correlacion_id = '13010100-0000-0000-0000-000000000001');

EXEC [log].registrar_scrap
    @sesion_linea_id = @sesion_main_id,
    @componente_orden_id = @componente_main_a_id,
    @motivo_scrap_id = @motivo_componente_id,
    @cantidad = 2,
    @descripcion = N'ZZTEST 013 alta por operario',
    @registrado_por_empleado_id = @operario_1_id,
    @correlacion_id = '13010100-0000-0000-0000-000000000001',
    @scrap_id = @scrap_repetido_id OUTPUT,
    @operacion_nav_id = @operacion_repetida_id OUTPUT;

IF @scrap_repetido_id <> @scrap_operario_id
 OR @operacion_repetida_id <> @operacion_operario_id
 OR (SELECT COUNT(*) FROM [log].scrap WHERE orden_id = @orden_main_id) <> @scrap_antes
 OR
 (
     SELECT COUNT(*) FROM nav.operaciones
     WHERE orden_id = @orden_main_id AND tipo = N'CONSUMO_SCRAP'
 ) <> @operaciones_antes
 OR
 (
     SELECT COUNT(*) FROM aud.eventos
     WHERE correlacion_id = '13010100-0000-0000-0000-000000000001'
 ) <> @auditoria_antes
    THROW 56110, 'R03 duplico filas o no devolvio el resultado anterior.', 1;

/* R04: misma correlacion con parametros diferentes. */
DECLARE
    @error int,
    @tran int,
    @xstate int,
    @salida_scrap bigint,
    @salida_operacion bigint;

BEGIN TRY
    SET @salida_scrap = -1;
    SET @salida_operacion = -1;

    EXEC [log].registrar_scrap
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_a_id,
        @motivo_scrap_id = @motivo_componente_id,
        @cantidad = 3,
        @descripcion = N'ZZTEST 013 alta por operario',
        @registrado_por_empleado_id = @operario_1_id,
        @correlacion_id = '13010100-0000-0000-0000-000000000001',
        @scrap_id = @salida_scrap OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56111, 'R04 debio rechazar la reutilizacion diferente.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55016 OR @tran <> 0 OR @xstate <> 0
    THROW 56112, 'R04 no devolvio 55016 con estado transaccional limpio.', 1;

/* R05: cantidad no positiva, validacion previa a transaccion. */
BEGIN TRY
    SET @error = NULL;
    SET @salida_scrap = -1;
    SET @salida_operacion = -1;

    EXEC [log].registrar_scrap
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_a_id,
        @motivo_scrap_id = @motivo_componente_id,
        @cantidad = 0,
        @registrado_por_empleado_id = @operario_1_id,
        @correlacion_id = '13010500-0000-0000-0000-000000000001',
        @scrap_id = @salida_scrap OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56113, 'R05 debio rechazar cantidad cero.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55003 OR @tran <> 0 OR @xstate <> 0
    THROW 56114, 'R05 no devolvio 55003 con estado transaccional limpio.', 1;

/* R06: componente de otra orden. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].registrar_scrap
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_aux_a_id,
        @motivo_scrap_id = @motivo_componente_id,
        @cantidad = 1,
        @registrado_por_empleado_id = @operario_1_id,
        @correlacion_id = '13010600-0000-0000-0000-000000000001',
        @scrap_id = @salida_scrap OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56115, 'R06 debio rechazar el componente ajeno.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55013 OR @tran <> 0 OR @xstate <> 0
    THROW 56116, 'R06 no devolvio 55013 con estado transaccional limpio.', 1;

/* R07: motivo inexistente. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].registrar_scrap
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_a_id,
        @motivo_scrap_id = 32767,
        @cantidad = 1,
        @registrado_por_empleado_id = @operario_1_id,
        @correlacion_id = '13010700-0000-0000-0000-000000000001',
        @scrap_id = @salida_scrap OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56117, 'R07 debio rechazar el motivo inexistente.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55014 OR @tran <> 0 OR @xstate <> 0
    THROW 56118, 'R07 no devolvio 55014 con estado transaccional limpio.', 1;

/* R08: motivo OTROS sin descripcion. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].registrar_scrap
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_a_id,
        @motivo_scrap_id = @motivo_otros_id,
        @cantidad = 1,
        @descripcion = N'   ',
        @registrado_por_empleado_id = @operario_1_id,
        @correlacion_id = '13010800-0000-0000-0000-000000000001',
        @scrap_id = @salida_scrap OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56119, 'R08 debio exigir descripcion.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55015 OR @tran <> 0 OR @xstate <> 0
    THROW 56120, 'R08 no devolvio 55015 con estado transaccional limpio.', 1;

/* R09: empleado activo sin rol funcional. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].registrar_scrap
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_a_id,
        @motivo_scrap_id = @motivo_componente_id,
        @cantidad = 1,
        @registrado_por_empleado_id = @sin_rol_id,
        @correlacion_id = '13010900-0000-0000-0000-000000000001',
        @scrap_id = @salida_scrap OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56121, 'R09 debio rechazar el empleado sin rol.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55012 OR @tran <> 0 OR @xstate <> 0
    THROW 56122, 'R09 no devolvio 55012 con estado transaccional limpio.', 1;

/* R10: sesion inexistente. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].registrar_scrap
        @sesion_linea_id = 9223372036854775807,
        @componente_orden_id = @componente_main_a_id,
        @motivo_scrap_id = @motivo_componente_id,
        @cantidad = 1,
        @registrado_por_empleado_id = @operario_1_id,
        @correlacion_id = '13011000-0000-0000-0000-000000000001',
        @scrap_id = @salida_scrap OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56123, 'R10 debio rechazar la sesion inexistente.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55009 OR @tran <> 0 OR @xstate <> 0
    THROW 56124, 'R10 no devolvio 55009 con estado transaccional limpio.', 1;

IF (SELECT COUNT(*) FROM [log].scrap WHERE orden_id = @orden_main_id) <> 2
 OR
 (
     SELECT COUNT(*) FROM nav.operaciones
     WHERE orden_id = @orden_main_id
       AND tipo = N'CONSUMO_SCRAP'
 ) <> 2
 OR (SELECT cantidad_scrap_acumulada FROM prod.ordenes
     WHERE orden_id = @orden_main_id) <> 3
    THROW 56125, 'Los rechazos dejaron efectos parciales o cardinalidad incorrecta.', 1;

IF
(
    SELECT COUNT(*)
    FROM aud.eventos
    WHERE tipo_evento = N'SCRAP_REGISTRADO'
      AND orden_id = @orden_main_id
) <> 2
    THROW 56126, 'La auditoria de altas validas no contiene dos eventos.', 1;

SELECT
    @sesion_main_id sesion_main_id,
    @sesion_aux_id sesion_aux_id,
    @sesion_conc_a_id sesion_conc_a_id,
    @sesion_conc_b_id sesion_conc_b_id,
    @scrap_operario_id scrap_operario_id,
    @scrap_supervisor_id scrap_supervisor_id,
    (SELECT cantidad_scrap_acumulada
     FROM prod.ordenes WHERE orden_id = @orden_main_id) scrap_acumulado,
    (SELECT cantidad_objetivo
     FROM prod.ordenes WHERE orden_id = @orden_main_id) objetivo_bueno,
    (SELECT cantidad_buena_acumulada
     FROM prod.ordenes WHERE orden_id = @orden_main_id) cantidad_buena;

PRINT N'PRUEBAS 013-01 REGISTRO SCRAP CORRECTAS';

