/*
Fixtures sinteticos para las pruebas del paquete 012.
Estado: preparado para revision; no ejecutado.
No instala procedimientos ni llama a sistemas externos.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 54000, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF EXISTS (SELECT 1 FROM cfg.lineas WHERE codigo LIKE N'ZZ12-%')
 OR EXISTS (SELECT 1 FROM seg.empleados WHERE codigo_nav LIKE N'ZZ12-%')
 OR EXISTS (SELECT 1 FROM prod.ordenes WHERE numero_orden LIKE N'ZZ12-%')
 OR EXISTS (SELECT 1 FROM nav.empresas WHERE codigo = N'ZZTEST_012')
 OR EXISTS (SELECT 1 FROM cfg.impresoras WHERE codigo = N'ZZ12-PRN')
    THROW 54001, 'Ya existen fixtures ZZTEST_012; revisar la limpieza.', 1;

IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0) <> 37
    THROW 54003, 'El prevuelo requiere exactamente 37 tablas de usuario.', 1;

IF (SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0) <> 16
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
 OR OBJECT_ID(N'prod.recursos_efectivos_sesion', N'IF') IS NULL
    THROW 54004, 'El paquete 012 no esta instalado de forma completa.', 1;

IF (SELECT COUNT(*) FROM cfg.centros_trabajo) <> 1
 OR (SELECT COUNT(*) FROM cfg.turnos) <> 2
 OR (SELECT COUNT(*) FROM seg.roles) <> 3
 OR (SELECT COUNT(*) FROM nav.entornos) <> 1
 OR (SELECT COUNT(*) FROM [log].motivos_scrap) <> 30
    THROW 54005, 'Los catalogos iniciales no contienen sus 37 registros.', 1;

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
      (SCHEMA_NAME(t.schema_id) = N'cfg' AND t.name IN (N'centros_trabajo', N'turnos'))
      OR (SCHEMA_NAME(t.schema_id) = N'seg' AND t.name = N'roles')
      OR (SCHEMA_NAME(t.schema_id) = N'nav' AND t.name = N'entornos')
      OR (SCHEMA_NAME(t.schema_id) = N'log' AND t.name = N'motivos_scrap')
  )
ORDER BY SCHEMA_NAME(t.schema_id), t.name;

EXEC sys.sp_executesql
    @sql_prevuelo,
    N'@total bigint OUTPUT',
    @total = @filas_operativas OUTPUT;

IF @filas_operativas <> 0
    THROW 54006, 'El prevuelo requiere todas las tablas operativas vacias.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
 OR USER_ID(N'EBIR\MES$') IS NULL
 OR NOT EXISTS
 (
     SELECT 1
     FROM sys.database_role_members drm
     WHERE drm.role_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
       AND drm.member_principal_id = USER_ID(N'EBIR\MES$')
 )
    THROW 54007, 'El runtime o su pertenencia a mes_runtime no son correctos.', 1;

DECLARE
    @entorno_nav_id smallint =
        (SELECT entorno_nav_id FROM nav.entornos WHERE codigo = N'EBIRTEST'),
    @centro_trabajo_id bigint =
        (SELECT centro_trabajo_id FROM cfg.centros_trabajo WHERE codigo = N'CT-01'),
    @rol_operario_id smallint =
        (SELECT rol_id FROM seg.roles WHERE codigo = N'OPERARIO' AND activo = 1),
    @rol_supervisor_id smallint =
        (SELECT rol_id FROM seg.roles WHERE codigo = N'SUPERVISOR' AND activo = 1);

IF @entorno_nav_id IS NULL OR @centro_trabajo_id IS NULL
 OR @rol_operario_id IS NULL OR @rol_supervisor_id IS NULL
    THROW 54002, 'Faltan catalogos iniciales requeridos.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT nav.empresas
    (
        entorno_nav_id, codigo, nombre, activo
    )
    VALUES
    (
        @entorno_nav_id, N'ZZTEST_012',
        N'ZZTEST 012 empresa sintetica', 1
    );

    DECLARE @empresa_nav_id bigint = SCOPE_IDENTITY();

    INSERT cfg.impresoras
    (
        codigo, nombre, modelo, nombre_red,
        direccion_ip, protocolo, resolucion_dpi, activa
    )
    VALUES
    (
        N'ZZ12-PRN', N'ZZTEST 012 impresora simulada',
        N'SIMULADA_SIN_SALIDA', NULL,
        NULL, NULL, NULL, 1
    );

    DECLARE @impresora_id bigint = SCOPE_IDENTITY();

    INSERT cfg.lineas
    (
        centro_trabajo_id, codigo, nombre, descripcion, activa
    )
    VALUES
    (@centro_trabajo_id, N'ZZ12-L01', N'ZZTEST 012 LÃ­nea 1', N'Orden normal', 1),
    (@centro_trabajo_id, N'ZZ12-L02', N'ZZTEST 012 LÃ­nea 2', N'Conflicto normal', 1),
    (@centro_trabajo_id, N'ZZ12-L03', N'ZZTEST 012 LÃ­nea 3', N'MultilÃ­nea A', 1),
    (@centro_trabajo_id, N'ZZ12-L04', N'ZZTEST 012 LÃ­nea 4', N'MultilÃ­nea B', 1),
    (@centro_trabajo_id, N'ZZ12-L05', N'ZZTEST 012 LÃ­nea 5', N'Fin de turno', 1),
    (@centro_trabajo_id, N'ZZ12-L06', N'ZZTEST 012 LÃ­nea 6', N'ImpresiÃ³n', 1);

    INSERT prod.estados_linea
    (
        linea_id, sesion_linea_id, estado, motivo_bloqueo
    )
    SELECT linea_id, NULL, N'LIBRE', NULL
    FROM cfg.lineas
    WHERE codigo LIKE N'ZZ12-%';

    INSERT cfg.lineas_impresoras
    (
        linea_id, impresora_id, es_principal,
        asignado_desde_utc, asignado_por_cuenta, motivo
    )
    SELECT
        linea_id, @impresora_id, 1,
        SYSUTCDATETIME(), N'ZZTEST_012', N'Fixture sintetico'
    FROM cfg.lineas
    WHERE codigo LIKE N'ZZ12-%';

    INSERT seg.empleados
    (
        codigo_nav, nombre_completo, activo_nav,
        activo_mes, sincronizado_nav_utc
    )
    VALUES
    (N'ZZ12-SUP', N'ZZTEST 012 Supervisor', 1, 1, SYSUTCDATETIME()),
    (N'ZZ12-SUP2', N'ZZTEST 012 Supervisor Dos', 1, 1, SYSUTCDATETIME()),
    (N'ZZ12-OP1', N'ZZTEST 012 Operario Uno', 1, 1, SYSUTCDATETIME()),
    (N'ZZ12-OP2', N'ZZTEST 012 Operario Dos', 1, 1, SYSUTCDATETIME()),
    (N'ZZ12-OP3', N'ZZTEST 012 Operario Tres', 1, 1, SYSUTCDATETIME()),
    (N'ZZ12-DUAL', N'ZZTEST 012 Rol Dual', 1, 1, SYSUTCDATETIME());

    DECLARE
        @supervisor_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-SUP'),
        @supervisor_2_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-SUP2'),
        @operario_1_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-OP1'),
        @operario_2_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-OP2'),
        @operario_3_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-OP3'),
        @dual_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-DUAL');

    INSERT seg.empleados_roles
    (
        empleado_id, rol_id, desde_utc,
        asignado_por_cuenta, motivo
    )
    VALUES
    (@supervisor_id, @rol_supervisor_id, SYSUTCDATETIME(), N'ZZTEST_012', N'Fixture'),
    (@supervisor_2_id, @rol_supervisor_id, SYSUTCDATETIME(), N'ZZTEST_012', N'Fixture'),
    (@operario_1_id, @rol_operario_id, SYSUTCDATETIME(), N'ZZTEST_012', N'Fixture'),
    (@operario_2_id, @rol_operario_id, SYSUTCDATETIME(), N'ZZTEST_012', N'Fixture'),
    (@operario_3_id, @rol_operario_id, SYSUTCDATETIME(), N'ZZTEST_012', N'Fixture'),
    (@dual_id, @rol_operario_id, SYSUTCDATETIME(), N'ZZTEST_012', N'Fixture'),
    (@dual_id, @rol_supervisor_id, SYSUTCDATETIME(), N'ZZTEST_012', N'Fixture');

    DECLARE @ordenes TABLE
    (
        numero_orden nvarchar(30) NOT NULL,
        modo_trabajo nvarchar(20) NOT NULL,
        cantidad_objetivo int NOT NULL,
        descripcion nvarchar(250) NOT NULL
    );

    INSERT @ordenes
    VALUES
    (N'ZZ12-FL-NORMAL', N'NORMAL', 100, N'ZZTEST 012 orden normal'),
    (N'ZZ12-FL-MULTI', N'MULTILINEA', 100, N'ZZTEST 012 orden multilÃ­nea'),
    (N'ZZ12-FL-TURNO', N'NORMAL', 60, N'ZZTEST 012 fin de turno'),
    (N'ZZ12-FL-PRINT', N'NORMAL', 40, N'ZZTEST 012 desbloqueo impresiÃ³n');

    INSERT prod.ordenes
    (
        empresa_nav_id, numero_orden,
        producto_codigo, producto_descripcion, producto_barcode,
        lote, cantidad_objetivo, tiempo_ejecucion_nav_min,
        modo_trabajo, estado, datos_nav_originales
    )
    SELECT
        @empresa_nav_id, numero_orden,
        N'ZZ12-PROD', descripcion, N'ZZ12-NO-GS1',
        numero_orden, cantidad_objetivo, 2.0,
        modo_trabajo, N'IMPORTADA',
        N'{"origen":"ZZTEST_012","nav_real":false}'
    FROM @ordenes;

    INSERT prod.formatos_palet_orden
    (
        orden_id, codigo_formato, unidades_por_palet,
        descripcion, es_predeterminado_nav,
        datos_nav_originales, activo
    )
    SELECT
        orden_id, N'ZZ12-FMT-20', 20,
        N'ZZTEST 012 formato de 20 unidades', 1,
        N'{"origen":"ZZTEST_012"}', 1
    FROM prod.ordenes
    WHERE numero_orden LIKE N'ZZ12-%';

    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

IF (SELECT COUNT(*) FROM nav.empresas WHERE codigo = N'ZZTEST_012') <> 1
 OR (SELECT COUNT(*) FROM cfg.impresoras WHERE codigo = N'ZZ12-PRN') <> 1
 OR (SELECT COUNT(*) FROM cfg.lineas WHERE codigo LIKE N'ZZ12-%') <> 6
 OR
 (
     SELECT COUNT(*)
     FROM prod.estados_linea e
     JOIN cfg.lineas l ON l.linea_id = e.linea_id
     WHERE l.codigo LIKE N'ZZ12-%'
       AND e.estado = N'LIBRE'
       AND e.sesion_linea_id IS NULL
 ) <> 6
 OR (SELECT COUNT(*) FROM seg.empleados WHERE codigo_nav LIKE N'ZZ12-%') <> 6
 OR
 (
     SELECT COUNT(*)
     FROM seg.empleados_roles er
     JOIN seg.empleados e ON e.empleado_id = er.empleado_id
     WHERE e.codigo_nav LIKE N'ZZ12-%'
       AND er.hasta_utc IS NULL
 ) <> 7
 OR (SELECT COUNT(*) FROM prod.ordenes WHERE numero_orden LIKE N'ZZ12-%') <> 4
 OR
 (
     SELECT COUNT(*)
     FROM prod.formatos_palet_orden f
     JOIN prod.ordenes o ON o.orden_id = f.orden_id
     WHERE o.numero_orden LIKE N'ZZ12-%'
 ) <> 4
    THROW 54008, 'La cardinalidad de los fixtures 012 no es la esperada.', 1;

IF EXISTS
(
    SELECT 1
    FROM prod.sesiones_linea s
    JOIN prod.ordenes o ON o.orden_id = s.orden_id
    WHERE o.numero_orden LIKE N'ZZ12-%'
)
 OR EXISTS
(
    SELECT 1
    FROM seg.credenciales_rfid r
    JOIN seg.empleados e ON e.empleado_id = r.empleado_id
    WHERE e.codigo_nav LIKE N'ZZ12-%'
)
 OR EXISTS
(
    SELECT 1
    FROM cfg.lineas_dispositivos d
    JOIN cfg.lineas l ON l.linea_id = d.linea_id
    WHERE l.codigo LIKE N'ZZ12-%'
)
    THROW 54009, 'Los fixtures no deben crear sesiones, RFID ni dispositivos.', 1;

SELECT N'empresas' entidad, COUNT(*) cantidad
FROM nav.empresas WHERE codigo = N'ZZTEST_012'
UNION ALL
SELECT N'impresoras', COUNT(*)
FROM cfg.impresoras WHERE codigo = N'ZZ12-PRN'
UNION ALL
SELECT N'lineas', COUNT(*)
FROM cfg.lineas WHERE codigo LIKE N'ZZ12-%'
UNION ALL
SELECT N'estados_linea', COUNT(*)
FROM prod.estados_linea e
JOIN cfg.lineas l ON l.linea_id = e.linea_id
WHERE l.codigo LIKE N'ZZ12-%'
UNION ALL
SELECT N'empleados', COUNT(*)
FROM seg.empleados WHERE codigo_nav LIKE N'ZZ12-%'
UNION ALL
SELECT N'roles', COUNT(*)
FROM seg.empleados_roles er
JOIN seg.empleados e ON e.empleado_id = er.empleado_id
WHERE e.codigo_nav LIKE N'ZZ12-%'
UNION ALL
SELECT N'ordenes', COUNT(*)
FROM prod.ordenes WHERE numero_orden LIKE N'ZZ12-%'
UNION ALL
SELECT N'formatos', COUNT(*)
FROM prod.formatos_palet_orden f
JOIN prod.ordenes o ON o.orden_id = f.orden_id
WHERE o.numero_orden LIKE N'ZZ12-%'
UNION ALL
SELECT N'sesiones_iniciales', COUNT(*)
FROM prod.sesiones_linea s
JOIN prod.ordenes o ON o.orden_id = s.orden_id
WHERE o.numero_orden LIKE N'ZZ12-%'
UNION ALL
SELECT N'rfid', COUNT(*)
FROM seg.credenciales_rfid r
JOIN seg.empleados e ON e.empleado_id = r.empleado_id
WHERE e.codigo_nav LIKE N'ZZ12-%'
UNION ALL
SELECT N'dispositivos', COUNT(*)
FROM cfg.lineas_dispositivos d
JOIN cfg.lineas l ON l.linea_id = d.linea_id
WHERE l.codigo LIKE N'ZZ12-%';

PRINT N'FIXTURES 012 PREPARADOS';

