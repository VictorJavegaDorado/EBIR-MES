/*
Pruebas 013 - cliente B y verificacion global de concurrencia.
Ejecutar en conexion independiente junto con 05_CONCURRENCIA_A.sql.
Sustituir la unica marca 2099 por el mismo instante UTC usado en 05.
Estado: preparado para revision estatica; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 56600, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

DECLARE
    @inicio_base datetime2(3) = '2099-01-01T00:00:00.000', -- REVISAR
    @inicio_revision datetime2(3),
    @inicio_doble_aceptacion datetime2(3),
    @inicio_aceptar_rechazar datetime2(3),
    @inicio_entregar_cancelar datetime2(3),
    @inicio_revision_solicitud datetime2(3);

SET @inicio_revision = @inicio_base;
SET @inicio_doble_aceptacion = DATEADD(SECOND, 4, @inicio_base);
SET @inicio_aceptar_rechazar = DATEADD(SECOND, 8, @inicio_base);
SET @inicio_entregar_cancelar = DATEADD(SECOND, 12, @inicio_base);
SET @inicio_revision_solicitud = DATEADD(SECOND, 16, @inicio_base);

IF @inicio_base <= DATEADD(SECOND, 2, SYSUTCDATETIME())
 OR @inicio_revision_solicitud > DATEADD(MINUTE, 2, SYSUTCDATETIME())
    THROW 56601, 'La marca debe ser futura y completar las carreras dentro de dos minutos UTC.', 1;

DECLARE
    @supervisor_2_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-SUP2'),
    @aprovisionador_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-APR1'),
    @aprovisionador_2_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-APR2'),
    @operario_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-OP1'),
    @orden_main_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-MAIN'),
    @orden_conc_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-CONC'),
    @sesion_main_id bigint,
    @scrap_conc_id bigint =
        (SELECT scrap_id FROM [log].scrap
         WHERE descripcion = N'ZZTEST 013 scrap para concurrencia'),
    @scrap_main_activo_id bigint =
        (SELECT scrap_id FROM [log].scrap
         WHERE descripcion = N'ZZTEST 013 motivo otros descrito'),
    @componente_conc_b_id bigint,
    @componente_main_b_id bigint,
    @motivo_componente_id smallint =
        (SELECT motivo_scrap_id FROM [log].motivos_scrap
         WHERE categoria = N'COMPONENTE' AND codigo = N'ROTO_PROCESO'),
    @solicitud_doble_aceptacion_id bigint =
        (SELECT entidad_id FROM aud.eventos
         WHERE correlacion_id = '13030400-0000-0000-0000-000000000003'
           AND tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO'),
    @solicitud_aceptar_rechazar_id bigint =
        (SELECT entidad_id FROM aud.eventos
         WHERE correlacion_id = '13030400-0000-0000-0000-000000000004'
           AND tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO'),
    @solicitud_entregar_cancelar_id bigint =
        (SELECT entidad_id FROM aud.eventos
         WHERE correlacion_id = '13041600-0000-0000-0000-000000000001'
           AND tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO');

SELECT @sesion_main_id = s.sesion_linea_id
FROM prod.sesiones_linea s
JOIN cfg.lineas l ON l.linea_id = s.linea_id
WHERE s.orden_id = @orden_main_id
  AND l.codigo = N'ZZ13-L01'
  AND s.finalizada_utc IS NULL;

SELECT @componente_conc_b_id = componente_orden_id
FROM nav.componentes_orden
WHERE orden_id = @orden_conc_id
  AND codigo_componente LIKE N'ZZ13-COMP-B-%';

SELECT @componente_main_b_id = componente_orden_id
FROM nav.componentes_orden
WHERE orden_id = @orden_main_id
  AND codigo_componente LIKE N'ZZ13-COMP-B-%';

IF @supervisor_2_id IS NULL OR @aprovisionador_1_id IS NULL
 OR @aprovisionador_2_id IS NULL OR @operario_1_id IS NULL
 OR @sesion_main_id IS NULL
 OR @scrap_conc_id IS NULL OR @scrap_main_activo_id IS NULL
 OR @componente_conc_b_id IS NULL OR @componente_main_b_id IS NULL
 OR @motivo_componente_id IS NULL
 OR @solicitud_doble_aceptacion_id IS NULL
 OR @solicitud_aceptar_rechazar_id IS NULL
 OR @solicitud_entregar_cancelar_id IS NULL
    THROW 56602, 'Falta el estado previo requerido para concurrencia.', 1;

DECLARE
    @error_revision int,
    @revision_id bigint,
    @operacion_id bigint,
    @error_doble_aceptacion int,
    @error_aceptar_rechazar int,
    @error_entregar_cancelar int,
    @error_solicitud_revision int,
    @solicitud_revision_id bigint,
    @tran int,
    @xstate int;

/* C1-B: segunda revision simultanea del mismo scrap. */
WHILE SYSUTCDATETIME() < @inicio_revision
    WAITFOR DELAY '00:00:00.050';

