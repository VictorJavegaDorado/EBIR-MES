/*
Fixtures sinteticos para las pruebas del paquete 013.
Estado: preparado para revision estatica; no ejecutado.
No instala procedimientos ni llama a sistemas externos.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 56000, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF EXISTS (SELECT 1 FROM nav.empresas WHERE codigo = N'ZZTEST_013')
 OR EXISTS (SELECT 1 FROM cfg.lineas WHERE codigo LIKE N'ZZ13-%')
 OR EXISTS (SELECT 1 FROM seg.empleados WHERE codigo_nav LIKE N'ZZ13-%')
 OR EXISTS (SELECT 1 FROM prod.ordenes WHERE numero_orden LIKE N'ZZ13-%')
    THROW 56001, 'Ya existen fixtures ZZTEST_013 o ZZ13-; revisar la limpieza.', 1;

IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0) <> 37
    THROW 56002, 'El prevuelo requiere exactamente 37 tablas de usuario.', 1;

IF (SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0) <> 20
 OR OBJECT_ID(N'aud.registrar_evento', N'P') IS NULL
 OR OBJECT_ID(N'prod.reservar_palet', N'P') IS NULL
 OR OBJECT_ID(N'prod.cancelar_reserva_palet', N'P') IS NULL
 OR OBJECT_ID(N'prod.cerrar_palet', N'P') IS NULL
 OR OBJECT_ID(N'nav.confirmar_salida_palet', N'P') IS NULL
 OR OBJECT_ID(N'imp.confirmar_trabajo_impresion', N'P') IS NULL
 OR OBJECT_ID(N'prod.abrir_sesion_linea', N'P') IS NULL
 OR OBJECT_ID(N'prod.registrar_entrada_productiva', N'P') IS NULL
 OR OBJECT_ID(N'prod.registrar_salida_productiva', N'P') IS NULL
 OR OBJECT_ID(N'prod.marcar_cambio_turno_pendiente', N'P') IS NULL
 OR OBJECT_ID(N'prod.finalizar_sesion_turno', N'P') IS NULL
 OR OBJECT_ID(N'prod.iniciar_paro_operario', N'P') IS NULL
 OR OBJECT_ID(N'prod.finalizar_paro_operario', N'P') IS NULL
 OR OBJECT_ID(N'prod.iniciar_sustitucion_capacidad', N'P') IS NULL
 OR OBJECT_ID(N'prod.finalizar_sustitucion_capacidad', N'P') IS NULL
 OR OBJECT_ID(N'prod.corregir_fichaje_turno_actual', N'P') IS NULL
 OR OBJECT_ID(N'log.registrar_scrap', N'P') IS NULL
 OR OBJECT_ID(N'log.revisar_scrap', N'P') IS NULL
 OR OBJECT_ID(N'log.crear_solicitud_reaprovisionamiento', N'P') IS NULL
 OR OBJECT_ID(N'log.transicionar_solicitud_reaprovisionamiento', N'P') IS NULL
 OR OBJECT_ID(N'prod.recursos_efectivos_sesion', N'IF') IS NULL
    THROW 56003, 'El paquete 013 no esta instalado de forma completa.', 1;

IF (SELECT COUNT(*) FROM cfg.centros_trabajo) <> 1
 OR (SELECT COUNT(*) FROM cfg.turnos) <> 2
 OR (SELECT COUNT(*) FROM seg.roles) <> 3
 OR (SELECT COUNT(*) FROM nav.entornos) <> 1
 OR (SELECT COUNT(*) FROM [log].motivos_scrap) <> 30
    THROW 56004, 'Los catalogos iniciales no contienen sus 37 registros.', 1;

DECLARE
    @filas_operativas bigint = 0,
    @sql_prevuelo nvarchar(max) = N'SET @total = 0;';

SELECT @sql_prevuelo = @sql_prevuelo
    + N'SELECT @total = @total + COUNT_BIG(*) FROM '
    + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N';'
FROM sys.tables t
WHERE t.is_ms_shipped = 0
  AND NOT
  (
      (SCHEMA_NAME(t.schema_id) = N'cfg'
       AND t.name IN (N'centros_trabajo', N'turnos'))
      OR (SCHEMA_NAME(t.schema_id) = N'seg' AND t.name = N'roles')
      OR (SCHEMA_NAME(t.schema_id) = N'nav' AND t.name = N'entornos')
      OR (SCHEMA_NAME(t.schema_id) = N'log'
          AND t.name = N'motivos_scrap')
  )
ORDER BY SCHEMA_NAME(t.schema_id), t.name;

EXEC sys.sp_executesql
    @sql_prevuelo,
    N'@total bigint OUTPUT',
    @total = @filas_operativas OUTPUT;

IF @filas_operativas <> 0
    THROW 56005, 'El prevuelo requiere todas las tablas operativas vacias.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
 OR USER_ID(N'EBIR\MES$') IS NULL
 OR NOT EXISTS
 (
     SELECT 1
     FROM sys.database_role_members drm
     WHERE drm.role_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
       AND drm.member_principal_id = USER_ID(N'EBIR\MES$')
 )
    THROW 56006, 'El runtime o su pertenencia a mes_runtime no son correctos.', 1;

DECLARE
    @entorno_nav_id smallint =
        (SELECT entorno_nav_id FROM nav.entornos WHERE codigo = N'EBIRTEST'),
    @centro_trabajo_id bigint =
        (SELECT centro_trabajo_id FROM cfg.centros_trabajo WHERE codigo = N'CT-01'),
    @rol_operario_id smallint =
        (SELECT rol_id FROM seg.roles WHERE codigo = N'OPERARIO' AND activo = 1),
    @rol_supervisor_id smallint =
        (SELECT rol_id FROM seg.roles WHERE codigo = N'SUPERVISOR' AND activo = 1),
    @rol_aprovisionador_id smallint =
        (SELECT rol_id FROM seg.roles WHERE codigo = N'APROVISIONADOR' AND activo = 1);

IF @entorno_nav_id IS NULL
 OR @centro_trabajo_id IS NULL
 OR @rol_operario_id IS NULL
 OR @rol_supervisor_id IS NULL
 OR @rol_aprovisionador_id IS NULL
    THROW 56007, 'Faltan catalogos iniciales requeridos.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT nav.empresas
    (
        entorno_nav_id, codigo, nombre, activo
    )
    VALUES
    (
        @entorno_nav_id, N'ZZTEST_013',
        N'ZZTEST 013 empresa sintetica', 1
    );

    DECLARE @empresa_nav_id bigint = SCOPE_IDENTITY();

    INSERT cfg.lineas
    (
        centro_trabajo_id, codigo, nombre, descripcion, activa
    )
    VALUES
    (@centro_trabajo_id, N'ZZ13-L01', N'ZZTEST 013 Linea 1', N'Scrap principal', 1),
    (@centro_trabajo_id, N'ZZ13-L02', N'ZZTEST 013 Linea 2', N'Validaciones', 1),
    (@centro_trabajo_id, N'ZZ13-L03', N'ZZTEST 013 Linea 3', N'Concurrencia A', 1),
    (@centro_trabajo_id, N'ZZ13-L04', N'ZZTEST 013 Linea 4', N'Concurrencia B', 1);

    INSERT prod.estados_linea
    (
        linea_id, sesion_linea_id, estado, motivo_bloqueo
    )
    SELECT linea_id, NULL, N'LIBRE', NULL
    FROM cfg.lineas
    WHERE codigo LIKE N'ZZ13-%';

    INSERT seg.empleados
    (
        codigo_nav, nombre_completo, activo_nav,
        activo_mes, sincronizado_nav_utc
    )
    VALUES
    (N'ZZ13-SUP1', N'ZZTEST 013 Supervisor Uno', 1, 1, SYSUTCDATETIME()),
    (N'ZZ13-SUP2', N'ZZTEST 013 Supervisor Dos', 1, 1, SYSUTCDATETIME()),
    (N'ZZ13-OP1', N'ZZTEST 013 Operario Uno', 1, 1, SYSUTCDATETIME()),
    (N'ZZ13-OP2', N'ZZTEST 013 Operario Dos', 1, 1, SYSUTCDATETIME()),
    (N'ZZ13-APR1', N'ZZTEST 013 Aprovisionador Uno', 1, 1, SYSUTCDATETIME()),
    (N'ZZ13-APR2', N'ZZTEST 013 Aprovisionador Dos', 1, 1, SYSUTCDATETIME()),
    (N'ZZ13-SINROL', N'ZZTEST 013 Empleado Sin Rol', 1, 1, SYSUTCDATETIME());

    DECLARE
        @supervisor_1_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-SUP1'),
        @supervisor_2_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-SUP2'),
        @operario_1_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-OP1'),
        @operario_2_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-OP2'),
        @aprovisionador_1_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-APR1'),
        @aprovisionador_2_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ13-APR2');

    INSERT seg.empleados_roles
    (
        empleado_id, rol_id, desde_utc,
        asignado_por_cuenta, motivo
    )
    VALUES
    (@supervisor_1_id, @rol_supervisor_id, SYSUTCDATETIME(), N'ZZTEST_013', N'Fixture'),
    (@supervisor_2_id, @rol_supervisor_id, SYSUTCDATETIME(), N'ZZTEST_013', N'Fixture'),
    (@operario_1_id, @rol_operario_id, SYSUTCDATETIME(), N'ZZTEST_013', N'Fixture'),
    (@operario_2_id, @rol_operario_id, SYSUTCDATETIME(), N'ZZTEST_013', N'Fixture'),
    (@aprovisionador_1_id, @rol_aprovisionador_id, SYSUTCDATETIME(), N'ZZTEST_013', N'Fixture'),
    (@aprovisionador_2_id, @rol_aprovisionador_id, SYSUTCDATETIME(), N'ZZTEST_013', N'Fixture');

    DECLARE @ordenes TABLE
    (
        numero_orden nvarchar(30) NOT NULL,
        producto_codigo nvarchar(50) NOT NULL,
        descripcion nvarchar(250) NOT NULL,
        modo_trabajo nvarchar(20) NOT NULL,
        cantidad_objetivo int NOT NULL
    );

    INSERT @ordenes
    VALUES
    (N'ZZ13-FL-MAIN', N'ZZ13-PROD-MAIN', N'ZZTEST 013 orden principal', N'NORMAL', 100),
    (N'ZZ13-FL-AUX', N'ZZ13-PROD-AUX', N'ZZTEST 013 orden auxiliar', N'NORMAL', 80),
    (N'ZZ13-FL-CONC', N'ZZ13-PROD-CONC', N'ZZTEST 013 orden concurrente', N'MULTILINEA', 120);

    INSERT prod.ordenes
    (
        empresa_nav_id, numero_orden,
        producto_codigo, producto_descripcion, producto_barcode,
        lote, cantidad_objetivo, tiempo_ejecucion_nav_min,
        modo_trabajo, estado, datos_nav_originales
    )
    SELECT
        @empresa_nav_id, numero_orden,
        producto_codigo, descripcion, CONCAT(N'ZZ13-BC-', producto_codigo),
        numero_orden, cantidad_objetivo, 2.0,
        modo_trabajo, N'IMPORTADA',
        N'{"origen":"ZZTEST_013","nav_real":false}'
    FROM @ordenes;

    INSERT prod.formatos_palet_orden
    (
        orden_id, codigo_formato, unidades_por_palet,
        descripcion, es_predeterminado_nav,
        datos_nav_originales, activo
    )
    SELECT
        orden_id, N'ZZ13-FMT-20', 20,
        N'ZZTEST 013 formato de 20 unidades', 1,
        N'{"origen":"ZZTEST_013"}', 1
    FROM prod.ordenes
    WHERE numero_orden LIKE N'ZZ13-%';

    INSERT nav.componentes_orden
    (
        orden_id, codigo_componente, descripcion,
        unidad_medida, cantidad_teorica, datos_nav_originales
    )
    SELECT
        o.orden_id,
        CONCAT(N'ZZ13-COMP-A-', RIGHT(o.numero_orden, 4)),
        CONCAT(N'ZZTEST 013 componente A de ', o.numero_orden),
        N'UD', CONVERT(decimal(18,4), 1),
        N'{"origen":"ZZTEST_013","nav_real":false}'
    FROM prod.ordenes o
    WHERE o.numero_orden LIKE N'ZZ13-%'
    UNION ALL
    SELECT
        o.orden_id,
        CONCAT(N'ZZ13-COMP-B-', RIGHT(o.numero_orden, 4)),
        CONCAT(N'ZZTEST 013 componente B de ', o.numero_orden),
        N'UD', CONVERT(decimal(18,4), 2),
        N'{"origen":"ZZTEST_013","nav_real":false}'
    FROM prod.ordenes o
    WHERE o.numero_orden LIKE N'ZZ13-%';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

IF (SELECT COUNT(*) FROM nav.empresas WHERE codigo = N'ZZTEST_013') <> 1
 OR (SELECT COUNT(*) FROM cfg.lineas WHERE codigo LIKE N'ZZ13-%') <> 4
 OR
 (
     SELECT COUNT(*)
     FROM prod.estados_linea e
     JOIN cfg.lineas l ON l.linea_id = e.linea_id
     WHERE l.codigo LIKE N'ZZ13-%'
       AND e.estado = N'LIBRE'
       AND e.sesion_linea_id IS NULL
 ) <> 4
 OR (SELECT COUNT(*) FROM seg.empleados WHERE codigo_nav LIKE N'ZZ13-%') <> 7
 OR
 (
     SELECT COUNT(*)
     FROM seg.empleados_roles er
     JOIN seg.empleados e ON e.empleado_id = er.empleado_id
     WHERE e.codigo_nav LIKE N'ZZ13-%'
       AND er.hasta_utc IS NULL
 ) <> 6
 OR (SELECT COUNT(*) FROM prod.ordenes WHERE numero_orden LIKE N'ZZ13-%') <> 3
 OR
 (
     SELECT COUNT(*)
     FROM prod.formatos_palet_orden f
     JOIN prod.ordenes o ON o.orden_id = f.orden_id
     WHERE o.numero_orden LIKE N'ZZ13-%'
 ) <> 3
 OR
 (
     SELECT COUNT(*)
     FROM nav.componentes_orden c
     JOIN prod.ordenes o ON o.orden_id = c.orden_id
     WHERE o.numero_orden LIKE N'ZZ13-%'
 ) <> 6
    THROW 56008, 'La cardinalidad de los fixtures 013 no es la esperada.', 1;

IF EXISTS
(
    SELECT 1
    FROM prod.sesiones_linea s
    JOIN prod.ordenes o ON o.orden_id = s.orden_id
    WHERE o.numero_orden LIKE N'ZZ13-%'
)
 OR EXISTS
(
    SELECT 1
    FROM seg.credenciales_rfid r
    JOIN seg.empleados e ON e.empleado_id = r.empleado_id
    WHERE e.codigo_nav LIKE N'ZZ13-%'
)
 OR EXISTS
(
    SELECT 1
    FROM cfg.lineas_dispositivos d
    JOIN cfg.lineas l ON l.linea_id = d.linea_id
    WHERE l.codigo LIKE N'ZZ13-%'
)
 OR EXISTS
(
    SELECT 1
    FROM cfg.lineas_impresoras li
    JOIN cfg.lineas l ON l.linea_id = li.linea_id
    WHERE l.codigo LIKE N'ZZ13-%'
)
 OR EXISTS
(
    SELECT 1
    FROM cfg.impresoras
    WHERE codigo LIKE N'ZZ13-%'
)
    THROW 56009, 'Los fixtures no deben crear sesiones, RFID, dispositivos ni impresoras.', 1;

SELECT N'empresas' entidad, COUNT(*) cantidad
FROM nav.empresas WHERE codigo = N'ZZTEST_013'
UNION ALL
SELECT N'lineas', COUNT(*)
FROM cfg.lineas WHERE codigo LIKE N'ZZ13-%'
UNION ALL
SELECT N'estados_linea', COUNT(*)
FROM prod.estados_linea e
JOIN cfg.lineas l ON l.linea_id = e.linea_id
WHERE l.codigo LIKE N'ZZ13-%'
UNION ALL
SELECT N'empleados', COUNT(*)
FROM seg.empleados WHERE codigo_nav LIKE N'ZZ13-%'
UNION ALL
SELECT N'roles', COUNT(*)
FROM seg.empleados_roles er
JOIN seg.empleados e ON e.empleado_id = er.empleado_id
WHERE e.codigo_nav LIKE N'ZZ13-%'
UNION ALL
SELECT N'ordenes', COUNT(*)
FROM prod.ordenes WHERE numero_orden LIKE N'ZZ13-%'
UNION ALL
SELECT N'formatos', COUNT(*)
FROM prod.formatos_palet_orden f
JOIN prod.ordenes o ON o.orden_id = f.orden_id
WHERE o.numero_orden LIKE N'ZZ13-%'
UNION ALL
SELECT N'componentes', COUNT(*)
FROM nav.componentes_orden c
JOIN prod.ordenes o ON o.orden_id = c.orden_id
WHERE o.numero_orden LIKE N'ZZ13-%'
UNION ALL
SELECT N'sesiones_iniciales', COUNT(*)
FROM prod.sesiones_linea s
JOIN prod.ordenes o ON o.orden_id = s.orden_id
WHERE o.numero_orden LIKE N'ZZ13-%'
UNION ALL
SELECT N'rfid', COUNT(*)
FROM seg.credenciales_rfid r
JOIN seg.empleados e ON e.empleado_id = r.empleado_id
WHERE e.codigo_nav LIKE N'ZZ13-%'
UNION ALL
SELECT N'dispositivos', COUNT(*)
FROM cfg.lineas_dispositivos d
JOIN cfg.lineas l ON l.linea_id = d.linea_id
WHERE l.codigo LIKE N'ZZ13-%'
UNION ALL
SELECT N'impresoras', COUNT(*)
FROM cfg.impresoras WHERE codigo LIKE N'ZZ13-%';

PRINT N'FIXTURES 013 PREPARADOS';

