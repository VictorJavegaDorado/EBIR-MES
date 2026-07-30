/*
Pruebas funcionales 013 — revisiones y anulacion de scrap.
Requiere 00 y 01 ejecutados en orden.
Estado: preparado para revision estatica; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 56200, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'log.revisar_scrap', N'P') IS NULL
 OR OBJECT_ID(N'log.registrar_scrap', N'P') IS NULL
    THROW 56201, 'Los procedimientos 013 requeridos no estan instalados.', 1;

DECLARE
    @supervisor_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-SUP1'),
    @operario_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-OP1'),
    @orden_main_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-MAIN'),
    @orden_conc_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-CONC'),
    @sesion_conc_a_id bigint,
    @motivo_componente_id smallint =
        (SELECT motivo_scrap_id FROM [log].motivos_scrap
         WHERE categoria = N'COMPONENTE' AND codigo = N'ROTO_PROCESO'),
    @motivo_otros_id smallint =
        (SELECT motivo_scrap_id FROM [log].motivos_scrap
         WHERE categoria = N'LUNA' AND codigo = N'OTROS');

SELECT @sesion_conc_a_id = s.sesion_linea_id
FROM prod.sesiones_linea s
JOIN cfg.lineas l ON l.linea_id = s.linea_id
WHERE s.orden_id = @orden_conc_id
  AND l.codigo = N'ZZ13-L03'
  AND s.finalizada_utc IS NULL;

DECLARE
    @componente_main_a_id bigint =
        (SELECT componente_orden_id FROM nav.componentes_orden
         WHERE orden_id = @orden_main_id AND codigo_componente LIKE N'ZZ13-COMP-A-%'),
    @componente_main_b_id bigint =
        (SELECT componente_orden_id FROM nav.componentes_orden
         WHERE orden_id = @orden_main_id AND codigo_componente LIKE N'ZZ13-COMP-B-%'),
    @componente_conc_a_id bigint =
        (SELECT componente_orden_id FROM nav.componentes_orden
         WHERE orden_id = @orden_conc_id AND codigo_componente LIKE N'ZZ13-COMP-A-%'),
    @componente_conc_b_id bigint =
        (SELECT componente_orden_id FROM nav.componentes_orden
         WHERE orden_id = @orden_conc_id AND codigo_componente LIKE N'ZZ13-COMP-B-%'),
    @scrap_principal_id bigint =
        (SELECT scrap_id FROM [log].scrap
         WHERE orden_id = @orden_main_id
           AND descripcion = N'ZZTEST 013 alta por operario'),
    @scrap_secundario_id bigint =
        (SELECT scrap_id FROM [log].scrap
         WHERE orden_id = @orden_main_id
           AND descripcion = N'ZZTEST 013 motivo otros descrito');

IF @supervisor_1_id IS NULL OR @operario_1_id IS NULL
 OR @orden_main_id IS NULL OR @orden_conc_id IS NULL
 OR @sesion_conc_a_id IS NULL
 OR @componente_main_a_id IS NULL OR @componente_main_b_id IS NULL
 OR @componente_conc_a_id IS NULL OR @componente_conc_b_id IS NULL
 OR @motivo_componente_id IS NULL OR @motivo_otros_id IS NULL
 OR @scrap_principal_id IS NULL OR @scrap_secundario_id IS NULL
    THROW 56202, 'No existe el estado acumulativo requerido de 01.', 1;

IF (SELECT cantidad_scrap_acumulada FROM prod.ordenes
    WHERE orden_id = @orden_main_id) <> 3
 OR (SELECT COUNT(*) FROM [log].revisiones_scrap
     WHERE scrap_id IN (@scrap_principal_id, @scrap_secundario_id)) <> 0
    THROW 56203, 'El punto de partida de cantidades o revisiones no es correcto.', 1;

/* V01: correccion completa del scrap principal: 2 -> 5. */
DECLARE
    @revision_1_id bigint,
    @operacion_ajuste_1_id bigint;

