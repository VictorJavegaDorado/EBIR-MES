/*
Pruebas funcionales 013 — transiciones de reaprovisionamiento.
Requiere 00, 01, 02 y 03 ejecutados en orden.
Estado: preparado para revision estatica; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 56400, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'log.transicionar_solicitud_reaprovisionamiento', N'P') IS NULL
 OR OBJECT_ID(N'log.crear_solicitud_reaprovisionamiento', N'P') IS NULL
    THROW 56401, 'Los procedimientos de reaprovisionamiento no estan instalados.', 1;

DECLARE
    @aprovisionador_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-APR1'),
    @aprovisionador_2_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-APR2'),
    @supervisor_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-SUP1'),
    @orden_conc_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-CONC'),
    @sesion_conc_a_id bigint,
    @componente_conc_b_id bigint;

SELECT @sesion_conc_a_id = s.sesion_linea_id
FROM prod.sesiones_linea s
JOIN cfg.lineas l ON l.linea_id = s.linea_id
WHERE s.orden_id = @orden_conc_id
  AND l.codigo = N'ZZ13-L03'
  AND s.finalizada_utc IS NULL;

SELECT @componente_conc_b_id = componente_orden_id
FROM nav.componentes_orden
WHERE orden_id = @orden_conc_id
  AND codigo_componente LIKE N'ZZ13-COMP-B-%';

DECLARE
    @solicitud_ciclo_id bigint =
        (SELECT entidad_id FROM aud.eventos
         WHERE correlacion_id = '13030100-0000-0000-0000-000000000001'
           AND tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO'),
    @solicitud_rechazo_id bigint =
        (SELECT entidad_id FROM aud.eventos
         WHERE correlacion_id = '13030200-0000-0000-0000-000000000001'
           AND tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO'),
    @solicitud_cancelar_pendiente_id bigint =
        (SELECT entidad_id FROM aud.eventos
         WHERE correlacion_id = '13030300-0000-0000-0000-000000000001'
           AND tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO'),
    @solicitud_cancelar_aceptada_id bigint =
        (SELECT entidad_id FROM aud.eventos
         WHERE correlacion_id = '13030400-0000-0000-0000-000000000001'
           AND tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO'),
    @solicitud_cancelar_camino_id bigint =
        (SELECT entidad_id FROM aud.eventos
         WHERE correlacion_id = '13030400-0000-0000-0000-000000000002'
           AND tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO'),
    @solicitud_carrera_aceptar_id bigint =
        (SELECT entidad_id FROM aud.eventos
         WHERE correlacion_id = '13030400-0000-0000-0000-000000000003'
           AND tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO'),
    @solicitud_carrera_decidir_id bigint =
        (SELECT entidad_id FROM aud.eventos
         WHERE correlacion_id = '13030400-0000-0000-0000-000000000004'
           AND tipo_evento = N'REAPROVISIONAMIENTO_SOLICITADO');

IF @aprovisionador_1_id IS NULL OR @aprovisionador_2_id IS NULL
 OR @supervisor_1_id IS NULL OR @orden_conc_id IS NULL
 OR @sesion_conc_a_id IS NULL OR @componente_conc_b_id IS NULL
 OR @solicitud_ciclo_id IS NULL OR @solicitud_rechazo_id IS NULL
 OR @solicitud_cancelar_pendiente_id IS NULL
 OR @solicitud_cancelar_aceptada_id IS NULL
 OR @solicitud_cancelar_camino_id IS NULL
 OR @solicitud_carrera_aceptar_id IS NULL
 OR @solicitud_carrera_decidir_id IS NULL
    THROW 56402, 'No existe el estado acumulativo requerido de 03.', 1;

IF (SELECT COUNT(*) FROM [log].solicitudes_reaprovisionamiento) <> 7
 OR EXISTS
 (
     SELECT 1
     FROM [log].solicitudes_reaprovisionamiento
     WHERE estado <> N'PENDIENTE'
        OR asignada_a_empleado_id IS NOT NULL
 )
 OR (SELECT COUNT(*) FROM [log].historial_solicitudes) <> 7
    THROW 56403, 'Las siete solicitudes no parten de PENDIENTE.', 1;

/* T01: PENDIENTE -> ACEPTADA. */
EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_ciclo_id,
    @estado_nuevo = N'aceptada',
    @empleado_id = @aprovisionador_1_id,
    @comentario = N'ZZTEST 013 aceptacion ciclo',
    @correlacion_id = '13040100-0000-0000-0000-000000000001';