BEGIN TRY
    EXEC [log].revisar_scrap
        @scrap_id = @scrap_conc_id,
        @componente_orden_id = @componente_conc_b_id,
        @motivo_scrap_id = @motivo_componente_id,
        @cantidad = 8,
        @descripcion = N'ZZTEST 013 carrera revision cliente B',
        @es_anulacion = 0,
        @ajustado_por_supervisor_id = @supervisor_2_id,
        @motivo_ajuste = N'ZZTEST 013 concurrencia revision B',
        @correlacion_id = '13060100-0000-0000-0000-000000000001',
        @revision_scrap_id = @revision_id OUTPUT,
        @operacion_nav_id = @operacion_id OUTPUT;
END TRY
BEGIN CATCH
    SET @error_revision = ERROR_NUMBER();
END CATCH;

SET @tran = @@TRANCOUNT;
SET @xstate = XACT_STATE();

IF @error_revision IS NOT NULL
 OR @revision_id IS NULL OR @operacion_id IS NULL
 OR @tran <> 0 OR @xstate <> 0
    THROW 56603, 'C1-B no completo limpiamente la revision serializada.', 1;

/* C2-B: segundo aprovisionador intenta aceptar. */
WHILE SYSUTCDATETIME() < @inicio_doble_aceptacion
    WAITFOR DELAY '00:00:00.050';

BEGIN TRY
    EXEC [log].transicionar_solicitud_reaprovisionamiento
        @solicitud_id = @solicitud_doble_aceptacion_id,
        @estado_nuevo = N'ACEPTADA',
        @empleado_id = @aprovisionador_2_id,
        @comentario = N'ZZTEST 013 doble aceptacion cliente B',
        @correlacion_id = '13060200-0000-0000-0000-000000000001';
END TRY
BEGIN CATCH
    SET @error_doble_aceptacion = ERROR_NUMBER();
    IF @error_doble_aceptacion NOT IN (55310, 55311)
        THROW;
END CATCH;

SET @tran = @@TRANCOUNT;
SET @xstate = XACT_STATE();

IF @error_doble_aceptacion IS NOT NULL
   AND (@tran <> 0 OR @xstate <> 0)
    THROW 56604, 'C2-B dejo una transaccion abierta tras perder.', 1;

/* C3-B: rechazar frente a aceptar. */
WHILE SYSUTCDATETIME() < @inicio_aceptar_rechazar
    WAITFOR DELAY '00:00:00.050';

BEGIN TRY
    EXEC [log].transicionar_solicitud_reaprovisionamiento
        @solicitud_id = @solicitud_aceptar_rechazar_id,
        @estado_nuevo = N'RECHAZADA',
        @empleado_id = @aprovisionador_2_id,
        @comentario = N'ZZTEST 013 rechazar cliente B',
        @correlacion_id = '13060300-0000-0000-0000-000000000001';
END TRY
BEGIN CATCH
    SET @error_aceptar_rechazar = ERROR_NUMBER();
    IF @error_aceptar_rechazar NOT IN (55309, 55310)
        THROW;
END CATCH;

SET @tran = @@TRANCOUNT;
SET @xstate = XACT_STATE();

IF @error_aceptar_rechazar IS NOT NULL
   AND (@tran <> 0 OR @xstate <> 0)
    THROW 56605, 'C3-B dejo una transaccion abierta tras perder.', 1;

/* C4-B: cancelar frente a entregar, usando el aprovisionador asignado. */
WHILE SYSUTCDATETIME() < @inicio_entregar_cancelar
    WAITFOR DELAY '00:00:00.050';

