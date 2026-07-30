/*
Reanudacion controlada tras aplicar y validar el paquete 010.
Estado esperado: caso 1 confirmado y una reserva activa en ZZT-FL-TX-01.
Estado: preparado para revision; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME()<>N'EBIR_MES_TEST' THROW 52500,'Base no autorizada.',1;

DECLARE @op1 bigint=(SELECT empleado_id FROM seg.empleados WHERE codigo_nav=N'ZZT-EMP-TX-OP1');
DECLARE @op2 bigint=(SELECT empleado_id FROM seg.empleados WHERE codigo_nav=N'ZZT-EMP-TX-OP2');
DECLARE @sup bigint=(SELECT empleado_id FROM seg.empleados WHERE codigo_nav=N'ZZT-EMP-TX-SUP');
DECLARE @corr uniqueidentifier=NEWID();
DECLARE @o1 bigint=(SELECT orden_id FROM prod.ordenes WHERE numero_orden=N'ZZT-FL-TX-01');
DECLARE @s1 bigint=(SELECT TOP(1) sesion_linea_id FROM prod.sesiones_linea WHERE orden_id=@o1);
DECLARE @l1 bigint=(SELECT linea_id FROM prod.sesiones_linea WHERE sesion_linea_id=@s1);
DECLARE @r1 bigint;

IF @op1 IS NULL OR @op2 IS NULL OR @sup IS NULL OR @o1 IS NULL OR @s1 IS NULL
 THROW 52501,'No se encuentran los fixtures requeridos.',1;
IF NOT EXISTS
(
 SELECT 1 FROM prod.ordenes
 WHERE orden_id=@o1 AND cantidad_buena_acumulada=0
   AND cantidad_reservada_activa=20 AND estado=N'ABIERTA'
)
 THROW 52502,'La orden ZZT-FL-TX-01 no conserva el estado esperado.',1;
IF (SELECT COUNT(*) FROM prod.reservas_palet WHERE orden_id=@o1 AND estado=N'ACTIVA')<>1
 THROW 52503,'No existe exactamente una reserva activa para reanudar.',1;
SELECT @r1=reserva_palet_id FROM prod.reservas_palet WHERE orden_id=@o1 AND estado=N'ACTIVA';
IF NOT EXISTS
(
 SELECT 1 FROM prod.reservas_palet
 WHERE reserva_palet_id=@r1 AND sesion_linea_id=@s1 AND cantidad_reservada=20
)
 THROW 52504,'La reserva activa no coincide con la sesion y cantidad esperadas.',1;
IF NOT EXISTS
(
 SELECT 1 FROM prod.estados_linea
 WHERE linea_id=@l1 AND sesion_linea_id=@s1 AND estado=N'PRODUCIENDO'
)
 THROW 52505,'La linea no conserva el estado PRODUCIENDO esperado.',1;
IF @@TRANCOUNT<>0 OR XACT_STATE()<>0
 THROW 52506,'La conexion no comienza en estado transaccional limpio.',1;
PRINT N'OK PRECONDICIONES - Reanudacion desde el caso 3';
/* 3 Motivo obligatorio y supervisor. */
BEGIN TRY
 EXEC prod.cancelar_reserva_palet @r1,@sup,N'   ',@corr;
 THROW 52104,'Caso 3: cancelacion sin motivo admitida.',1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>51300 THROW;
END CATCH;
IF NOT EXISTS(SELECT 1 FROM prod.reservas_palet WHERE reserva_palet_id=@r1 AND estado=N'ACTIVA')
 THROW 52105,'Caso 3: cambio tras error.',1;
EXEC prod.cancelar_reserva_palet @r1,@sup,N'ZZTEST cancelacion controlada',@corr;
PRINT N'OK 3 - Cancelacion supervisada';

/* 4 Cierre ordinario. */
DECLARE @r4 bigint,@p4 bigint;
EXEC prod.reservar_palet @o1,@s1,20,@op1,@corr,@r4 OUTPUT;
EXEC prod.cerrar_palet @r4,20,@op1,NULL,0,NULL,@corr,@p4 OUTPUT;
IF NOT EXISTS(SELECT 1 FROM nav.operaciones WHERE palet_id=@p4 AND tipo=N'SALIDA_PALET' AND estado=N'PENDIENTE')
 THROW 52106,'Caso 4: salida NAV ausente.',1;
