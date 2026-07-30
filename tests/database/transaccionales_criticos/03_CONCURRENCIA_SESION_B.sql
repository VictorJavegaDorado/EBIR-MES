SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME()<>N'EBIR_MES_TEST' THROW 52300,'Base no autorizada.',1;
DECLARE @inicio datetime2(3)='2099-01-01T00:00:00.000'; -- MISMA HORA QUE A
IF @inicio<=SYSUTCDATETIME() OR @inicio>DATEADD(MINUTE,2,SYSUTCDATETIME())
 THROW 52301,'La hora de sincronizacion debe estar entre ahora y los proximos 2 minutos UTC.',1;
DECLARE @o bigint=(SELECT orden_id FROM prod.ordenes WHERE numero_orden=N'ZZT-FL-TX-02');
DECLARE @s bigint=(SELECT MAX(sesion_linea_id) FROM prod.sesiones_linea WHERE orden_id=@o);
DECLARE @l bigint=(SELECT linea_id FROM prod.sesiones_linea WHERE sesion_linea_id=@s);
DECLARE @e bigint=(SELECT empleado_id FROM seg.empleados WHERE codigo_nav=N'ZZT-EMP-TX-OP2');
DECLARE @corr uniqueidentifier=NEWID();
UPDATE prod.estados_linea SET sesion_linea_id=@s,estado=N'PRODUCIENDO',motivo_bloqueo=NULL WHERE linea_id=@l;
WHILE SYSUTCDATETIME()<@inicio WAITFOR DELAY '00:00:00.050';
DECLARE @r bigint;
BEGIN TRY
 EXEC prod.reservar_palet @o,@s,20,@e,@corr,@r OUTPUT;
 SELECT N'B' sesion,N'CONFIRMADA' resultado,@r reserva_palet_id;
END TRY
BEGIN CATCH
 SELECT N'B' sesion,N'RECHAZADA' resultado,ERROR_NUMBER() error_numero,ERROR_MESSAGE() mensaje;
END CATCH;
IF EXISTS(SELECT 1 FROM prod.ordenes WHERE orden_id=@o
 AND cantidad_buena_acumulada+cantidad_reservada_activa>cantidad_objetivo)
 THROW 52302,'Invariante global incumplida.',1;
IF (SELECT COUNT(*) FROM prod.reservas_palet WHERE orden_id=@o AND estado=N'ACTIVA')<>1
 THROW 52303,'La concurrencia no termino con exactamente una reserva activa.',1;
IF NOT EXISTS
(
 SELECT 1 FROM prod.ordenes
 WHERE orden_id=@o AND cantidad_buena_acumulada=80
   AND cantidad_reservada_activa=20 AND cantidad_objetivo=100
)
 THROW 52304,'Los acumulados finales de concurrencia no son los esperados.',1;
SELECT cantidad_objetivo,cantidad_buena_acumulada,cantidad_reservada_activa
FROM prod.ordenes WHERE orden_id=@o;
PRINT N'OK 2b - Concurrencia multilínea: una reserva confirmada y otra rechazada';