BEGIN TRY
    EXEC [log].transicionar_solicitud_reaprovisionamiento
        @solicitud_id = @solicitud_entregar_cancelar_id,
        @estado_nuevo = N'CANCELADA',
        @empleado_id = @aprovisionador_1_id,
        @comentario = N'ZZTEST 013 cancelar cliente B',
        @correlacion_id = '13060400-0000-0000-0000-000000000001';
END TRY
BEGIN CATCH
    SET @error_entregar_cancelar = ERROR_NUMBER();
    IF @error_entregar_cancelar <> 55309
        THROW;
END CATCH;

SET @tran = @@TRANCOUNT;
SET @xstate = XACT_STATE();

IF @error_entregar_cancelar IS NOT NULL
   AND (@tran <> 0 OR @xstate <> 0)
    THROW 56606, 'C4-B dejo una transaccion abierta tras perder.', 1;

/* C5-B: solicitud vinculada frente a revision del mismo scrap. */
WHILE SYSUTCDATETIME() < @inicio_revision_solicitud
    WAITFOR DELAY '00:00:00.050';

BEGIN TRY
    EXEC [log].crear_solicitud_reaprovisionamiento
        @sesion_linea_id = @sesion_main_id,
        @componente_orden_id = @componente_main_b_id,
        @cantidad_solicitada = 1,
        @solicitada_por_empleado_id = @operario_1_id,
        @scrap_id = @scrap_main_activo_id,
        @correlacion_id = '13060500-0000-0000-0000-000000000001',
        @solicitud_id = @solicitud_revision_id OUTPUT;
END TRY
BEGIN CATCH
    SET @error_solicitud_revision = ERROR_NUMBER();
    IF @error_solicitud_revision <> 55216
        THROW;
END CATCH;

SET @tran = @@TRANCOUNT;
SET @xstate = XACT_STATE();

IF @error_solicitud_revision IS NOT NULL
   AND
   (
       @solicitud_revision_id IS NOT NULL
       OR @tran <> 0
       OR @xstate <> 0
   )
    THROW 56607, 'C5-B no rechazo limpiamente la solicitud perdedora.', 1;

/*
El cliente B puede liberar el bloqueo del scrap inmediatamente antes de que
el cliente A confirme su revision. Espera acotada a la marca de auditoria del
cliente A antes de evaluar el estado global.
*/
DECLARE @limite_verificacion datetime2(3) =
    DATEADD(SECOND, 10, SYSUTCDATETIME());

WHILE NOT EXISTS
(
    SELECT 1
    FROM aud.eventos
    WHERE correlacion_id = '13050500-0000-0000-0000-000000000001'
      AND tipo_evento = N'SCRAP_CORREGIDO'
)
AND SYSUTCDATETIME() < @limite_verificacion
    WAITFOR DELAY '00:00:00.050';

IF NOT EXISTS
(
    SELECT 1
    FROM aud.eventos
    WHERE correlacion_id = '13050500-0000-0000-0000-000000000001'
      AND tipo_evento = N'SCRAP_CORREGIDO'
)
    THROW 56616, 'C5 no alcanzo la barrera final del cliente A.', 1;

/* Verificacion global despues de las cinco marcas. */
IF
(
    SELECT COUNT(*)
    FROM [log].revisiones_scrap
    WHERE scrap_id = @scrap_conc_id
) <> 3
 OR
 (
     SELECT COUNT(DISTINCT numero_revision)
     FROM [log].revisiones_scrap
     WHERE scrap_id = @scrap_conc_id
 ) <> 3
 OR
 (
     SELECT COUNT(*)
     FROM aud.eventos
     WHERE correlacion_id IN
           (
               '13050100-0000-0000-0000-000000000001',
               '13060100-0000-0000-0000-000000000001'
           )
       AND tipo_evento = N'SCRAP_CORREGIDO'
 ) <> 2
    THROW 56608, 'C1 no serializo dos revisiones unicas.', 1;

DECLARE @cantidad_efectiva_conc int =
(
    SELECT TOP (1) cantidad
    FROM [log].revisiones_scrap
    WHERE scrap_id = @scrap_conc_id
    ORDER BY numero_revision DESC
);

