/* Paquete 014: limpieza exclusiva ZZTEST_014 / ZZ14-. No ejecutar sin autorizacion. */
SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME() <> N'EBIR_MES_TEST' THROW 57900, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;
BEGIN TRY
 BEGIN TRANSACTION;
 DELETE a FROM aud.eventos a JOIN prod.ordenes o ON o.orden_id=a.orden_id WHERE o.numero_orden LIKE N'ZZ14-%';
 DELETE FROM aud.eventos WHERE correlacion_id='14010200-0000-0000-0000-000000000001';
 DELETE n FROM nav.intentos_operacion n JOIN nav.operaciones o ON o.operacion_nav_id=n.operacion_nav_id JOIN prod.ordenes po ON po.orden_id=o.orden_id WHERE po.numero_orden LIKE N'ZZ14-%';
 DELETE n FROM nav.operaciones n JOIN prod.ordenes o ON o.orden_id=n.orden_id WHERE o.numero_orden LIKE N'ZZ14-%';
 DELETE t FROM imp.trabajos_impresion t JOIN imp.etiquetas e ON e.etiqueta_id=t.etiqueta_id JOIN prod.ordenes o ON o.orden_id=e.orden_id WHERE o.numero_orden LIKE N'ZZ14-%';
 DELETE e FROM imp.etiquetas e JOIN prod.ordenes o ON o.orden_id=e.orden_id WHERE o.numero_orden LIKE N'ZZ14-%';
 DELETE p FROM prod.palets p JOIN prod.ordenes o ON o.orden_id=p.orden_id WHERE o.numero_orden LIKE N'ZZ14-%';
 DELETE r FROM prod.reservas_palet r JOIN prod.ordenes o ON o.orden_id=r.orden_id WHERE o.numero_orden LIKE N'ZZ14-%';
 DELETE es FROM prod.estados_linea es JOIN cfg.lineas l ON l.linea_id=es.linea_id WHERE l.codigo LIKE N'ZZ14-%';
 DELETE s FROM prod.sesiones_linea s JOIN prod.ordenes o ON o.orden_id=s.orden_id WHERE o.numero_orden LIKE N'ZZ14-%';
 DELETE f FROM prod.formatos_palet_orden f JOIN prod.ordenes o ON o.orden_id=f.orden_id WHERE o.numero_orden LIKE N'ZZ14-%';
 DELETE FROM prod.ordenes WHERE numero_orden LIKE N'ZZ14-%'; DELETE FROM cfg.lineas WHERE codigo LIKE N'ZZ14-%';
 DELETE er FROM seg.empleados_roles er JOIN seg.empleados e ON e.empleado_id=er.empleado_id WHERE e.codigo_nav LIKE N'ZZ14-%'; DELETE FROM seg.empleados WHERE codigo_nav LIKE N'ZZ14-%'; DELETE FROM nav.empresas WHERE codigo=N'ZZTEST_014';
 IF EXISTS(SELECT 1 FROM prod.ordenes WHERE numero_orden LIKE N'ZZ14-%') OR EXISTS(SELECT 1 FROM cfg.lineas WHERE codigo LIKE N'ZZ14-%') OR EXISTS(SELECT 1 FROM seg.empleados WHERE codigo_nav LIKE N'ZZ14-%') THROW 57901, 'Limpieza incompleta.', 1;
 COMMIT TRANSACTION;
END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK TRANSACTION; THROW; END CATCH;
PRINT N'LIMPIEZA 014: OK';
