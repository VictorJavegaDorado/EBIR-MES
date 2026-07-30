/* Paquete 014: prevuelo y fixtures sinteticos. No ejecutar sin autorizacion. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 57000, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'prod.cerrar_palet_idempotente', N'P') IS NULL
 OR OBJECT_ID(N'prod.cerrar_palet', N'P') IS NULL
    THROW 57001, 'El paquete 014 no esta instalado completo.', 1;

IF EXISTS (SELECT 1 FROM prod.ordenes WHERE numero_orden LIKE N'ZZ14-%')
 OR EXISTS (SELECT 1 FROM cfg.lineas WHERE codigo LIKE N'ZZ14-%')
 OR EXISTS (SELECT 1 FROM seg.empleados WHERE codigo_nav LIKE N'ZZ14-%')
    THROW 57002, 'Ya existen fixtures ZZ14-; revisar limpieza.', 1;

DECLARE @entorno smallint = (SELECT entorno_nav_id FROM nav.entornos WHERE codigo = N'EBIRTEST');
DECLARE @centro bigint = (SELECT centro_trabajo_id FROM cfg.centros_trabajo WHERE codigo = N'CT-01');
DECLARE @turno smallint = (SELECT turno_id FROM cfg.turnos WHERE codigo = N'MANANA');
DECLARE @rol_operario smallint = (SELECT rol_id FROM seg.roles WHERE codigo = N'OPERARIO' AND activo = 1);
DECLARE @rol_supervisor smallint = (SELECT rol_id FROM seg.roles WHERE codigo = N'SUPERVISOR' AND activo = 1);

IF @entorno IS NULL OR @centro IS NULL OR @turno IS NULL OR @rol_operario IS NULL OR @rol_supervisor IS NULL
    THROW 57003, 'Faltan catalogos iniciales.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    INSERT nav.empresas (entorno_nav_id, codigo, nombre, activo)
    VALUES (@entorno, N'ZZTEST_014', N'ZZTEST 014 empresa sintetica', 1);
    DECLARE @empresa bigint = SCOPE_IDENTITY();

    INSERT cfg.lineas (centro_trabajo_id, codigo, nombre, descripcion, activa)
    VALUES (@centro, N'ZZ14-FUNC', N'ZZTEST 014 funcional', N'Sintetica', 1),
           (@centro, N'ZZ14-CONC-A', N'ZZTEST 014 concurrencia A', N'Sintetica', 1),
           (@centro, N'ZZ14-CONC-B', N'ZZTEST 014 concurrencia B', N'Sintetica', 1);

    INSERT seg.empleados (codigo_nav, nombre_completo, activo_nav, activo_mes, sincronizado_nav_utc)
    VALUES (N'ZZ14-OP1', N'ZZTEST 014 Operario 1', 1, 1, SYSUTCDATETIME()),
           (N'ZZ14-OP2', N'ZZTEST 014 Operario 2', 1, 1, SYSUTCDATETIME()),
           (N'ZZ14-SUP', N'ZZTEST 014 Supervisor', 1, 1, SYSUTCDATETIME());
    DECLARE @op1 bigint = (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ14-OP1');
    DECLARE @op2 bigint = (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ14-OP2');
    DECLARE @sup bigint = (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ14-SUP');
    INSERT seg.empleados_roles (empleado_id, rol_id, desde_utc, asignado_por_cuenta, motivo)
    VALUES (@op1, @rol_operario, SYSUTCDATETIME(), N'ZZTEST_014', N'Fixture'),
           (@op2, @rol_operario, SYSUTCDATETIME(), N'ZZTEST_014', N'Fixture'),
           (@sup, @rol_supervisor, SYSUTCDATETIME(), N'ZZTEST_014', N'Fixture');

    INSERT prod.ordenes (empresa_nav_id, numero_orden, producto_codigo, producto_descripcion, producto_barcode, lote, cantidad_objetivo, tiempo_ejecucion_nav_min, modo_trabajo, estado, datos_nav_originales)
    VALUES (@empresa, N'ZZ14-FUNC', N'ZZ14-P', N'ZZTEST 014 producto', N'ZZ14-BC', N'ZZ14-FUNC', 100, 1, N'NORMAL', N'IMPORTADA', N'{"origen":"ZZTEST_014"}'),
           (@empresa, N'ZZ14-CONC', N'ZZ14-P', N'ZZTEST 014 concurrencia', N'ZZ14-BC', N'ZZ14-CONC', 80, 1, N'MULTILINEA', N'IMPORTADA', N'{"origen":"ZZTEST_014"}');
    INSERT prod.formatos_palet_orden (orden_id, codigo_formato, unidades_por_palet, descripcion, es_predeterminado_nav, datos_nav_originales, activo)
    SELECT orden_id, N'ZZ14-FMT', 20, N'ZZTEST 014 formato', 1, N'{"origen":"ZZTEST_014"}', 1 FROM prod.ordenes WHERE numero_orden LIKE N'ZZ14-%';
    INSERT prod.sesiones_linea (orden_id, linea_id, turno_id, formato_palet_orden_id, fecha_operativa, estado, iniciada_utc, cargada_por_empleado_id)
    SELECT o.orden_id, l.linea_id, @turno, f.formato_palet_orden_id, CONVERT(date, SYSUTCDATETIME()), N'PRODUCIENDO', SYSUTCDATETIME(), @sup
    FROM prod.ordenes o JOIN prod.formatos_palet_orden f ON f.orden_id = o.orden_id JOIN cfg.lineas l ON (o.numero_orden = N'ZZ14-FUNC' AND l.codigo = N'ZZ14-FUNC') OR (o.numero_orden = N'ZZ14-CONC' AND l.codigo IN (N'ZZ14-CONC-A', N'ZZ14-CONC-B'));
    INSERT prod.estados_linea (linea_id, sesion_linea_id, estado)
    SELECT l.linea_id, s.sesion_linea_id, N'PRODUCIENDO' FROM cfg.lineas l JOIN prod.sesiones_linea s ON s.linea_id = l.linea_id WHERE l.codigo LIKE N'ZZ14-%';
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

PRINT N'FIXTURES 014 PREPARADOS';