IF NOT EXISTS(SELECT 1 FROM imp.etiquetas WHERE palet_id=@p4 AND estado=N'PENDIENTE_NAV' AND habilitada_utc IS NULL)
 THROW 52107,'Caso 4: etiqueta incorrecta.',1;
PRINT N'OK 4 - Cierre ordinario';

/* 5 NAV simulado local. */
DECLARE @nav4 bigint=(SELECT operacion_nav_id FROM nav.operaciones WHERE palet_id=@p4 AND tipo=N'SALIDA_PALET');
EXEC nav.confirmar_salida_palet @nav4,N'{"simulado":true}',N'ZZTEST-NAV-SIM-01',@corr;
DECLARE @job4 bigint=(SELECT t.trabajo_impresion_id FROM imp.trabajos_impresion t
 JOIN imp.etiquetas e ON e.etiqueta_id=t.etiqueta_id WHERE e.palet_id=@p4 AND t.estado=N'PENDIENTE');
IF @job4 IS NULL THROW 52108,'Caso 5: trabajo de impresion ausente.',1;
PRINT N'OK 5 - NAV simulado';

/* 6 Impresión simulada local y desbloqueo. */
DECLARE @prn bigint=(SELECT impresora_id FROM cfg.impresoras WHERE codigo=N'ZZT-PRN-TX-01');
EXEC imp.confirmar_trabajo_impresion @job4,@prn,@corr;
IF NOT EXISTS(SELECT 1 FROM prod.estados_linea WHERE linea_id=@l1 AND estado=N'PRODUCIENDO')
 THROW 52109,'Caso 6: linea no desbloqueada.',1;
PRINT N'OK 6 - Impresion y desbloqueo';

/* 7 Trabajo multilínea coherente:
   dos reservas de 20, primer cierre ordinario y último cierre supervisado. */
DECLARE @o5 bigint=(SELECT orden_id FROM prod.ordenes WHERE numero_orden=N'ZZT-FL-TX-05');
DECLARE @s5a bigint=(SELECT MIN(sesion_linea_id) FROM prod.sesiones_linea WHERE orden_id=@o5);
DECLARE @s5b bigint=(SELECT MAX(sesion_linea_id) FROM prod.sesiones_linea WHERE orden_id=@o5);
DECLARE @l5a bigint=(SELECT linea_id FROM prod.sesiones_linea WHERE sesion_linea_id=@s5a);
DECLARE @l5b bigint=(SELECT linea_id FROM prod.sesiones_linea WHERE sesion_linea_id=@s5b);
UPDATE prod.estados_linea SET sesion_linea_id=@s5a,estado=N'PRODUCIENDO',motivo_bloqueo=NULL WHERE linea_id=@l5a;
UPDATE prod.estados_linea SET sesion_linea_id=@s5b,estado=N'PRODUCIENDO',motivo_bloqueo=NULL WHERE linea_id=@l5b;
DECLARE @r5a bigint,@r5b bigint,@p5a bigint,@p5b bigint;
EXEC prod.reservar_palet @o5,@s5a,20,@op1,@corr,@r5a OUTPUT;
EXEC prod.reservar_palet @o5,@s5b,20,@op2,@corr,@r5b OUTPUT;
IF (SELECT cantidad_reservada_activa FROM prod.ordenes WHERE orden_id=@o5)<>40
 THROW 52110,'Caso 7: las dos reservas no quedaron consolidadas.',1;

EXEC prod.cerrar_palet @r5a,20,@op1,NULL,0,NULL,@corr,@p5a OUTPUT;
IF NOT EXISTS
(
 SELECT 1 FROM prod.palets
 WHERE palet_id=@p5a AND es_ultimo=0 AND cantidad_buena=20
)
 THROW 52111,'Caso 7: el primer cierre no fue ordinario.',1;
IF NOT EXISTS
(
 SELECT 1 FROM prod.reservas_palet
 WHERE reserva_palet_id=@r5b AND estado=N'ACTIVA'
)
 THROW 52112,'Caso 7: se perdio la reserva activa de la segunda linea.',1;

