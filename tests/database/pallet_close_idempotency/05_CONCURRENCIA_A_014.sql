/* Cliente A: ejecutar junto con 06, misma marca UTC futura. No ejecutar sin autorizacion. */
SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME() <> N'EBIR_MES_TEST' THROW 57500, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;
DECLARE @inicio datetime2(3) = '2099-01-01T00:00:00.000'; -- REVISAR: igual en A y B
IF @inicio <= DATEADD(SECOND,2,SYSUTCDATETIME()) OR @inicio > DATEADD(MINUTE,2,SYSUTCDATETIME()) THROW 57501, 'Marca UTC invalida.', 1;
DECLARE @op bigint = (SELECT empleado_id FROM seg.empleados WHERE codigo_nav=N'ZZ14-OP1');
DECLARE @orden bigint = (SELECT orden_id FROM prod.ordenes WHERE numero_orden=N'ZZ14-CONC');
DECLARE @reserva bigint = (SELECT MIN(reserva_palet_id) FROM prod.reservas_palet WHERE orden_id=@orden AND estado=N'ACTIVA');
DECLARE @reserva_distinta bigint = (SELECT MAX(reserva_palet_id) FROM prod.reservas_palet WHERE orden_id=@orden AND estado=N'ACTIVA');
DECLARE @palet bigint, @error int = NULL;
IF @op IS NULL OR @orden IS NULL OR @reserva IS NULL OR @reserva=@reserva_distinta THROW 57502, 'Faltan las dos reservas preparadas en 01.', 1;
WHILE SYSUTCDATETIME() < @inicio WAITFOR DELAY '00:00:00.050';
BEGIN TRY EXEC prod.cerrar_palet_idempotente @reserva,20,@op,NULL,0,NULL,'14050100-0000-0000-0000-000000000001',@palet OUTPUT; END TRY
BEGIN CATCH SET @error=ERROR_NUMBER(); END CATCH;
IF @error IS NOT NULL OR @palet IS NULL OR @@TRANCOUNT<>0 THROW 57503, 'A no completo limpiamente el reintento identico.', 1;
INSERT aud.eventos(tipo_evento,empleado_id,orden_id,entidad,entidad_id,valor_nuevo,correlacion_id)
VALUES(N'ZZTEST_014_BARRERA_IDENTICA_A',@op,@orden,N'prod.palets',@palet,CONCAT(N'{"palet_id":',@palet,N'}'),'1405A100-0000-0000-0000-000000000001');
DECLARE @limite datetime2(3)=DATEADD(SECOND,15,SYSUTCDATETIME());
WHILE (SELECT COUNT(*) FROM aud.eventos WHERE correlacion_id IN('1405A100-0000-0000-0000-000000000001','1405B100-0000-0000-0000-000000000001'))<2 AND SYSUTCDATETIME()<@limite WAITFOR DELAY '00:00:00.050';
IF (SELECT COUNT(*) FROM aud.eventos WHERE correlacion_id IN('1405A100-0000-0000-0000-000000000001','1405B100-0000-0000-0000-000000000001'))<>2 THROW 57504, 'Barrera identica no alcanzo ambos clientes.',1;
IF (SELECT COUNT(DISTINCT entidad_id) FROM aud.eventos WHERE correlacion_id IN('1405A100-0000-0000-0000-000000000001','1405B100-0000-0000-0000-000000000001'))<>1 OR (SELECT COUNT(*) FROM prod.palets WHERE reserva_palet_id=@reserva)<>1 OR (SELECT COUNT(*) FROM nav.operaciones WHERE palet_id=@palet AND tipo=N'SALIDA_PALET')<>1 OR (SELECT COUNT(*) FROM imp.etiquetas WHERE palet_id=@palet AND tipo=N'PALET')<>1 OR (SELECT COUNT(*) FROM aud.eventos WHERE correlacion_id='14050100-0000-0000-0000-000000000001' AND tipo_evento=N'PALET_CERRADO')<>1 THROW 57505, 'La carrera identica no termino con un cierre completo.',1;
WHILE SYSUTCDATETIME() < DATEADD(SECOND,4,@inicio) WAITFOR DELAY '00:00:00.050';
SET @palet=NULL; SET @error=NULL;
BEGIN TRY EXEC prod.cerrar_palet_idempotente @reserva_distinta,20,@op,NULL,0,NULL,'14050200-0000-0000-0000-000000000001',@palet OUTPUT; END TRY BEGIN CATCH SET @error=ERROR_NUMBER(); END CATCH;
IF @error IS NOT NULL AND @error<>51403 THROW 57506, 'A recibio un rechazo no esperado en la carrera distinta.',1;
IF @@TRANCOUNT<>0 THROW 57507, 'A dejo una transaccion abierta.',1;
INSERT aud.eventos(tipo_evento,empleado_id,orden_id,entidad,entidad_id,valor_nuevo,correlacion_id) VALUES(N'ZZTEST_014_BARRERA_DISTINTA_A',@op,@orden,N'prod.reservas_palet',@reserva_distinta,CONCAT(N'{"palet_id":',COALESCE(CONVERT(nvarchar(20),@palet),N'null'),N',"error":',COALESCE(CONVERT(nvarchar(20),@error),N'null'),N'}'),'1405A200-0000-0000-0000-000000000001');
