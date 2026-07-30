/* Paquete 014: casos funcionales. Requiere 00. No ejecutar sin autorizacion. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'EBIR_MES_TEST' THROW 57100, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

DECLARE @op bigint = (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ14-OP1');
DECLARE @orden bigint = (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ14-FUNC');
DECLARE @sesion bigint = (SELECT sesion_linea_id FROM prod.sesiones_linea WHERE orden_id = @orden);
IF @op IS NULL OR @orden IS NULL OR @sesion IS NULL THROW 57101, 'Fixtures ausentes.', 1;

DECLARE @reserva bigint, @palet bigint, @palet_repetido bigint;
DECLARE @correlacion uniqueidentifier = '14010100-0000-0000-0000-000000000001';
EXEC prod.reservar_palet @orden, @sesion, 20, @op, '14010000-0000-0000-0000-000000000001', @reserva OUTPUT;
EXEC prod.cerrar_palet_idempotente @reserva, 20, @op, NULL, 0, NULL, @correlacion, @palet OUTPUT;
EXEC prod.cerrar_palet_idempotente @reserva, 20, @op, NULL, 0, NULL, @correlacion, @palet_repetido OUTPUT;
IF @palet IS NULL OR @palet <> @palet_repetido
 OR (SELECT COUNT(*) FROM prod.palets WHERE reserva_palet_id = @reserva) <> 1
 OR (SELECT COUNT(*) FROM nav.operaciones WHERE palet_id = @palet AND tipo = N'SALIDA_PALET') <> 1
 OR (SELECT COUNT(*) FROM imp.etiquetas WHERE palet_id = @palet AND tipo = N'PALET') <> 1
    THROW 57102, 'El reintento identico no fue idempotente.', 1;

BEGIN TRY
    EXEC prod.cerrar_palet_idempotente @reserva, 19, @op, NULL, 1, N'FIN_TURNO', @correlacion, @palet_repetido OUTPUT;
    THROW 57103, 'Se admitieron parametros distintos.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 55403 THROW; END CATCH;
BEGIN TRY
    EXEC prod.cerrar_palet_idempotente @reserva, 20, @op, NULL, 0, NULL, NULL, @palet_repetido OUTPUT;
    THROW 57104, 'Se admitio correlacion nula.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 55400 THROW; END CATCH;

INSERT aud.eventos (tipo_evento, entidad, entidad_id, correlacion_id, fecha_utc)
VALUES (N'ZZTEST_OTRA_OPERACION', N'ZZTEST', 1, '14010200-0000-0000-0000-000000000001', SYSUTCDATETIME());
BEGIN TRY
    EXEC prod.cerrar_palet_idempotente @reserva, 20, @op, NULL, 0, NULL, '14010200-0000-0000-0000-000000000001', @palet_repetido OUTPUT;
    THROW 57105, 'Se admitio correlacion de otra operacion.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 55402 THROW; END CATCH;
BEGIN TRY
    EXEC prod.cerrar_palet_idempotente @reserva, 0, @op, NULL, 0, NULL, '14010300-0000-0000-0000-000000000001', @palet_repetido OUTPUT;
    THROW 57106, 'No se propago 51400.', 1;
END TRY BEGIN CATCH IF ERROR_NUMBER() <> 51400 THROW; END CATCH;
DECLARE @orden_concurrencia bigint = (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ14-CONC');
DECLARE @sesion_concurrencia_a bigint = (SELECT MIN(sesion_linea_id) FROM prod.sesiones_linea WHERE orden_id = @orden_concurrencia);
DECLARE @sesion_concurrencia_b bigint = (SELECT MAX(sesion_linea_id) FROM prod.sesiones_linea WHERE orden_id = @orden_concurrencia);
DECLARE @reserva_concurrencia_a bigint, @reserva_concurrencia_b bigint;
EXEC prod.reservar_palet @orden_concurrencia, @sesion_concurrencia_a, 20, @op, '14010400-0000-0000-0000-000000000001', @reserva_concurrencia_a OUTPUT;
EXEC prod.reservar_palet @orden_concurrencia, @sesion_concurrencia_b, 20, @op, '14010400-0000-0000-0000-000000000002', @reserva_concurrencia_b OUTPUT;
IF @reserva_concurrencia_a IS NULL OR @reserva_concurrencia_b IS NULL THROW 57107, 'No se pudieron preparar las carreras concurrentes.', 1;
PRINT N'FUNCIONALES 014: OK';
