SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'EBIR_MES_TEST'
 THROW 52000,'Pruebas permitidas unicamente en EBIR_MES_TEST.',1;
IF OBJECT_ID(N'prod.reservar_palet',N'P') IS NULL
 OR OBJECT_ID(N'prod.cancelar_reserva_palet',N'P') IS NULL
 OR OBJECT_ID(N'prod.cerrar_palet',N'P') IS NULL
 OR OBJECT_ID(N'nav.confirmar_salida_palet',N'P') IS NULL
 OR OBJECT_ID(N'imp.confirmar_trabajo_impresion',N'P') IS NULL
 THROW 52001,'Faltan procedimientos operativos.',1;
IF EXISTS(SELECT 1 FROM prod.ordenes WHERE numero_orden LIKE N'ZZT-FL-TX-%')
 OR EXISTS(SELECT 1 FROM cfg.lineas WHERE codigo LIKE N'ZZT-TX-%')
 OR EXISTS(SELECT 1 FROM seg.empleados WHERE codigo_nav LIKE N'ZZT-EMP-TX-%')
 THROW 52002,'Ya existen fixtures ZZTEST; revisar limpieza.',1;

BEGIN TRANSACTION;
DECLARE @entorno smallint=(SELECT entorno_nav_id FROM nav.entornos WHERE codigo=N'EBIRTEST');
DECLARE @centro bigint=(SELECT centro_trabajo_id FROM cfg.centros_trabajo WHERE codigo=N'CT-01');
DECLARE @turno smallint=(SELECT turno_id FROM cfg.turnos WHERE codigo=N'MANANA');
IF @entorno IS NULL OR @centro IS NULL OR @turno IS NULL
 THROW 52003,'Faltan EBIRTEST, CT-01 o MANANA.',1;
INSERT nav.empresas(entorno_nav_id,codigo,nombre,activo)
VALUES(@entorno,N'ZZTEST_MES_TX_20260728',N'ZZTEST empresa sintetica',1);
DECLARE @empresa bigint=SCOPE_IDENTITY();
INSERT cfg.impresoras(codigo,nombre,modelo,nombre_red,direccion_ip,protocolo,activa)
VALUES(N'ZZT-PRN-TX-01',N'ZZTEST impresora simulada',N'SIMULADA_SIN_SALIDA',NULL,NULL,NULL,1);
DECLARE @impresora bigint=SCOPE_IDENTITY();
INSERT cfg.lineas(centro_trabajo_id,codigo,nombre,descripcion,activa) VALUES
(@centro,N'ZZT-TX-01',N'ZZTEST Linea 1',N'Sintetica; no planta',1),
(@centro,N'ZZT-TX-02',N'ZZTEST Linea 2',N'Sintetica; no planta',1),
(@centro,N'ZZT-TX-03',N'ZZTEST Linea 3',N'Sintetica; no planta',1),
(@centro,N'ZZT-TX-04',N'ZZTEST Linea 4',N'Sintetica; no planta',1),
(@centro,N'ZZT-TX-05',N'ZZTEST Linea 5',N'Sintetica; no planta',1),
(@centro,N'ZZT-TX-06',N'ZZTEST Linea 6',N'Sintetica; no planta',1),
(@centro,N'ZZT-TX-07',N'ZZTEST Linea 7',N'Sintetica; no planta',1);
INSERT cfg.lineas_impresoras
(linea_id,impresora_id,es_principal,asignado_desde_utc,asignado_por_cuenta,motivo)
SELECT linea_id,@impresora,1,SYSUTCDATETIME(),N'ZZTEST_MES_TX_20260728',N'Fixture'
FROM cfg.lineas WHERE codigo LIKE N'ZZT-TX-%';
INSERT seg.empleados
(codigo_nav,nombre_completo,activo_nav,activo_mes,sincronizado_nav_utc) VALUES
(N'ZZT-EMP-TX-OP1',N'ZZTEST Operario Uno',1,1,SYSUTCDATETIME()),
(N'ZZT-EMP-TX-OP2',N'ZZTEST Operario Dos',1,1,SYSUTCDATETIME()),
(N'ZZT-EMP-TX-SUP',N'ZZTEST Supervisor',1,1,SYSUTCDATETIME());
DECLARE @op1 bigint=(SELECT empleado_id FROM seg.empleados WHERE codigo_nav=N'ZZT-EMP-TX-OP1');
DECLARE @op2 bigint=(SELECT empleado_id FROM seg.empleados WHERE codigo_nav=N'ZZT-EMP-TX-OP2');
DECLARE @sup bigint=(SELECT empleado_id FROM seg.empleados WHERE codigo_nav=N'ZZT-EMP-TX-SUP');
DECLARE @rolop smallint=(SELECT rol_id FROM seg.roles WHERE codigo=N'OPERARIO');
DECLARE @rolsup smallint=(SELECT rol_id FROM seg.roles WHERE codigo=N'SUPERVISOR');
INSERT seg.empleados_roles(empleado_id,rol_id,desde_utc,asignado_por_cuenta,motivo) VALUES
(@op1,@rolop,SYSUTCDATETIME(),N'ZZTEST_MES_TX_20260728',N'Fixture'),
(@op2,@rolop,SYSUTCDATETIME(),N'ZZTEST_MES_TX_20260728',N'Fixture'),
(@sup,@rolsup,SYSUTCDATETIME(),N'ZZTEST_MES_TX_20260728',N'Fixture');
DECLARE @spec TABLE(numero nvarchar(30),objetivo int,buenas int,modo nvarchar(20),formato int);
INSERT @spec VALUES
(N'ZZT-FL-TX-01',60,0,N'NORMAL',20),
(N'ZZT-FL-TX-02',100,80,N'MULTILINEA',20),
(N'ZZT-FL-TX-03',40,0,N'NORMAL',20),
(N'ZZT-FL-TX-04',20,0,N'NORMAL',20),
(N'ZZT-FL-TX-05',40,0,N'MULTILINEA',20);
INSERT prod.ordenes
(empresa_nav_id,numero_orden,producto_codigo,producto_descripcion,producto_barcode,
 lote,cantidad_objetivo,cantidad_buena_acumulada,tiempo_ejecucion_nav_min,
 modo_trabajo,estado,datos_nav_originales)