IF NOT EXISTS
(
    SELECT 1
    FROM [log].solicitudes_reaprovisionamiento
    WHERE solicitud_id = @solicitud_ciclo_id
      AND estado = N'ACEPTADA'
      AND asignada_a_empleado_id = @aprovisionador_1_id
      AND aceptada_utc IS NOT NULL
)
    THROW 56404, 'T01 no asigno y acepto la solicitud.', 1;

/* T02: repeticion idempotente exacta de la aceptacion. */
DECLARE
    @historial_antes int =
        (SELECT COUNT(*) FROM [log].historial_solicitudes
         WHERE solicitud_id = @solicitud_ciclo_id),
    @auditoria_antes int =
        (SELECT COUNT(*) FROM aud.eventos
         WHERE correlacion_id = '13040100-0000-0000-0000-000000000001');

EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_ciclo_id,
    @estado_nuevo = N'ACEPTADA',
    @empleado_id = @aprovisionador_1_id,
    @comentario = N'ZZTEST 013 aceptacion ciclo',
    @correlacion_id = '13040100-0000-0000-0000-000000000001';

IF (SELECT COUNT(*) FROM [log].historial_solicitudes
    WHERE solicitud_id = @solicitud_ciclo_id) <> @historial_antes
 OR (SELECT COUNT(*) FROM aud.eventos
     WHERE correlacion_id = '13040100-0000-0000-0000-000000000001') <> @auditoria_antes
    THROW 56405, 'T02 duplico historial o auditoria.', 1;

/* T03: un segundo aprovisionador no puede continuar la asignada. */
DECLARE
    @error int,
    @tran int,
    @xstate int;

BEGIN TRY
    EXEC [log].transicionar_solicitud_reaprovisionamiento
        @solicitud_id = @solicitud_ciclo_id,
        @estado_nuevo = N'EN_CAMINO',
        @empleado_id = @aprovisionador_2_id,
        @comentario = N'ZZTEST 013 segundo aprovisionador',
        @correlacion_id = '13040300-0000-0000-0000-000000000001';

    THROW 56406, 'T03 debio rechazar al segundo aprovisionador.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55310 OR @tran <> 0 OR @xstate <> 0
    THROW 56407, 'T03 no devolvio 55310 con estado limpio.', 1;

/* T04-T05: ACEPTADA -> EN_CAMINO -> ENTREGADA. */
EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_ciclo_id,
    @estado_nuevo = N'EN_CAMINO',
    @empleado_id = @aprovisionador_1_id,
    @comentario = N'ZZTEST 013 material en camino',
    @correlacion_id = '13040400-0000-0000-0000-000000000001';

EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_ciclo_id,
    @estado_nuevo = N'ENTREGADA',
    @empleado_id = @aprovisionador_1_id,
    @comentario = N'ZZTEST 013 material entregado',
    @correlacion_id = '13040500-0000-0000-0000-000000000001';

IF NOT EXISTS
(
    SELECT 1
    FROM [log].solicitudes_reaprovisionamiento
    WHERE solicitud_id = @solicitud_ciclo_id
      AND estado = N'ENTREGADA'
      AND asignada_a_empleado_id = @aprovisionador_1_id
      AND aceptada_utc IS NOT NULL
      AND en_camino_utc IS NOT NULL
      AND entregada_utc IS NOT NULL
      AND aceptada_utc <= en_camino_utc
      AND en_camino_utc <= entregada_utc
)
 OR (SELECT COUNT(*) FROM [log].historial_solicitudes
     WHERE solicitud_id = @solicitud_ciclo_id) <> 4
    THROW 56408, 'T04-T05 no completaron el ciclo y su historial.', 1;