EXEC [log].revisar_scrap
    @scrap_id = @scrap_principal_id,
    @componente_orden_id = @componente_main_b_id,
    @motivo_scrap_id = @motivo_otros_id,
    @cantidad = 5,
    @descripcion = N'ZZTEST 013 scrap corregido a cinco',
    @es_anulacion = 0,
    @ajustado_por_supervisor_id = @supervisor_1_id,
    @motivo_ajuste = N'ZZTEST 013 correccion funcional',
    @correlacion_id = '13020100-0000-0000-0000-000000000001',
    @revision_scrap_id = @revision_1_id OUTPUT,
    @operacion_nav_id = @operacion_ajuste_1_id OUTPUT;

IF @revision_1_id IS NULL OR @operacion_ajuste_1_id IS NULL
    THROW 56204, 'V01 no devolvio revision y operacion.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM [log].revisiones_scrap
    WHERE revision_scrap_id = @revision_1_id
      AND scrap_id = @scrap_principal_id
      AND numero_revision = 1
      AND componente_orden_id = @componente_main_b_id
      AND motivo_scrap_id = @motivo_otros_id
      AND cantidad = 5
      AND es_anulacion = 0
      AND descripcion = N'ZZTEST 013 scrap corregido a cinco'
)
    THROW 56205, 'V01 no persistio la revision completa esperada.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM [log].scrap
    WHERE scrap_id = @scrap_principal_id
      AND componente_orden_id = @componente_main_a_id
      AND motivo_scrap_id = @motivo_componente_id
      AND cantidad = 2
      AND descripcion = N'ZZTEST 013 alta por operario'
)
    THROW 56206, 'V01 modifico indebidamente el scrap original.', 1;

IF (SELECT cantidad_scrap_acumulada FROM prod.ordenes
    WHERE orden_id = @orden_main_id) <> 6
    THROW 56207, 'V01 no aplico el delta +3 al acumulado.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones
    WHERE operacion_nav_id = @operacion_ajuste_1_id
      AND tipo = N'AJUSTE_CONSUMO_SCRAP'
      AND scrap_id = @scrap_principal_id
      AND revision_scrap_id = @revision_1_id
      AND estado = N'PENDIENTE'
      AND TRY_CONVERT(int, JSON_VALUE(payload, '$.cantidad_anterior')) = 2
      AND TRY_CONVERT(int, JSON_VALUE(payload, '$.cantidad_nueva')) = 5
      AND TRY_CONVERT(int, JSON_VALUE(payload, '$.delta_consumo')) = 3
)
    THROW 56208, 'V01 no creo el ajuste NAV con delta correcto.', 1;

/* V02: repeticion idempotente exacta. */
DECLARE
    @revision_repetida_id bigint = -1,
    @operacion_repetida_id bigint = -1,
    @revisiones_antes int =
        (SELECT COUNT(*) FROM [log].revisiones_scrap
         WHERE scrap_id = @scrap_principal_id),
    @operaciones_antes int =
        (SELECT COUNT(*) FROM nav.operaciones
         WHERE scrap_id = @scrap_principal_id),
    @auditoria_antes int =
        (SELECT COUNT(*) FROM aud.eventos
         WHERE correlacion_id = '13020100-0000-0000-0000-000000000001');

EXEC [log].revisar_scrap
    @scrap_id = @scrap_principal_id,
    @componente_orden_id = @componente_main_b_id,
    @motivo_scrap_id = @motivo_otros_id,
    @cantidad = 5,
    @descripcion = N'ZZTEST 013 scrap corregido a cinco',
    @es_anulacion = 0,
    @ajustado_por_supervisor_id = @supervisor_1_id,
    @motivo_ajuste = N'ZZTEST 013 correccion funcional',
    @correlacion_id = '13020100-0000-0000-0000-000000000001',
    @revision_scrap_id = @revision_repetida_id OUTPUT,
    @operacion_nav_id = @operacion_repetida_id OUTPUT;

