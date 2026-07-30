/*
Pruebas funcionales 013 — solicitudes de reaprovisionamiento.
Requiere 00, 01 y 02 ejecutados en orden.
Estado: preparado para revision estatica; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 56300, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'log.crear_solicitud_reaprovisionamiento', N'P') IS NULL
    THROW 56301, 'El procedimiento de solicitudes no esta instalado.', 1;

DECLARE
    @supervisor_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-SUP1'),
    @operario_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-OP1'),
    @sin_rol_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-SINROL'),
    @orden_main_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-MAIN'),
    @orden_conc_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-CONC'),
    @sesion_main_id bigint,
    @sesion_conc_a_id bigint;

SELECT @sesion_main_id = s.sesion_linea_id
FROM prod.sesiones_linea s
JOIN cfg.lineas l ON l.linea_id = s.linea_id
WHERE s.orden_id = @orden_main_id
  AND l.codigo = N'ZZ13-L01'
  AND s.finalizada_utc IS NULL;

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
    @componente_conc_b_id bigint =
        (SELECT componente_orden_id FROM nav.componentes_orden
         WHERE orden_id = @orden_conc_id AND codigo_componente LIKE N'ZZ13-COMP-B-%'),
    @scrap_anulado_id bigint =
        (SELECT scrap_id FROM [log].scrap
         WHERE orden_id = @orden_main_id
           AND descripcion = N'ZZTEST 013 alta por operario'),
    @scrap_activo_main_id bigint =
        (SELECT scrap_id FROM [log].scrap
         WHERE orden_id = @orden_main_id
           AND descripcion = N'ZZTEST 013 motivo otros descrito'),
    @scrap_activo_conc_id bigint =
        (SELECT scrap_id FROM [log].scrap
         WHERE orden_id = @orden_conc_id
           AND descripcion = N'ZZTEST 013 scrap para concurrencia');

IF @supervisor_1_id IS NULL OR @operario_1_id IS NULL OR @sin_rol_id IS NULL
 OR @orden_main_id IS NULL OR @orden_conc_id IS NULL
 OR @sesion_main_id IS NULL OR @sesion_conc_a_id IS NULL
 OR @componente_main_a_id IS NULL OR @componente_main_b_id IS NULL
 OR @componente_conc_b_id IS NULL
 OR @scrap_anulado_id IS NULL OR @scrap_activo_main_id IS NULL
 OR @scrap_activo_conc_id IS NULL
    THROW 56302, 'No existe el estado acumulativo requerido de 02.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM [log].revisiones_scrap
    WHERE scrap_id = @scrap_anulado_id
      AND numero_revision = 2
      AND es_anulacion = 1
)
 OR NOT EXISTS
(
    SELECT 1
    FROM [log].revisiones_scrap
    WHERE scrap_id = @scrap_activo_conc_id
      AND numero_revision = 1
      AND componente_orden_id = @componente_conc_b_id
      AND es_anulacion = 0
)
    THROW 56303, 'Los valores efectivos de scrap no son los esperados.', 1;

/* S01: solicitud vinculada a scrap activo. */
DECLARE @solicitud_vinculada_id bigint;

EXEC [log].crear_solicitud_reaprovisionamiento
    @sesion_linea_id = @sesion_main_id,
    @componente_orden_id = @componente_main_b_id,
    @cantidad_solicitada = 1,
    @solicitada_por_empleado_id = @operario_1_id,
    @scrap_id = @scrap_activo_main_id,
    @correlacion_id = '13030100-0000-0000-0000-000000000001',
    @solicitud_id = @solicitud_vinculada_id OUTPUT;