SELECT @empresa,numero,N'ZZT-PROD-TX',N'ZZTEST producto',N'ZZTEST-NO-GS1',
 numero,objetivo,buenas,1.0,modo,N'IMPORTADA',
 N'{"origen":"ZZTEST_MES_TX_20260728","nav_real":false}' FROM @spec;
INSERT prod.formatos_palet_orden
(orden_id,codigo_formato,unidades_por_palet,descripcion,es_predeterminado_nav,
 datos_nav_originales,activo)
SELECT p.orden_id,N'ZZT-FMT-TX',s.formato,N'ZZTEST formato',1,
 N'{"origen":"ZZTEST_MES_TX_20260728"}',1
FROM prod.ordenes p JOIN @spec s ON s.numero=p.numero_orden;
DECLARE @l1 bigint=(SELECT linea_id FROM cfg.lineas WHERE codigo=N'ZZT-TX-01');
DECLARE @l2 bigint=(SELECT linea_id FROM cfg.lineas WHERE codigo=N'ZZT-TX-02');
DECLARE @l3 bigint=(SELECT linea_id FROM cfg.lineas WHERE codigo=N'ZZT-TX-03');
DECLARE @l4 bigint=(SELECT linea_id FROM cfg.lineas WHERE codigo=N'ZZT-TX-04');
DECLARE @l5 bigint=(SELECT linea_id FROM cfg.lineas WHERE codigo=N'ZZT-TX-05');
DECLARE @l6 bigint=(SELECT linea_id FROM cfg.lineas WHERE codigo=N'ZZT-TX-06');
DECLARE @l7 bigint=(SELECT linea_id FROM cfg.lineas WHERE codigo=N'ZZT-TX-07');
DECLARE @ses TABLE(numero nvarchar(30),linea bigint);
INSERT @ses VALUES
(N'ZZT-FL-TX-01',@l1),(N'ZZT-FL-TX-02',@l2),(N'ZZT-FL-TX-02',@l3),
(N'ZZT-FL-TX-03',@l4),(N'ZZT-FL-TX-04',@l5),
(N'ZZT-FL-TX-05',@l6),(N'ZZT-FL-TX-05',@l7);
INSERT prod.sesiones_linea
(orden_id,linea_id,turno_id,formato_palet_orden_id,fecha_operativa,
 estado,iniciada_utc,cargada_por_empleado_id)
SELECT o.orden_id,x.linea,@turno,f.formato_palet_orden_id,
 CONVERT(date,SYSUTCDATETIME()),N'PRODUCIENDO',SYSUTCDATETIME(),@sup
FROM @ses x JOIN prod.ordenes o ON o.numero_orden=x.numero
JOIN prod.formatos_palet_orden f ON f.orden_id=o.orden_id;
INSERT prod.estados_linea(linea_id,sesion_linea_id,estado)
SELECT linea_id,NULL,N'LIBRE' FROM cfg.lineas WHERE codigo LIKE N'ZZT-TX-%';
COMMIT;
PRINT N'PREVUELO Y FIXTURES: PREPARADOS';