BEGIN TRY
 EXEC prod.cerrar_palet @r5b,20,@op2,NULL,0,NULL,@corr,@p5b OUTPUT;
 THROW 52113,'Caso 7: se admitio el ultimo palet sin supervisor.',1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>51407 THROW;
END CATCH;
IF NOT EXISTS
(
 SELECT 1 FROM prod.reservas_palet
 WHERE reserva_palet_id=@r5b AND estado=N'ACTIVA'
)
 THROW 52114,'Caso 7: el intento rechazado consumio la reserva.',1;

EXEC prod.cerrar_palet @r5b,20,@op2,@sup,0,NULL,@corr,@p5b OUTPUT;
IF NOT EXISTS
(
 SELECT 1 FROM prod.palets
 WHERE palet_id=@p5b AND es_ultimo=1
   AND autorizado_por_supervisor_id=@sup
)
 THROW 52115,'Caso 7: ultimo palet supervisado incorrecto.',1;
IF EXISTS
(
 SELECT 1 FROM prod.reservas_palet
 WHERE orden_id=@o5 AND estado=N'ACTIVA'
)
 THROW 52116,'Caso 7: quedaron reservas activas.',1;
IF NOT EXISTS
(
 SELECT 1 FROM prod.ordenes
 WHERE orden_id=@o5 AND cantidad_buena_acumulada=40
   AND cantidad_reservada_activa=0 AND estado=N'PENDIENTE_CIERRE'
)
 THROW 52117,'Caso 7: acumulados finales incorrectos.',1;
PRINT N'OK 7 - Multilinea: cierre ordinario y ultimo palet supervisado';

/* 8 Último palé correcto e idempotencia. */
DECLARE @o4 bigint=(SELECT orden_id FROM prod.ordenes WHERE numero_orden=N'ZZT-FL-TX-04');
DECLARE @s4 bigint=(SELECT TOP(1) sesion_linea_id FROM prod.sesiones_linea WHERE orden_id=@o4);
DECLARE @l4 bigint=(SELECT linea_id FROM prod.sesiones_linea WHERE sesion_linea_id=@s4);
UPDATE prod.estados_linea SET sesion_linea_id=@s4,estado=N'PRODUCIENDO',motivo_bloqueo=NULL WHERE linea_id=@l4;
DECLARE @r8 bigint,@p8 bigint;
EXEC prod.reservar_palet @o4,@s4,20,@op1,@corr,@r8 OUTPUT;
EXEC prod.cerrar_palet @r8,20,@op1,@sup,0,NULL,@corr,@p8 OUTPUT;
DECLARE @nav8 bigint=(SELECT operacion_nav_id FROM nav.operaciones WHERE palet_id=@p8 AND tipo=N'SALIDA_PALET');
EXEC nav.confirmar_salida_palet @nav8,N'{"simulado":true}',N'ZZTEST-NAV-SIM-ULT',@corr;
DECLARE @job8 bigint=(SELECT t.trabajo_impresion_id FROM imp.trabajos_impresion t
 JOIN imp.etiquetas e ON e.etiqueta_id=t.etiqueta_id WHERE e.palet_id=@p8 AND t.estado=N'PENDIENTE');
EXEC imp.confirmar_trabajo_impresion @job8,@prn,@corr;
IF (SELECT COUNT(*) FROM nav.operaciones WHERE orden_id=@o4 AND tipo=N'CIERRE_FL')<>1
 THROW 52118,'Caso 8: CIERRE_FL ausente o duplicado.',1;
BEGIN TRY
 EXEC imp.confirmar_trabajo_impresion @job8,@prn,@corr;
 THROW 52119,'Caso 8: doble confirmacion admitida.',1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>51600 THROW;
END CATCH;
IF (SELECT COUNT(*) FROM nav.operaciones WHERE orden_id=@o4 AND tipo=N'CIERRE_FL')<>1
 THROW 52120,'Caso 8: idempotencia alterada.',1;
PRINT N'OK 8 - Ultimo palet y CIERRE_FL';
