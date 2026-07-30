SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME()<>N'EBIR_MES_TEST' THROW 52200,'Base no autorizada.',1;
/* Poner la misma hora UTC, unos 15 segundos en el futuro, en A y B. */
DECLARE @inicio datetime2(3)='2099-01-01T00:00:00.000'; -- REVISAR
IF @inicio<=SYSUTCDATETIME() OR @inicio>DATEADD(MINUTE,2,SYSUTCDATETIME())
 THROW 52201,'La hora de sincronizacion debe estar entre ahora y los proximos 2 minutos UTC.',1;
DECLARE @o bigint=(SELECT orden_id FROM prod.ordenes WHERE numero_orden=N'ZZT-FL-TX-02');
DECLARE @s bigint=(SELECT MIN(sesion_linea_id) FROM prod.sesiones_linea WHERE orden_id=@o);
DECLARE @l bigint=(SELECT linea_id FROM prod.sesiones_linea WHERE sesion_linea_id=@s);
DECLARE @e bigint=(SELECT empleado_id FROM seg.empleados WHERE codigo_nav=N'ZZT-EMP-TX-OP1');
DECLARE @corr uniqueidentifier=NEWID();
UPDATE prod.estados_linea SET sesion_linea_id=@s,estado=N'PRODUCIENDO',motivo_bloqueo=NULL WHERE linea_id=@l;
WHILE SYSUTCDATETIME()<@inicio WAITFOR DELAY '00:00:00.050';
DECLARE @r bigint;
BEGIN TRY
 EXEC prod.reservar_palet @o,@s,20,@e,@corr,@r OUTPUT;
 SELECT N'A' sesion,N'CONFIRMADA' resultado,@r reserva_palet_id;
END TRY
BEGIN CATCH
 SELECT N'A' sesion,N'RECHAZADA' resultado,ERROR_NUMBER() error_numero,ERROR_MESSAGE() mensaje;
END CATCH;
