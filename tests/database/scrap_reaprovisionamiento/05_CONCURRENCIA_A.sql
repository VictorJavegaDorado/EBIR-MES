/*
Pruebas 013 - cliente A de concurrencia.
Ejecutar en conexion independiente junto con 06_CONCURRENCIA_B.sql.
Sustituir la unica marca 2099 por un instante UTC comun, entre 10 y
60 segundos en el futuro. Las cinco carreras se separan desde esa base.
Estado: preparado para revision estatica; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 56500, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

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
    THROW 56501, 'La marca debe ser futura y completar las carreras dentro de dos minutos UTC.', 1;

DECLARE
    @supervisor_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-SUP1'),
    @aprovisionador_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-APR1'),
    @orden_main_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-MAIN'),
    @orden_conc_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ13-FL-CONC'),
    @scrap_conc_id bigint =
        (SELECT scrap_id FROM [log].scrap
         WHERE descripcion = N'ZZTEST 013 scrap para concurrencia'),
    @scrap_main_activo_id bigint =
        (SELECT scrap_id FROM [log].scrap
         WHERE descripcion = N'ZZTEST 013 motivo otros descrito'),
    @componente_conc_b_id bigint,
    @componente_main_a_id bigint,
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

SELECT @componente_conc_b_id = componente_orden_id
FROM nav.componentes_orden
WHERE orden_id = @orden_conc_id
  AND codigo_componente LIKE N'ZZ13-COMP-B-%';

SELECT @componente_main_a_id = componente_orden_id
FROM nav.componentes_orden
WHERE orden_id = @orden_main_id
  AND codigo_componente LIKE N'ZZ13-COMP-A-%';

IF @supervisor_1_id IS NULL OR @aprovisionador_1_id IS NULL
 OR @scrap_conc_id IS NULL OR @scrap_main_activo_id IS NULL
 OR @componente_conc_b_id IS NULL OR @componente_main_a_id IS NULL
 OR @motivo_componente_id IS NULL
 OR @solicitud_doble_aceptacion_id IS NULL
 OR @solicitud_aceptar_rechazar_id IS NULL
 OR @solicitud_entregar_cancelar_id IS NULL
    THROW 56502, 'Falta el estado previo requerido para concurrencia.', 1;

IF
(
    (SELECT estado FROM [log].solicitudes_reaprovisionamiento
     WHERE solicitud_id = @solicitud_doble_aceptacion_id) <> N'PENDIENTE'
    AND NOT EXISTS
    (
        SELECT 1 FROM aud.eventos
        WHERE correlacion_id IN
              ('13050200-0000-0000-0000-000000000001',
               '13060200-0000-0000-0000-000000000001')
    )
)
 OR
(
    (SELECT estado FROM [log].solicitudes_reaprovisionamiento
     WHERE solicitud_id = @solicitud_aceptar_rechazar_id) <> N'PENDIENTE'
    AND NOT EXISTS
    (
        SELECT 1 FROM aud.eventos
        WHERE correlacion_id IN
              ('13050300-0000-0000-0000-000000000001',
               '13060300-0000-0000-0000-000000000001')
    )
)
 OR
(
    (SELECT estado FROM [log].solicitudes_reaprovisionamiento
     WHERE solicitud_id = @solicitud_entregar_cancelar_id) <> N'EN_CAMINO'
    AND NOT EXISTS
    (
        SELECT 1 FROM aud.eventos
        WHERE correlacion_id IN
              ('13050400-0000-0000-0000-000000000001',
               '13060400-0000-0000-0000-000000000001')
    )
)
    THROW 56503, 'Las solicitudes concurrentes no estan en su estado inicial.', 1;

DECLARE
    @error_revision int,
    @revision_id bigint,
    @operacion_id bigint,
    @error_doble_aceptacion int,
    @error_aceptar_rechazar int,
    @error_entregar_cancelar int,
    @error_revision_solicitud int,
    @tran int,
    @xstate int;

/* C1-A: revision simultanea del mismo scrap. Ambas revisiones deben
   serializarse con numeros distintos, sin perder actualizaciones. */
WHILE SYSUTCDATETIME() < @inicio_revision
    WAITFOR DELAY '00:00:00.050';

BEGIN TRY
    EXEC [log].revisar_scrap
        @scrap_id = @scrap_conc_id,
        @componente_orden_id = @componente_conc_b_id,
        @motivo_scrap_id = @motivo_componente_id,
        @cantidad = 7,
        @descripcion = N'ZZTEST 013 carrera revision cliente A',
        @es_anulacion = 0,
        @ajustado_por_supervisor_id = @supervisor_1_id,
        @motivo_ajuste = N'ZZTEST 013 concurrencia revision A',
        @correlacion_id = '13050100-0000-0000-0000-000000000001',
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
    THROW 56504, 'C1-A no completo limpiamente la revision serializada.', 1;

