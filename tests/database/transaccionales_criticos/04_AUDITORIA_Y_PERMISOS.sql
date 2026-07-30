SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME()<>N'EBIR_MES_TEST' THROW 52400,'Base no autorizada.',1;
DECLARE @tipos TABLE(tipo nvarchar(80) PRIMARY KEY);
INSERT @tipos VALUES
(N'RESERVA_PALET_CREADA'),
(N'RESERVA_PALET_CANCELADA'),
(N'PALET_CERRADO'),
(N'SALIDA_PALET_NAV_CONFIRMADA'),
(N'ETIQUETA_IMPRESA');
IF EXISTS
(
 SELECT 1 FROM @tipos t
 WHERE NOT EXISTS
 (
  SELECT 1 FROM aud.eventos a
  JOIN prod.ordenes o ON o.orden_id=a.orden_id
  WHERE o.numero_orden LIKE N'ZZT-FL-TX-%'
    AND a.tipo_evento=t.tipo
 )
)
 THROW 52401,'Falta al menos un tipo de auditoria esperado.',1;
IF EXISTS
(
 SELECT 1 FROM aud.eventos a
 JOIN prod.ordenes o ON o.orden_id=a.orden_id
 WHERE o.numero_orden LIKE N'ZZT-FL-TX-%'
   AND a.correlacion_id IS NULL
)
 THROW 52402,'Existe auditoria sintetica sin correlacion.',1;
IF EXISTS
(
 SELECT 1 FROM aud.eventos a JOIN prod.ordenes o ON o.orden_id=a.orden_id
 WHERE o.numero_orden LIKE N'ZZT-FL-TX-%'
 AND (a.valor_anterior LIKE N'%rfid%' OR a.valor_nuevo LIKE N'%rfid%'
 OR a.motivo LIKE N'%rfid%')
)
 THROW 52403,'Posible RFID expuesto.',1;
IF USER_ID(N'EBIR\MES$') IS NULL THROW 52404,'Runtime ausente.',1;

EXECUTE AS USER=N'EBIR\MES$';
BEGIN TRY
 IF EXISTS
 (
  SELECT 1
  FROM
  (
   VALUES
   (N'prod.reservar_palet'),
   (N'prod.cancelar_reserva_palet'),
   (N'prod.cerrar_palet'),
   (N'nav.confirmar_salida_palet'),
   (N'imp.confirmar_trabajo_impresion')
  ) p(objeto)
  WHERE HAS_PERMS_BY_NAME(p.objeto,N'OBJECT',N'EXECUTE')<>1
 )
  THROW 52405,'Runtime sin EXECUTE en algun procedimiento operativo.',1;
 IF HAS_PERMS_BY_NAME(N'aud.registrar_evento',N'OBJECT',N'EXECUTE')<>0
  THROW 52406,'Runtime puede ejecutar directamente el registrador de auditoria.',1;
 IF HAS_PERMS_BY_NAME(N'aud.eventos',N'OBJECT',N'SELECT')<>0
  THROW 52407,'Runtime puede leer auditoria.',1;
 IF HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'CREATE TABLE')<>0
  THROW 52408,'Runtime puede crear tablas.',1;
 IF HAS_PERMS_BY_NAME(N'prod.ordenes',N'OBJECT',N'UPDATE')<>0
  THROW 52409,'Runtime puede escribir directamente en produccion.',1;
 IF HAS_PERMS_BY_NAME(N'nav.operaciones',N'OBJECT',N'INSERT')<>0
  THROW 52410,'Runtime puede insertar directamente operaciones NAV.',1;
 IF HAS_PERMS_BY_NAME(N'imp.trabajos_impresion',N'OBJECT',N'INSERT')<>0
  THROW 52411,'Runtime puede insertar directamente trabajos de impresion.',1;
END TRY
BEGIN CATCH
 REVERT;
 THROW;
END CATCH;
REVERT;
PRINT N'OK 9 - Auditoria y permisos';