/* T06: estado terminal no admite otra transicion. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].transicionar_solicitud_reaprovisionamiento
        @solicitud_id = @solicitud_ciclo_id,
        @estado_nuevo = N'CANCELADA',
        @empleado_id = @aprovisionador_1_id,
        @comentario = N'ZZTEST 013 intento tras entrega',
        @correlacion_id = '13040600-0000-0000-0000-000000000001';

    THROW 56409, 'T06 debio rechazar el estado terminal.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55309 OR @tran <> 0 OR @xstate <> 0
    THROW 56410, 'T06 no devolvio 55309 con estado limpio.', 1;

/* T07: salto PENDIENTE -> ENTREGADA no permitido. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].transicionar_solicitud_reaprovisionamiento
        @solicitud_id = @solicitud_carrera_aceptar_id,
        @estado_nuevo = N'ENTREGADA',
        @empleado_id = @aprovisionador_1_id,
        @comentario = N'ZZTEST 013 salto invalido',
        @correlacion_id = '13040700-0000-0000-0000-000000000001';

    THROW 56411, 'T07 debio rechazar el salto.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55311 OR @tran <> 0 OR @xstate <> 0
    THROW 56412, 'T07 no devolvio 55311 con estado limpio.', 1;

/* T08: rechazo sin motivo. */
BEGIN TRY
    SET @error = NULL;

    EXEC [log].transicionar_solicitud_reaprovisionamiento
        @solicitud_id = @solicitud_rechazo_id,
        @estado_nuevo = N'RECHAZADA',
        @empleado_id = @aprovisionador_1_id,
        @comentario = N'   ',
        @correlacion_id = '13040800-0000-0000-0000-000000000001';

    THROW 56413, 'T08 debio exigir motivo.', 1;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    SET @tran = @@TRANCOUNT;
    SET @xstate = XACT_STATE();
END CATCH;

IF @error <> 55303 OR @tran <> 0 OR @xstate <> 0
    THROW 56414, 'T08 no devolvio 55303 con estado limpio.', 1;

/* T09: rechazo valido desde PENDIENTE. */
EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_rechazo_id,
    @estado_nuevo = N'RECHAZADA',
    @empleado_id = @aprovisionador_1_id,
    @comentario = N'ZZTEST 013 material no disponible',
    @correlacion_id = '13040900-0000-0000-0000-000000000001';

IF NOT EXISTS
(
    SELECT 1
    FROM [log].solicitudes_reaprovisionamiento
    WHERE solicitud_id = @solicitud_rechazo_id
      AND estado = N'RECHAZADA'
      AND rechazada_utc IS NOT NULL
      AND motivo_rechazo = N'ZZTEST 013 material no disponible'
)
    THROW 56415, 'T09 no persistio rechazo y motivo.', 1;

/* T10: cancelacion desde PENDIENTE. */
EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_cancelar_pendiente_id,
    @estado_nuevo = N'CANCELADA',
    @empleado_id = @aprovisionador_2_id,
    @comentario = N'ZZTEST 013 necesidad retirada',
    @correlacion_id = '13041000-0000-0000-0000-000000000001';

/* T11-T12: cancelacion desde ACEPTADA. */
EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_cancelar_aceptada_id,
    @estado_nuevo = N'ACEPTADA',
    @empleado_id = @aprovisionador_1_id,
    @comentario = N'ZZTEST 013 aceptada para cancelar',
    @correlacion_id = '13041100-0000-0000-0000-000000000001';

EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_cancelar_aceptada_id,
    @estado_nuevo = N'CANCELADA',
    @empleado_id = @aprovisionador_1_id,
    @comentario = N'ZZTEST 013 cancelada tras aceptar',
    @correlacion_id = '13041200-0000-0000-0000-000000000001';

/* T13-T15: cancelacion desde EN_CAMINO. */
EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_cancelar_camino_id,
    @estado_nuevo = N'ACEPTADA',
    @empleado_id = @aprovisionador_2_id,
    @comentario = N'ZZTEST 013 aceptada camino',
    @correlacion_id = '13041300-0000-0000-0000-000000000001';

EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_cancelar_camino_id,
    @estado_nuevo = N'EN_CAMINO',
    @empleado_id = @aprovisionador_2_id,
    @comentario = N'ZZTEST 013 en camino para cancelar',
    @correlacion_id = '13041400-0000-0000-0000-000000000001';

EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_cancelar_camino_id,
    @estado_nuevo = N'CANCELADA',
    @empleado_id = @aprovisionador_2_id,
    @comentario = N'ZZTEST 013 cancelada en camino',
    @correlacion_id = '13041500-0000-0000-0000-000000000001';

IF
(
    SELECT COUNT(*)
    FROM [log].solicitudes_reaprovisionamiento
    WHERE solicitud_id IN
          (
              @solicitud_cancelar_pendiente_id,
              @solicitud_cancelar_aceptada_id,
              @solicitud_cancelar_camino_id
          )
      AND estado = N'CANCELADA'
      AND cancelada_utc IS NOT NULL
      AND motivo_cancelacion IS NOT NULL
) <> 3
    THROW 56416, 'T10-T15 no cubrieron las tres cancelaciones.', 1;