/* C2-A: dos aprovisionadores aceptan la misma solicitud. */
WHILE SYSUTCDATETIME() < @inicio_doble_aceptacion
    WAITFOR DELAY '00:00:00.050';

BEGIN TRY
    EXEC [log].transicionar_solicitud_reaprovisionamiento
        @solicitud_id = @solicitud_doble_aceptacion_id,
        @estado_nuevo = N'ACEPTADA',
        @empleado_id = @aprovisionador_1_id,
        @comentario = N'ZZTEST 013 doble aceptacion cliente A',
        @correlacion_id = '13050200-0000-0000-0000-000000000001';
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
    THROW 56505, 'C2-A dejo una transaccion abierta tras perder.', 1;

/* C3-A: aceptar frente a rechazar. */
WHILE SYSUTCDATETIME() < @inicio_aceptar_rechazar
    WAITFOR DELAY '00:00:00.050';

BEGIN TRY
    EXEC [log].transicionar_solicitud_reaprovisionamiento
        @solicitud_id = @solicitud_aceptar_rechazar_id,
        @estado_nuevo = N'ACEPTADA',
        @empleado_id = @aprovisionador_1_id,
        @comentario = N'ZZTEST 013 aceptar cliente A',
        @correlacion_id = '13050300-0000-0000-0000-000000000001';
END TRY
BEGIN CATCH
    SET @error_aceptar_rechazar = ERROR_NUMBER();
    IF @error_aceptar_rechazar <> 55309
        THROW;
END CATCH;

SET @tran = @@TRANCOUNT;
SET @xstate = XACT_STATE();

IF @error_aceptar_rechazar IS NOT NULL
   AND (@tran <> 0 OR @xstate <> 0)
    THROW 56506, 'C3-A dejo una transaccion abierta tras perder.', 1;

/* C4-A: entregar frente a cancelar una solicitud EN_CAMINO. */
WHILE SYSUTCDATETIME() < @inicio_entregar_cancelar
    WAITFOR DELAY '00:00:00.050';

BEGIN TRY
    EXEC [log].transicionar_solicitud_reaprovisionamiento
        @solicitud_id = @solicitud_entregar_cancelar_id,
        @estado_nuevo = N'ENTREGADA',
        @empleado_id = @aprovisionador_1_id,
        @comentario = N'ZZTEST 013 entregar cliente A',
        @correlacion_id = '13050400-0000-0000-0000-000000000001';
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
    THROW 56507, 'C4-A dejo una transaccion abierta tras perder.', 1;

/* C5-A: revision frente a solicitud vinculada al mismo scrap. */
WHILE SYSUTCDATETIME() < @inicio_revision_solicitud
    WAITFOR DELAY '00:00:00.050';

SET @revision_id = NULL;
SET @operacion_id = NULL;

BEGIN TRY
    EXEC [log].revisar_scrap
        @scrap_id = @scrap_main_activo_id,
        @componente_orden_id = @componente_main_a_id,
        @motivo_scrap_id = @motivo_componente_id,
        @cantidad = 2,
        @descripcion = N'ZZTEST 013 revision frente a solicitud',
        @es_anulacion = 0,
        @ajustado_por_supervisor_id = @supervisor_1_id,
        @motivo_ajuste = N'ZZTEST 013 carrera scrap solicitud A',
        @correlacion_id = '13050500-0000-0000-0000-000000000001',
        @revision_scrap_id = @revision_id OUTPUT,
        @operacion_nav_id = @operacion_id OUTPUT;
END TRY
BEGIN CATCH
    SET @error_revision_solicitud = ERROR_NUMBER();
END CATCH;

SET @tran = @@TRANCOUNT;
SET @xstate = XACT_STATE();

IF @error_revision_solicitud IS NOT NULL
 OR @revision_id IS NULL OR @operacion_id IS NULL
 OR @tran <> 0 OR @xstate <> 0
    THROW 56508, 'C5-A no completo la revision del scrap compartido.', 1;

SELECT
    N'A' cliente,
    @revision_id ultima_revision_cliente_a,
    CASE WHEN @error_doble_aceptacion IS NULL
         THEN N'GANADOR' ELSE N'RECHAZADO_ESPERADO' END doble_aceptacion,
    CASE WHEN @error_aceptar_rechazar IS NULL
         THEN N'ACEPTADA' ELSE N'RECHAZADA_POR_B' END aceptar_rechazar,
    CASE WHEN @error_entregar_cancelar IS NULL
         THEN N'ENTREGADA' ELSE N'CANCELADA_POR_B' END entregar_cancelar;

PRINT N'CLIENTE A CONCURRENCIA 013 COMPLETADO';