IF @solicitud_vinculada_id IS NULL
    THROW 56304, 'S01 no devolvio solicitud.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM [log].solicitudes_reaprovisionamiento
    WHERE solicitud_id = @solicitud_vinculada_id
      AND orden_id = @orden_main_id
      AND sesion_linea_id = @sesion_main_id
      AND scrap_id = @scrap_activo_main_id
      AND componente_orden_id = @componente_main_b_id
      AND cantidad_solicitada = 1
      AND estado = N'PENDIENTE'
      AND asignada_a_empleado_id IS NULL
)
 OR
 (
     SELECT COUNT(*)
     FROM [log].historial_solicitudes
     WHERE solicitud_id = @solicitud_vinculada_id
       AND estado_anterior IS NULL
       AND estado_nuevo = N'PENDIENTE'
       AND empleado_id = @operario_1_id
 ) <> 1
    THROW 56305, 'S01 no creo solicitud e historial inicial correctos.', 1;

/* S02: solicitud ordinaria sin scrap por supervisor. */
DECLARE @solicitud_ordinaria_1_id bigint;

EXEC [log].crear_solicitud_reaprovisionamiento
    @sesion_linea_id = @sesion_main_id,
    @componente_orden_id = @componente_main_a_id,
    @cantidad_solicitada = 5,
    @solicitada_por_empleado_id = @supervisor_1_id,
    @scrap_id = NULL,
    @correlacion_id = '13030200-0000-0000-0000-000000000001',
    @solicitud_id = @solicitud_ordinaria_1_id OUTPUT;

/* S03: segunda necesidad real del mismo componente. */
DECLARE @solicitud_ordinaria_2_id bigint;

EXEC [log].crear_solicitud_reaprovisionamiento
    @sesion_linea_id = @sesion_main_id,
    @componente_orden_id = @componente_main_a_id,
    @cantidad_solicitada = 3,
    @solicitada_por_empleado_id = @operario_1_id,
    @scrap_id = NULL,
    @correlacion_id = '13030300-0000-0000-0000-000000000001',
    @solicitud_id = @solicitud_ordinaria_2_id OUTPUT;

IF @solicitud_ordinaria_1_id IS NULL OR @solicitud_ordinaria_2_id IS NULL
 OR @solicitud_ordinaria_1_id = @solicitud_ordinaria_2_id
 OR
 (
     SELECT COUNT(*)
     FROM [log].solicitudes_reaprovisionamiento
     WHERE sesion_linea_id = @sesion_main_id
       AND componente_orden_id = @componente_main_a_id
       AND scrap_id IS NULL
       AND estado = N'PENDIENTE'
 ) <> 2
    THROW 56306, 'S02-S03 no admitieron dos necesidades ordinarias reales.', 1;

/* S04-S07: solicitudes para transiciones y concurrencia posteriores. */
DECLARE
    @solicitud_conc_vinculada_id bigint,
    @solicitud_conc_2_id bigint,
    @solicitud_conc_3_id bigint,
    @solicitud_conc_4_id bigint;

EXEC [log].crear_solicitud_reaprovisionamiento
    @sesion_linea_id = @sesion_conc_a_id,
    @componente_orden_id = @componente_conc_b_id,
    @cantidad_solicitada = 6,
    @solicitada_por_empleado_id = @operario_1_id,
    @scrap_id = @scrap_activo_conc_id,
    @correlacion_id = '13030400-0000-0000-0000-000000000001',
    @solicitud_id = @solicitud_conc_vinculada_id OUTPUT;

EXEC [log].crear_solicitud_reaprovisionamiento
    @sesion_linea_id = @sesion_conc_a_id,
    @componente_orden_id = @componente_conc_b_id,
    @cantidad_solicitada = 2,
    @solicitada_por_empleado_id = @supervisor_1_id,
    @scrap_id = NULL,
    @correlacion_id = '13030400-0000-0000-0000-000000000002',
    @solicitud_id = @solicitud_conc_2_id OUTPUT;

EXEC [log].crear_solicitud_reaprovisionamiento
    @sesion_linea_id = @sesion_conc_a_id,
    @componente_orden_id = @componente_conc_b_id,
    @cantidad_solicitada = 3,
    @solicitada_por_empleado_id = @supervisor_1_id,
    @scrap_id = NULL,
    @correlacion_id = '13030400-0000-0000-0000-000000000003',
    @solicitud_id = @solicitud_conc_3_id OUTPUT;