/* T16-T18: solicitud preparada en EN_CAMINO para carrera entrega/cancelacion. */
DECLARE @solicitud_carrera_final_id bigint;

EXEC [log].crear_solicitud_reaprovisionamiento
    @sesion_linea_id = @sesion_conc_a_id,
    @componente_orden_id = @componente_conc_b_id,
    @cantidad_solicitada = 5,
    @solicitada_por_empleado_id = @supervisor_1_id,
    @scrap_id = NULL,
    @correlacion_id = '13041600-0000-0000-0000-000000000001',
    @solicitud_id = @solicitud_carrera_final_id OUTPUT;

EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_carrera_final_id,
    @estado_nuevo = N'ACEPTADA',
    @empleado_id = @aprovisionador_1_id,
    @comentario = N'ZZTEST 013 preparar carrera final',
    @correlacion_id = '13041700-0000-0000-0000-000000000001';

EXEC [log].transicionar_solicitud_reaprovisionamiento
    @solicitud_id = @solicitud_carrera_final_id,
    @estado_nuevo = N'EN_CAMINO',
    @empleado_id = @aprovisionador_1_id,
    @comentario = N'ZZTEST 013 carrera final en camino',
    @correlacion_id = '13041800-0000-0000-0000-000000000001';

IF NOT EXISTS
(
    SELECT 1
    FROM [log].solicitudes_reaprovisionamiento
    WHERE solicitud_id = @solicitud_carrera_final_id
      AND estado = N'EN_CAMINO'
      AND asignada_a_empleado_id = @aprovisionador_1_id
)
    THROW 56417, 'T16-T18 no prepararon EN_CAMINO.', 1;

/* T19: formula visual de prioridad, independiente de la hora real. */
DECLARE @prioridades TABLE
(
    minutos int NOT NULL,
    esperado nvarchar(10) NOT NULL
);

INSERT @prioridades (minutos, esperado)
VALUES (0, N'VERDE'), (9, N'VERDE'),
       (10, N'AMARILLO'), (19, N'AMARILLO'),
       (20, N'ROJO'), (120, N'ROJO');

IF EXISTS
(
    SELECT 1
    FROM @prioridades
    WHERE
        CASE
            WHEN minutos < 10 THEN N'VERDE'
            WHEN minutos < 20 THEN N'AMARILLO'
            ELSE N'ROJO'
        END <> esperado
)
    THROW 56418, 'T19 no cumple los umbrales visuales 10/20.', 1;

IF (SELECT COUNT(*) FROM [log].solicitudes_reaprovisionamiento) <> 8
 OR (SELECT COUNT(*) FROM [log].historial_solicitudes) <> 20
 OR
 (
     SELECT COUNT(*)
     FROM [log].solicitudes_reaprovisionamiento
     WHERE estado = N'PENDIENTE'
       AND solicitud_id IN
           (@solicitud_carrera_aceptar_id, @solicitud_carrera_decidir_id)
 ) <> 2
    THROW 56419, 'La cardinalidad final o preparacion concurrente no es correcta.', 1;

IF
(
    SELECT COUNT(*)
    FROM aud.eventos
    WHERE tipo_evento IN
    (
        N'REAPROVISIONAMIENTO_ACEPTADO',
        N'REAPROVISIONAMIENTO_EN_CAMINO',
        N'REAPROVISIONAMIENTO_ENTREGADO',
        N'REAPROVISIONAMIENTO_RECHAZADO',
        N'REAPROVISIONAMIENTO_CANCELADO'
    )
) <> 12
    THROW 56420, 'La auditoria no contiene las doce transiciones validas.', 1;

SELECT
    @solicitud_ciclo_id solicitud_entregada_id,
    @solicitud_rechazo_id solicitud_rechazada_id,
    @solicitud_cancelar_pendiente_id cancelada_desde_pendiente_id,
    @solicitud_cancelar_aceptada_id cancelada_desde_aceptada_id,
    @solicitud_cancelar_camino_id cancelada_desde_camino_id,
    @solicitud_carrera_aceptar_id carrera_aceptar_id,
    @solicitud_carrera_decidir_id carrera_decidir_id,
    @solicitud_carrera_final_id carrera_final_id,
    (SELECT COUNT(*) FROM [log].historial_solicitudes) total_historial;

PRINT N'PRUEBAS 013-04 TRANSICIONES CORRECTAS';