IF @revision_repetida_id <> @revision_1_id
 OR @operacion_repetida_id <> @operacion_ajuste_1_id
 OR (SELECT COUNT(*) FROM [log].revisiones_scrap
     WHERE scrap_id = @scrap_principal_id) <> @revisiones_antes
 OR (SELECT COUNT(*) FROM nav.operaciones
     WHERE scrap_id = @scrap_principal_id) <> @operaciones_antes
 OR (SELECT COUNT(*) FROM aud.eventos
     WHERE correlacion_id = '13020100-0000-0000-0000-000000000001') <> @auditoria_antes
    THROW 56209, 'V02 no fue idempotente.', 1;

/* V03: revision identica con correlacion nueva. */
DECLARE
    @error int,
    @tran int,
    @xstate int,
    @salida_revision bigint,
    @salida_operacion bigint;

BEGIN TRY
    EXEC [log].revisar_scrap
        @scrap_id = @scrap_principal_id,
        @componente_orden_id = @componente_main_b_id,
        @motivo_scrap_id = @motivo_otros_id,
        @cantidad = 5,
        @descripcion = N'ZZTEST 013 scrap corregido a cinco',
        @es_anulacion = 0,
        @ajustado_por_supervisor_id = @supervisor_1_id,
        @motivo_ajuste = N'ZZTEST 013 intento identico',
        @correlacion_id = '13020300-0000-0000-0000-000000000001',
        @revision_scrap_id = @salida_revision OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56210, 'V03 debio rechazar la revision identica.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55117 OR @tran <> 0 OR @xstate <> 0
    THROW 56211, 'V03 no devolvio 55117 con estado limpio.', 1;

/* V04: usuario no supervisor. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].revisar_scrap
        @scrap_id = @scrap_secundario_id,
        @componente_orden_id = @componente_main_b_id,
        @motivo_scrap_id = @motivo_otros_id,
        @cantidad = 2,
        @descripcion = N'ZZTEST 013 intento por operario',
        @es_anulacion = 0,
        @ajustado_por_supervisor_id = @operario_1_id,
        @motivo_ajuste = N'ZZTEST 013 rol invalido',
        @correlacion_id = '13020400-0000-0000-0000-000000000001',
        @revision_scrap_id = @salida_revision OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56212, 'V04 debio rechazar al operario.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55113 OR @tran <> 0 OR @xstate <> 0
    THROW 56213, 'V04 no devolvio 55113 con estado limpio.', 1;

/* V05: ultima operacion PROCESANDO. La transaccion exterior se revierte
   automaticamente por el ROLLBACK del procedimiento rechazado. */
BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE nav.operaciones
    SET estado = N'PROCESANDO'
    WHERE scrap_id = @scrap_secundario_id
      AND tipo = N'CONSUMO_SCRAP';

    EXEC [log].revisar_scrap
        @scrap_id = @scrap_secundario_id,
        @componente_orden_id = @componente_main_b_id,
        @motivo_scrap_id = @motivo_otros_id,
        @cantidad = 2,
        @descripcion = N'ZZTEST 013 bloqueado procesando',
        @es_anulacion = 0,
        @ajustado_por_supervisor_id = @supervisor_1_id,
        @motivo_ajuste = N'ZZTEST 013 estado procesando',
        @correlacion_id = '13020500-0000-0000-0000-000000000001',
        @revision_scrap_id = @salida_revision OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56214, 'V05 debio bloquear PROCESANDO.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55119 OR @tran <> 0 OR @xstate <> 0
    THROW 56215, 'V05 no devolvio 55119 con rollback completo.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM nav.operaciones
    WHERE scrap_id = @scrap_secundario_id
      AND tipo = N'CONSUMO_SCRAP'
      AND estado = N'PENDIENTE'
)
    THROW 56216, 'V05 no revirtio el estado NAV sintetico.', 1;

