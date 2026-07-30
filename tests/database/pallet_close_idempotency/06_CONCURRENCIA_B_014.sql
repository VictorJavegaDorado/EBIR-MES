/* Cliente B. Ejecutar junto a 05 y con la misma marca UTC futura. */
SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME() <> N'EBIR_MES_TEST' THROW 57600, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;
DECLARE @inicio datetime2(3) = '2099-01-01T00:00:00.000'; -- MISMA MARCA QUE A
IF @inicio <= DATEADD(SECOND,2,SYSUTCDATETIME()) OR @inicio > DATEADD(MINUTE,2,SYSUTCDATETIME()) THROW 57601, 'Marca UTC invalida.', 1;
DECLARE @op bigint = (SELECT empleado_id FROM seg.empleados WHERE codigo_nav=N'ZZ14-OP2');
DECLARE @reserva bigint = (SELECT MIN(r.reserva_palet_id) FROM prod.reservas_palet r JOIN prod.ordenes o ON o.orden_id=r.orden_id WHERE o.numero_orden=N'ZZ14-CONC' AND r.estado=N'ACTIVA');
DECLARE @reserva_distinta bigint = (SELECT MAX(r.reserva_palet_id) FROM prod.reservas_palet r JOIN prod.ordenes o ON o.orden_id=r.orden_id WHERE o.numero_orden=N'ZZ14-CONC' AND r.estado=N'ACTIVA');
DECLARE @palet bigint;
IF @reserva IS NULL OR @reserva = @reserva_distinta THROW 57602, 'Faltan las dos reservas preparadas en 01.', 1;
WHILE SYSUTCDATETIME() < @inicio WAITFOR DELAY '00:00:00.050';
BEGIN TRY EXEC prod.cerrar_palet_idempotente @reserva,20,@op,NULL,0,NULL,'14050100-0000-0000-0000-000000000001',@palet OUTPUT; SELECT N'B-identica' cliente,@palet palet_id; END TRY
BEGIN CATCH SELECT N'B-identica' cliente,ERROR_NUMBER() error_numero,ERROR_MESSAGE() mensaje; END CATCH;
WHILE SYSUTCDATETIME() < DATEADD(SECOND,4,@inicio) WAITFOR DELAY '00:00:00.050';
BEGIN TRY EXEC prod.cerrar_palet_idempotente @reserva_distinta,20,@op,NULL,0,NULL,'14050200-0000-0000-0000-000000000002',@palet OUTPUT; SELECT N'B-distinta' cliente,@palet palet_id; END TRY
BEGIN CATCH SELECT N'B-distinta' cliente,ERROR_NUMBER() error_numero,ERROR_MESSAGE() mensaje; END CATCH;
IF (SELECT COUNT(*) FROM prod.palets WHERE reserva_palet_id=@reserva) <> 1 THROW 57603, 'La misma correlacion creo mas de un palet.', 1;
IF (SELECT COUNT(*) FROM prod.palets WHERE reserva_palet_id=@reserva_distinta) <> 1 OR (SELECT COUNT(*) FROM aud.eventos WHERE correlacion_id IN ('14050200-0000-0000-0000-000000000001','14050200-0000-0000-0000-000000000002') AND tipo_evento=N'PALET_CERRADO') <> 1 THROW 57604, 'Dos correlaciones cerraron la misma reserva.', 1;