EXEC [log].crear_solicitud_reaprovisionamiento
    @sesion_linea_id = @sesion_conc_a_id,
    @componente_orden_id = @componente_conc_b_id,
    @cantidad_solicitada = 4,
    @solicitada_por_empleado_id = @supervisor_1_id,
    @scrap_id = NULL,
    @correlacion_id = '13030400-0000-0000-0000-000000000004',
    @solicitud_id = @solicitud_conc_4_id OUTPUT;

IF @solicitud_conc_vinculada_id IS NULL
 OR @solicitud_conc_2_id IS NULL
 OR @solicitud_conc_3_id IS NULL
 OR @solicitud_conc_4_id IS NULL
    THROW 56307, 'S04-S07 no crearon las solicitudes auxiliares.', 1;

/* S08: repeticion idempotente exacta de S01. */
DECLARE
    @solicitud_repetida_id bigint = -1,
    @solicitudes_antes int =
        (SELECT COUNT(*) FROM [log].solicitudes_reaprovisionamiento),
    @historial_antes int =
        (SELECT COUNT(*) FROM [log].historial_solicitudes
         WHERE solicitud_id = @solicitud_vinculada_id),
    @auditoria_antes int =
        (SELECT COUNT(*) FROM aud.eventos
         WHERE correlacion_id = '13030100-0000-0000-0000-000000000001');

EXEC [log].crear_solicitud_reaprovisionamiento
    @sesion_linea_id = @sesion_main_id,
    @componente_orden_id = @componente_main_b_id,
    @cantidad_solicitada = 1,
    @solicitada_por_empleado_id = @operario_1_id,
    @scrap_id = @scrap_activo_main_id,
    @correlacion_id = '13030100-0000-0000-0000-000000000001',
    @solicitud_id = @solicitud_repetida_id OUTPUT;

IF @solicitud_repetida_id <> @solicitud_vinculada_id
 OR (SELECT COUNT(*) FROM [log].solicitudes_reaprovisionamiento) <> @solicitudes_antes
 OR (SELECT COUNT(*) FROM [log].historial_solicitudes
     WHERE solicitud_id = @solicitud_vinculada_id) <> @historial_antes
 OR (SELECT COUNT(*) FROM aud.eventos
     WHERE correlacion_id = '13030100-0000-0000-0000-000000000001') <> @auditoria_antes
    THROW 56308, 'S08 no fue idempotente.', 1;

/* S09: correlacion repetida con parametros diferentes. */
DECLARE
    @error int,
    @tran int,
    @xstate int,
    @salida_solicitud bigint;

BEGIN TRY
    EXEC [log].crear_solicitud_reaprovisionamiento
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_b_id,
        @cantidad_solicitada = 2,
        @solicitada_por_empleado_id = @operario_1_id,
        @scrap_id = @scrap_activo_main_id,
        @correlacion_id = '13030100-0000-0000-0000-000000000001',
        @solicitud_id = @salida_solicitud OUTPUT;

    THROW 56309, 'S09 debio rechazar parametros diferentes.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55207 OR @tran <> 0 OR @xstate <> 0
    THROW 56310, 'S09 no devolvio 55207 con estado limpio.', 1;