/* V06: ultima operacion RESULTADO_DESCONOCIDO. */
BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE nav.operaciones
    SET estado = N'RESULTADO_DESCONOCIDO'
    WHERE scrap_id = @scrap_secundario_id
      AND tipo = N'CONSUMO_SCRAP';

    EXEC [log].revisar_scrap
        @scrap_id = @scrap_secundario_id,
        @componente_orden_id = @componente_main_b_id,
        @motivo_scrap_id = @motivo_otros_id,
        @cantidad = 2,
        @descripcion = N'ZZTEST 013 bloqueado desconocido',
        @es_anulacion = 0,
        @ajustado_por_supervisor_id = @supervisor_1_id,
        @motivo_ajuste = N'ZZTEST 013 resultado desconocido',
        @correlacion_id = '13020600-0000-0000-0000-000000000001',
        @revision_scrap_id = @salida_revision OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56217, 'V06 debio bloquear RESULTADO_DESCONOCIDO.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55119 OR @tran <> 0 OR @xstate <> 0
    THROW 56218, 'V06 no devolvio 55119 con rollback completo.', 1;

/* V07: proteccion ante acumulado incoherente que produciria negativo. */
BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE prod.ordenes
    SET cantidad_scrap_acumulada = 0
    WHERE orden_id = @orden_main_id;

    EXEC [log].revisar_scrap
        @scrap_id = @scrap_secundario_id,
        @componente_orden_id = @componente_main_b_id,
        @motivo_scrap_id = @motivo_otros_id,
        @cantidad = 0,
        @descripcion = NULL,
        @es_anulacion = 1,
        @ajustado_por_supervisor_id = @supervisor_1_id,
        @motivo_ajuste = N'ZZTEST 013 acumulado negativo',
        @correlacion_id = '13020700-0000-0000-0000-000000000001',
        @revision_scrap_id = @salida_revision OUTPUT,
        @operacion_nav_id = @salida_operacion OUTPUT;

    THROW 56219, 'V07 debio proteger el acumulado.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55120 OR @tran <> 0 OR @xstate <> 0
    THROW 56220, 'V07 no devolvio 55120 con rollback completo.', 1;

IF (SELECT cantidad_scrap_acumulada FROM prod.ordenes
    WHERE orden_id = @orden_main_id) <> 6
    THROW 56221, 'V07 no revirtio el acumulado sintetico.', 1;

/* V08: ERROR_REINTENTABLE admite una revision posterior. */
DECLARE
    @scrap_conc_id bigint,
    @operacion_conc_inicial_id bigint,
    @revision_conc_id bigint,
    @operacion_conc_ajuste_id bigint;

EXEC [log].registrar_scrap
    @sesion_linea_id = @sesion_conc_a_id,
    @componente_orden_id = @componente_conc_a_id,
    @motivo_scrap_id = @motivo_componente_id,
    @cantidad = 4,
    @descripcion = N'ZZTEST 013 scrap para concurrencia',
    @registrado_por_empleado_id = @operario_1_id,
    @correlacion_id = '13020800-0000-0000-0000-000000000001',
    @scrap_id = @scrap_conc_id OUTPUT,
    @operacion_nav_id = @operacion_conc_inicial_id OUTPUT;

UPDATE nav.operaciones
SET estado = N'ERROR_REINTENTABLE'
WHERE operacion_nav_id = @operacion_conc_inicial_id;

EXEC [log].revisar_scrap
    @scrap_id = @scrap_conc_id,
    @componente_orden_id = @componente_conc_b_id,
    @motivo_scrap_id = @motivo_componente_id,
    @cantidad = 6,
    @descripcion = N'ZZTEST 013 revisado tras error reintentable',
    @es_anulacion = 0,
    @ajustado_por_supervisor_id = @supervisor_1_id,
    @motivo_ajuste = N'ZZTEST 013 ajuste permitido',
    @correlacion_id = '13020800-0000-0000-0000-000000000002',
    @revision_scrap_id = @revision_conc_id OUTPUT,
    @operacion_nav_id = @operacion_conc_ajuste_id OUTPUT;

IF @revision_conc_id IS NULL OR @operacion_conc_ajuste_id IS NULL
 OR (SELECT cantidad_scrap_acumulada FROM prod.ordenes
     WHERE orden_id = @orden_conc_id) <> 6
    THROW 56222, 'V08 no admitio correctamente ERROR_REINTENTABLE.', 1;