IF @cantidad_efectiva_conc NOT IN (7, 8)
 OR (SELECT cantidad_scrap_acumulada FROM prod.ordenes
     WHERE orden_id = @orden_conc_id) <> @cantidad_efectiva_conc
    THROW 56609, 'C1 perdio el ultimo valor efectivo o su acumulado.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM [log].solicitudes_reaprovisionamiento
    WHERE solicitud_id = @solicitud_doble_aceptacion_id
      AND estado = N'ACEPTADA'
      AND asignada_a_empleado_id IN (@aprovisionador_1_id, @aprovisionador_2_id)
)
 OR
 (
     SELECT COUNT(*)
     FROM [log].historial_solicitudes
     WHERE solicitud_id = @solicitud_doble_aceptacion_id
       AND estado_nuevo = N'ACEPTADA'
 ) <> 1
    THROW 56610, 'C2 no termino con una aceptacion unica.', 1;

IF (SELECT estado FROM [log].solicitudes_reaprovisionamiento
    WHERE solicitud_id = @solicitud_aceptar_rechazar_id)
   NOT IN (N'ACEPTADA', N'RECHAZADA')
 OR
 (
     SELECT COUNT(*)
     FROM [log].historial_solicitudes
     WHERE solicitud_id = @solicitud_aceptar_rechazar_id
       AND estado_nuevo IN (N'ACEPTADA', N'RECHAZADA')
 ) <> 1
    THROW 56611, 'C3 no termino con una decision unica.', 1;

IF (SELECT estado FROM [log].solicitudes_reaprovisionamiento
    WHERE solicitud_id = @solicitud_entregar_cancelar_id)
   NOT IN (N'ENTREGADA', N'CANCELADA')
 OR
 (
     SELECT COUNT(*)
     FROM [log].historial_solicitudes
     WHERE solicitud_id = @solicitud_entregar_cancelar_id
       AND estado_nuevo IN (N'ENTREGADA', N'CANCELADA')
 ) <> 1
    THROW 56612, 'C4 no termino con un estado terminal unico.', 1;

IF
(
    SELECT COUNT(*)
    FROM [log].revisiones_scrap
    WHERE scrap_id = @scrap_main_activo_id
) <> 1
 OR (SELECT cantidad_scrap_acumulada FROM prod.ordenes
     WHERE orden_id = @orden_main_id) <> 2
    THROW 56613, 'C5 no aplico una unica revision efectiva.', 1;

IF @error_solicitud_revision IS NULL
BEGIN
    IF @solicitud_revision_id IS NULL
       OR NOT EXISTS
       (
           SELECT 1
           FROM [log].solicitudes_reaprovisionamiento
           WHERE solicitud_id = @solicitud_revision_id
             AND scrap_id = @scrap_main_activo_id
             AND componente_orden_id = @componente_main_b_id
             AND estado = N'PENDIENTE'
       )
        THROW 56614, 'C5-B gano sin persistir la solicitud historica.', 1;
END;
ELSE IF EXISTS
(
    SELECT 1
    FROM aud.eventos
    WHERE correlacion_id = '13060500-0000-0000-0000-000000000001'
)
    THROW 56615, 'C5-B perdio pero dejo auditoria parcial.', 1;

SELECT
    N'B' cliente,
    @cantidad_efectiva_conc cantidad_efectiva_conc,
    (SELECT codigo_nav FROM seg.empleados
     WHERE empleado_id =
       (SELECT asignada_a_empleado_id
        FROM [log].solicitudes_reaprovisionamiento
        WHERE solicitud_id = @solicitud_doble_aceptacion_id))
        ganador_doble_aceptacion,
    (SELECT estado FROM [log].solicitudes_reaprovisionamiento
     WHERE solicitud_id = @solicitud_aceptar_rechazar_id)
        resultado_aceptar_rechazar,
    (SELECT estado FROM [log].solicitudes_reaprovisionamiento
     WHERE solicitud_id = @solicitud_entregar_cancelar_id)
        resultado_entregar_cancelar,
    CASE WHEN @error_solicitud_revision IS NULL
         THEN N'SOLICITUD_ANTES_DE_REVISION'
         ELSE N'REVISION_ANTES_DE_SOLICITUD'
    END resultado_revision_solicitud;

PRINT N'CLIENTE B Y CONCURRENCIA 013 COMPLETADO';
