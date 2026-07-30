/*
Fixtures sinteticos para las pruebas del paquete 011.
Estado: preparado para revision; no ejecutado.
No instala procedimientos ni llama a sistemas externos.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 53000, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF EXISTS (SELECT 1 FROM cfg.lineas WHERE codigo LIKE N'ZZ11-%')
 OR EXISTS (SELECT 1 FROM seg.empleados WHERE codigo_nav LIKE N'ZZ11-%')
 OR EXISTS (SELECT 1 FROM prod.ordenes WHERE numero_orden LIKE N'ZZ11-%')
 OR EXISTS (SELECT 1 FROM nav.empresas WHERE codigo = N'ZZTEST_011')
 OR EXISTS (SELECT 1 FROM cfg.impresoras WHERE codigo = N'ZZ11-PRN')
    THROW 53001, 'Ya existen fixtures ZZTEST_011; revisar la limpieza.', 1;

IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0) <> 37
    THROW 53003, 'El prevuelo requiere exactamente 37 tablas de usuario.', 1;

IF (SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0) <> 11
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
    THROW 53004, 'El paquete 011 no esta instalado de forma completa.', 1;

IF (SELECT COUNT(*) FROM cfg.centros_trabajo) <> 1
 OR (SELECT COUNT(*) FROM cfg.turnos) <> 2
 OR (SELECT COUNT(*) FROM seg.roles) <> 3
 OR (SELECT COUNT(*) FROM nav.entornos) <> 1
 OR (SELECT COUNT(*) FROM [log].motivos_scrap) <> 30
    THROW 53005, 'Los catalogos iniciales no contienen sus 37 registros.', 1;

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
    THROW 53006, 'El prevuelo requiere todas las tablas operativas vacias.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
 OR USER_ID(N'EBIR\MES$') IS NULL
 OR NOT EXISTS
 (
     SELECT 1
     FROM sys.database_role_members drm
     WHERE drm.role_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
       AND drm.member_principal_id = USER_ID(N'EBIR\MES$')
 )
    THROW 53007, 'El runtime o su pertenencia a mes_runtime no son correctos.', 1;

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
    THROW 53002, 'Faltan catalogos iniciales requeridos.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT nav.empresas
    (
        entorno_nav_id, codigo, nombre, activo
    )
    VALUES
    (
        @entorno_nav_id, N'ZZTEST_011',
        N'ZZTEST 011 empresa sintetica', 1
    );

    DECLARE @empresa_nav_id bigint = SCOPE_IDENTITY();

    INSERT cfg.impresoras
    (
        codigo, nombre, modelo, nombre_red,
        direccion_ip, protocolo, resolucion_dpi, activa
    )
    VALUES
    (
        N'ZZ11-PRN', N'ZZTEST 011 impresora simulada',
        N'SIMULADA_SIN_SALIDA', NULL,
        NULL, NULL, NULL, 1
    );

    DECLARE @impresora_id bigint = SCOPE_IDENTITY();

    INSERT cfg.lineas
    (
        centro_trabajo_id, codigo, nombre, descripcion, activa
    )
    VALUES
    (@centro_trabajo_id, N'ZZ11-L01', N'ZZTEST 011 Línea 1', N'Orden normal', 1),
    (@centro_trabajo_id, N'ZZ11-L02', N'ZZTEST 011 Línea 2', N'Conflicto normal', 1),
    (@centro_trabajo_id, N'ZZ11-L03', N'ZZTEST 011 Línea 3', N'Multilínea A', 1),
    (@centro_trabajo_id, N'ZZ11-L04', N'ZZTEST 011 Línea 4', N'Multilínea B', 1),
    (@centro_trabajo_id, N'ZZ11-L05', N'ZZTEST 011 Línea 5', N'Fin de turno', 1),
    (@centro_trabajo_id, N'ZZ11-L06', N'ZZTEST 011 Línea 6', N'Impresión', 1);

    INSERT prod.estados_linea
    (
        linea_id, sesion_linea_id, estado, motivo_bloqueo
    )
    SELECT linea_id, NULL, N'LIBRE', NULL
    FROM cfg.lineas
    WHERE codigo LIKE N'ZZ11-%';

    INSERT cfg.lineas_impresoras
    (
        linea_id, impresora_id, es_principal,
        asignado_desde_utc, asignado_por_cuenta, motivo
    )
    SELECT
        linea_id, @impresora_id, 1,
        SYSUTCDATETIME(), N'ZZTEST_011', N'Fixture sintetico'
    FROM cfg.lineas
    WHERE codigo LIKE N'ZZ11-%';

    INSERT seg.empleados
    (
        codigo_nav, nombre_completo, activo_nav,
        activo_mes, sincronizado_nav_utc
    )
    VALUES
    (N'ZZ11-SUP', N'ZZTEST 011 Supervisor', 1, 1, SYSUTCDATETIME()),
    (N'ZZ11-OP1', N'ZZTEST 011 Operario Uno', 1, 1, SYSUTCDATETIME()),
    (N'ZZ11-OP2', N'ZZTEST 011 Operario Dos', 1, 1, SYSUTCDATETIME()),
    (N'ZZ11-OP3', N'ZZTEST 011 Operario Tres', 1, 1, SYSUTCDATETIME()),
    (N'ZZ11-DUAL', N'ZZTEST 011 Rol Dual', 1, 1, SYSUTCDATETIME());

    DECLARE
        @supervisor_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-SUP'),
        @operario_1_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP1'),
        @operario_2_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP2'),
        @operario_3_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP3'),
        @dual_id bigint =
            (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-DUAL');

    INSERT seg.empleados_roles
    (
        empleado_id, rol_id, desde_utc,
        asignado_por_cuenta, motivo
    )
    VALUES
    (@supervisor_id, @rol_supervisor_id, SYSUTCDATETIME(), N'ZZTEST_011', N'Fixture'),
    (@operario_1_id, @rol_operario_id, SYSUTCDATETIME(), N'ZZTEST_011', N'Fixture'),
    (@operario_2_id, @rol_operario_id, SYSUTCDATETIME(), N'ZZTEST_011', N'Fixture'),
    (@operario_3_id, @rol_operario_id, SYSUTCDATETIME(), N'ZZTEST_011', N'Fixture'),
    (@dual_id, @rol_operario_id, SYSUTCDATETIME(), N'ZZTEST_011', N'Fixture'),
    (@dual_id, @rol_supervisor_id, SYSUTCDATETIME(), N'ZZTEST_011', N'Fixture');

    DECLARE @ordenes TABLE
    (
        numero_orden nvarchar(30) NOT NULL,
        modo_trabajo nvarchar(20) NOT NULL,
        cantidad_objetivo int NOT NULL,
        descripcion nvarchar(250) NOT NULL
    );

    INSERT @ordenes
    VALUES
    (N'ZZ11-FL-NORMAL', N'NORMAL', 100, N'ZZTEST 011 orden normal'),
    (N'ZZ11-FL-MULTI', N'MULTILINEA', 100, N'ZZTEST 011 orden multilínea'),
    (N'ZZ11-FL-TURNO', N'NORMAL', 60, N'ZZTEST 011 fin de turno'),
    (N'ZZ11-FL-PRINT', N'NORMAL', 40, N'ZZTEST 011 desbloqueo impresión');

    INSERT prod.ordenes
    (
        empresa_nav_id, numero_orden,
        producto_codigo, producto_descripcion, producto_barcode,
        lote, cantidad_objetivo, tiempo_ejecucion_nav_min,
        modo_trabajo, estado, datos_nav_originales
    )
    SELECT
        @empresa_nav_id, numero_orden,
        N'ZZ11-PROD', descripcion, N'ZZ11-NO-GS1',
        numero_orden, cantidad_objetivo, 2.0,
        modo_trabajo, N'IMPORTADA',
        N'{"origen":"ZZTEST_011","nav_real":false}'
    FROM @ordenes;

    INSERT prod.formatos_palet_orden
    (
        orden_id, codigo_formato, unidades_por_palet,
        descripcion, es_predeterminado_nav,
        datos_nav_originales, activo
    )
    SELECT
        orden_id, N'ZZ11-FMT-20', 20,
        N'ZZTEST 011 formato de 20 unidades', 1,
        N'{"origen":"ZZTEST_011"}', 1
    FROM prod.ordenes
    WHERE numero_orden LIKE N'ZZ11-%';

    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT N'empresas' entidad, COUNT(*) cantidad
FROM nav.empresas WHERE codigo = N'ZZTEST_011'
UNION ALL
SELECT N'impresoras', COUNT(*)
FROM cfg.impresoras WHERE codigo = N'ZZ11-PRN'
UNION ALL
SELECT N'lineas', COUNT(*)
FROM cfg.lineas WHERE codigo LIKE N'ZZ11-%'
UNION ALL
SELECT N'estados_linea', COUNT(*)
FROM prod.estados_linea e
JOIN cfg.lineas l ON l.linea_id = e.linea_id
WHERE l.codigo LIKE N'ZZ11-%'
UNION ALL
SELECT N'empleados', COUNT(*)
FROM seg.empleados WHERE codigo_nav LIKE N'ZZ11-%'
UNION ALL
SELECT N'roles', COUNT(*)
FROM seg.empleados_roles er
JOIN seg.empleados e ON e.empleado_id = er.empleado_id
WHERE e.codigo_nav LIKE N'ZZ11-%'
UNION ALL
SELECT N'ordenes', COUNT(*)
FROM prod.ordenes WHERE numero_orden LIKE N'ZZ11-%'
UNION ALL
SELECT N'formatos', COUNT(*)
FROM prod.formatos_palet_orden f
JOIN prod.ordenes o ON o.orden_id = f.orden_id
WHERE o.numero_orden LIKE N'ZZ11-%'
UNION ALL
SELECT N'sesiones_iniciales', COUNT(*)
FROM prod.sesiones_linea s
JOIN prod.ordenes o ON o.orden_id = s.orden_id
WHERE o.numero_orden LIKE N'ZZ11-%'
UNION ALL
SELECT N'rfid', COUNT(*)
FROM seg.credenciales_rfid r
JOIN seg.empleados e ON e.empleado_id = r.empleado_id
WHERE e.codigo_nav LIKE N'ZZ11-%'
UNION ALL
SELECT N'dispositivos', COUNT(*)
FROM cfg.lineas_dispositivos d
JOIN cfg.lineas l ON l.linea_id = d.linea_id
WHERE l.codigo LIKE N'ZZ11-%';

PRINT N'FIXTURES 011 PREPARADOS';