/* V09: anulacion del scrap principal efectivo 5 -> 0. */
DECLARE
    @revision_anulacion_id bigint,
    @operacion_anulacion_id bigint;

EXEC [log].revisar_scrap
    @scrap_id = @scrap_principal_id,
    @componente_orden_id = @componente_main_b_id,
    @motivo_scrap_id = @motivo_otros_id,
    @cantidad = 0,
    @descripcion = NULL,
    @es_anulacion = 1,
    @ajustado_por_supervisor_id = @supervisor_1_id,
    @motivo_ajuste = N'ZZTEST 013 anulacion funcional',
    @correlacion_id = '13020900-0000-0000-0000-000000000001',
    @revision_scrap_id = @revision_anulacion_id OUTPUT,
    @operacion_nav_id = @operacion_anulacion_id OUTPUT;

IF NOT EXISTS
(
    SELECT 1
    FROM [log].revisiones_scrap
    WHERE revision_scrap_id = @revision_anulacion_id
      AND scrap_id = @scrap_principal_id
      AND numero_revision = 2
      AND cantidad = 0
      AND es_anulacion = 1
)
 OR NOT EXISTS
(
    SELECT 1
    FROM nav.operaciones
    WHERE operacion_nav_id = @operacion_anulacion_id
      AND tipo = N'ANULACION_CONSUMO'
      AND revision_scrap_id = @revision_anulacion_id
      AND TRY_CONVERT(int, JSON_VALUE(payload, '$.delta_consumo')) = -5
)
 OR (SELECT cantidad_scrap_acumulada FROM prod.ordenes
     WHERE orden_id = @orden_main_id) <> 1
    THROW 56223, 'V09 no anulo con revision 2 y delta -5.', 1;

/* V10: repeticion idempotente de la anulacion. */
SET @revision_repetida_id = -1;
SET @operacion_repetida_id = -1;

EXEC [log].revisar_scrap
    @scrap_id = @scrap_principal_id,
    @componente_orden_id = @componente_main_b_id,
    @motivo_scrap_id = @motivo_otros_id,
    @cantidad = 0,
    @descripcion = NULL,
    @es_anulacion = 1,
    @ajustado_por_supervisor_id = @supervisor_1_id,
    @motivo_ajuste = N'ZZTEST 013 anulacion funcional',
    @correlacion_id = '13020900-0000-0000-0000-000000000001',
    @revision_scrap_id = @revision_repetida_id OUTPUT,
    @operacion_nav_id = @operacion_repetida_id OUTPUT;

IF @revision_repetida_id <> @revision_anulacion_id
 OR @operacion_repetida_id <> @operacion_anulacion_id
 OR (SELECT COUNT(*) FROM [log].revisiones_scrap
     WHERE scrap_id = @scrap_principal_id) <> 2
 OR (SELECT cantidad_scrap_acumulada FROM prod.ordenes
     WHERE orden_id = @orden_main_id) <> 1
    THROW 56224, 'V10 duplico o altero la anulacion idempotente.', 1;

IF
(
    SELECT COUNT(*)
    FROM aud.eventos
    WHERE tipo_evento IN (N'SCRAP_CORREGIDO', N'SCRAP_ANULADO')
      AND orden_id IN (@orden_main_id, @orden_conc_id)
) <> 3
    THROW 56225, 'La auditoria no contiene las tres revisiones validas.', 1;

SELECT
    @scrap_principal_id scrap_principal_anulado_id,
    @revision_1_id revision_correccion_id,
    @revision_anulacion_id revision_anulacion_id,
    @scrap_conc_id scrap_concurrencia_id,
    @revision_conc_id revision_error_reintentable_id,
    (SELECT cantidad_scrap_acumulada
     FROM prod.ordenes WHERE orden_id = @orden_main_id) acumulado_main,
    (SELECT cantidad_scrap_acumulada
     FROM prod.ordenes WHERE orden_id = @orden_conc_id) acumulado_conc;

PRINT N'PRUEBAS 013-02 REVISIONES Y ANULACION CORRECTAS';

