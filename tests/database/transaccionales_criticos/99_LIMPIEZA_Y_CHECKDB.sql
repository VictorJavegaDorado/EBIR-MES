SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME()<>N'EBIR_MES_TEST' THROW 52900,'Base no autorizada.',1;
/* Ejecutar solo con autorización separada. */
BEGIN TRANSACTION;
DECLARE @ordenes TABLE(id bigint PRIMARY KEY);
INSERT @ordenes SELECT orden_id FROM prod.ordenes WHERE numero_orden LIKE N'ZZT-FL-TX-%';
DECLARE @lineas TABLE(id bigint PRIMARY KEY);
INSERT @lineas SELECT linea_id FROM cfg.lineas WHERE codigo LIKE N'ZZT-TX-%';
DECLARE @empleados TABLE(id bigint PRIMARY KEY);
INSERT @empleados SELECT empleado_id FROM seg.empleados WHERE codigo_nav LIKE N'ZZT-EMP-TX-%';

DELETE a FROM aud.eventos a WHERE a.orden_id IN(SELECT id FROM @ordenes)
 OR a.linea_id IN(SELECT id FROM @lineas) OR a.empleado_id IN(SELECT id FROM @empleados);
DELETE i FROM imp.intentos_impresion i
 JOIN imp.trabajos_impresion t ON t.trabajo_impresion_id=i.trabajo_impresion_id
 JOIN imp.etiquetas e ON e.etiqueta_id=t.etiqueta_id WHERE e.orden_id IN(SELECT id FROM @ordenes);
DELETE t FROM imp.trabajos_impresion t JOIN imp.etiquetas e ON e.etiqueta_id=t.etiqueta_id
 WHERE e.orden_id IN(SELECT id FROM @ordenes);
DELETE FROM imp.etiquetas WHERE orden_id IN(SELECT id FROM @ordenes);
DELETE i FROM nav.intentos_operacion i JOIN nav.operaciones o ON o.operacion_nav_id=i.operacion_nav_id
 WHERE o.orden_id IN(SELECT id FROM @ordenes);
DELETE FROM nav.operaciones WHERE orden_id IN(SELECT id FROM @ordenes);
DELETE FROM prod.palets WHERE orden_id IN(SELECT id FROM @ordenes);
DELETE FROM prod.reservas_palet WHERE orden_id IN(SELECT id FROM @ordenes);
DELETE FROM prod.estados_linea WHERE linea_id IN(SELECT id FROM @lineas);
DELETE FROM prod.sesiones_linea WHERE orden_id IN(SELECT id FROM @ordenes);
DELETE FROM prod.formatos_palet_orden WHERE orden_id IN(SELECT id FROM @ordenes);
DELETE FROM nav.componentes_orden WHERE orden_id IN(SELECT id FROM @ordenes);
DELETE FROM prod.ordenes WHERE orden_id IN(SELECT id FROM @ordenes);
DELETE FROM cfg.lineas_impresoras WHERE linea_id IN(SELECT id FROM @lineas);
DELETE FROM cfg.lineas_dispositivos WHERE linea_id IN(SELECT id FROM @lineas);
DELETE FROM cfg.lineas WHERE linea_id IN(SELECT id FROM @lineas);
DELETE FROM cfg.impresoras WHERE codigo=N'ZZT-PRN-TX-01';
DELETE FROM seg.empleados_roles WHERE empleado_id IN(SELECT id FROM @empleados);
DELETE FROM seg.credenciales_rfid WHERE empleado_id IN(SELECT id FROM @empleados);
DELETE FROM seg.empleados WHERE empleado_id IN(SELECT id FROM @empleados);
DELETE FROM nav.empresas WHERE codigo=N'ZZTEST_MES_TX_20260728';

IF EXISTS(SELECT 1 FROM prod.ordenes WHERE numero_orden LIKE N'ZZT-FL-TX-%')
 OR EXISTS(SELECT 1 FROM cfg.lineas WHERE codigo LIKE N'ZZT-TX-%')
 OR EXISTS(SELECT 1 FROM seg.empleados WHERE codigo_nav LIKE N'ZZT-EMP-TX-%')
 OR EXISTS(SELECT 1 FROM nav.empresas WHERE codigo=N'ZZTEST_MES_TX_20260728')
 OR EXISTS(SELECT 1 FROM cfg.impresoras WHERE codigo=N'ZZT-PRN-TX-01')
 OR EXISTS
 (
  SELECT 1 FROM prod.sesiones_linea s
  JOIN prod.ordenes o ON o.orden_id=s.orden_id
  WHERE o.numero_orden LIKE N'ZZT-FL-TX-%'
 )
 OR EXISTS
 (
  SELECT 1 FROM nav.operaciones n
  JOIN prod.ordenes o ON o.orden_id=n.orden_id
  WHERE o.numero_orden LIKE N'ZZT-FL-TX-%'
 )
 THROW 52901,'Limpieza incompleta; se revierte.',1;
COMMIT;
PRINT N'OK 10a - Fixtures eliminados';
DBCC CHECKDB(N'EBIR_MES_TEST') WITH NO_INFOMSGS,ALL_ERRORMSGS;
PRINT N'OK 10b - DBCC CHECKDB finalizado';