/* S10: scrap anulado. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].crear_solicitud_reaprovisionamiento
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_b_id,
        @cantidad_solicitada = 1,
        @solicitada_por_empleado_id = @operario_1_id,
        @scrap_id = @scrap_anulado_id,
        @correlacion_id = '13031000-0000-0000-0000-000000000001',
        @solicitud_id = @salida_solicitud OUTPUT;

    THROW 56311, 'S10 debio rechazar el scrap anulado.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55215 OR @tran <> 0 OR @xstate <> 0
    THROW 56312, 'S10 no devolvio 55215 con estado limpio.', 1;

/* S11: componente diferente al efectivo del scrap. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].crear_solicitud_reaprovisionamiento
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_a_id,
        @cantidad_solicitada = 1,
        @solicitada_por_empleado_id = @operario_1_id,
        @scrap_id = @scrap_activo_main_id,
        @correlacion_id = '13031100-0000-0000-0000-000000000001',
        @solicitud_id = @salida_solicitud OUTPUT;

    THROW 56313, 'S11 debio rechazar el componente diferente.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55216 OR @tran <> 0 OR @xstate <> 0
    THROW 56314, 'S11 no devolvio 55216 con estado limpio.', 1;

/* S12: scrap de otra orden, sesion y linea. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].crear_solicitud_reaprovisionamiento
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_b_id,
        @cantidad_solicitada = 1,
        @solicitada_por_empleado_id = @operario_1_id,
        @scrap_id = @scrap_activo_conc_id,
        @correlacion_id = '13031200-0000-0000-0000-000000000001',
        @solicitud_id = @salida_solicitud OUTPUT;

    THROW 56315, 'S12 debio rechazar el contexto del scrap.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55214 OR @tran <> 0 OR @xstate <> 0
    THROW 56316, 'S12 no devolvio 55214 con estado limpio.', 1;

/* S13: cantidad no positiva. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].crear_solicitud_reaprovisionamiento
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_a_id,
        @cantidad_solicitada = 0,
        @solicitada_por_empleado_id = @operario_1_id,
        @scrap_id = NULL,
        @correlacion_id = '13031300-0000-0000-0000-000000000001',
        @solicitud_id = @salida_solicitud OUTPUT;

    THROW 56317, 'S13 debio rechazar cantidad cero.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55202 OR @tran <> 0 OR @xstate <> 0
    THROW 56318, 'S13 no devolvio 55202 con estado limpio.', 1;

/* S14: solicitante sin rol funcional. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].crear_solicitud_reaprovisionamiento
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_a_id,
        @cantidad_solicitada = 1,
        @solicitada_por_empleado_id = @sin_rol_id,
        @scrap_id = NULL,
        @correlacion_id = '13031400-0000-0000-0000-000000000001',
        @solicitud_id = @salida_solicitud OUTPUT;

    THROW 56319, 'S14 debio rechazar al empleado sin rol.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55211 OR @tran <> 0 OR @xstate <> 0
    THROW 56320, 'S14 no devolvio 55211 con estado limpio.', 1;

IF (SELECT COUNT(*) FROM [log].solicitudes_reaprovisionamiento) <> 7
 OR (SELECT COUNT(*) FROM [log].historial_solicitudes) <> 7
 OR
 (
     SELECT COUNT(*)
     FROM [log].solicitudes_reaprovisionamiento
     WHERE estado = N'PENDIENTE'
       AND asignada_a_empleado_id IS NULL
 ) <> 7
    THROW 56321, 'Los rechazos dejaron efectos parciales o cardinalidad incorrecta.', 1;

IF
(
    SELECT COUNT(*)
    FROM aud.eventos
    WHERE tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO'
      AND entidad = N'log.solicitudes_reaprovisionamiento'
) <> 7
    THROW 56322, 'La auditoria no contiene las siete solicitudes validas.', 1;

SELECT
    @solicitud_vinculada_id solicitud_vinculada_main_id,
    @solicitud_ordinaria_1_id solicitud_ordinaria_1_id,
    @solicitud_ordinaria_2_id solicitud_ordinaria_2_id,
    @solicitud_conc_vinculada_id solicitud_conc_vinculada_id,
    @solicitud_conc_2_id solicitud_conc_2_id,
    @solicitud_conc_3_id solicitud_conc_3_id,
    @solicitud_conc_4_id solicitud_conc_4_id,
    (SELECT COUNT(*) FROM [log].solicitudes_reaprovisionamiento) total_solicitudes,
    (SELECT COUNT(*) FROM [log].historial_solicitudes) total_historial;

PRINT N'PRUEBAS 013-03 SOLICITUDES CORRECTAS';

