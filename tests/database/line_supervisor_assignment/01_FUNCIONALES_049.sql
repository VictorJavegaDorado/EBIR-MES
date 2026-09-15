/* Prueba transaccional 049. No ejecutar sin autorizacion. */
SET NOCOUNT ON;
/* XACT_ABORT OFF: las violaciones de restriccion esperadas se capturan sin
   condenar la transaccion exterior, que siempre termina en ROLLBACK. */
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 58900, 'Prueba permitida unicamente en EBIR_MES_TEST.', 1;
IF OBJECT_ID(N'cfg.lineas_jefes', N'U') IS NULL
    THROW 58901, 'El paquete 049A no esta instalado.', 1;
IF EXISTS (SELECT 1 FROM cfg.lineas WHERE codigo LIKE N'ZZ49-%')
 OR EXISTS (SELECT 1 FROM seg.empleados WHERE codigo_nav LIKE N'ZZ49-%')
    THROW 58902, 'Existen fixtures ZZ49 pendientes de revision.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE
        @centro_id bigint =
            (SELECT TOP (1) centro_trabajo_id FROM cfg.centros_trabajo ORDER BY centro_trabajo_id),
        @rol_supervisor_id smallint =
            (SELECT rol_id FROM seg.roles WHERE codigo = N'SUPERVISOR' AND activo = 1);
    IF @centro_id IS NULL OR @rol_supervisor_id IS NULL
        THROW 58903, 'Faltan catalogos base para la prueba.', 1;

    INSERT cfg.lineas (centro_trabajo_id, codigo, nombre, descripcion, activa)
    VALUES (@centro_id, N'ZZ49-L1', N'ZZTEST 049 linea 1', N'Sintetica', 1);
    DECLARE @linea1_id bigint = SCOPE_IDENTITY();
    INSERT cfg.lineas (centro_trabajo_id, codigo, nombre, descripcion, activa)
    VALUES (@centro_id, N'ZZ49-L2', N'ZZTEST 049 linea 2', N'Sintetica', 1);
    DECLARE @linea2_id bigint = SCOPE_IDENTITY();
    INSERT cfg.lineas (centro_trabajo_id, codigo, nombre, descripcion, activa)
    VALUES (@centro_id, N'ZZ49-L3', N'ZZTEST 049 linea 3', N'Sintetica', 1);
    DECLARE @linea3_id bigint = SCOPE_IDENTITY();

    INSERT seg.empleados (codigo_nav, nombre_completo, activo_nav, activo_mes, sincronizado_nav_utc)
    VALUES (N'ZZ49-JEFE-A', N'ZZTEST 049 Jefa A', 1, 1, SYSUTCDATETIME());
    DECLARE @jefe_a_id bigint = SCOPE_IDENTITY();
    INSERT seg.empleados (codigo_nav, nombre_completo, activo_nav, activo_mes, sincronizado_nav_utc)
    VALUES (N'ZZ49-JEFE-B', N'ZZTEST 049 Jefe B', 1, 1, SYSUTCDATETIME());
    DECLARE @jefe_b_id bigint = SCOPE_IDENTITY();

    INSERT seg.empleados_roles (empleado_id, rol_id, desde_utc, asignado_por_cuenta, motivo)
    VALUES (@jefe_a_id, @rol_supervisor_id, SYSUTCDATETIME(), N'ZZTEST_049', N'Fixture sintetico'),
           (@jefe_b_id, @rol_supervisor_id, SYSUTCDATETIME(), N'ZZTEST_049', N'Fixture sintetico');

    /* 1. Un jefe con dos lineas vigentes. */
    INSERT cfg.lineas_jefes (linea_id, empleado_id, asignado_por_cuenta, motivo)
    VALUES (@linea1_id, @jefe_a_id, N'ZZTEST_049', N'Fixture sintetico'),
           (@linea2_id, @jefe_a_id, N'ZZTEST_049', N'Fixture sintetico');
    IF (SELECT COUNT(*) FROM cfg.lineas_jefes
        WHERE empleado_id = @jefe_a_id AND asignado_hasta_utc IS NULL) <> 2
        THROW 58910, 'La jefa A deberia tener dos lineas vigentes.', 1;

    /* 2. Una segunda asignacion vigente para la misma linea se rechaza. */
    DECLARE @rechazo_duplicado int = 0;
    BEGIN TRY
        INSERT cfg.lineas_jefes (linea_id, empleado_id, asignado_por_cuenta)
        VALUES (@linea1_id, @jefe_b_id, N'ZZTEST_049');
    END TRY
    BEGIN CATCH
        SET @rechazo_duplicado = ERROR_NUMBER();
    END CATCH;
    IF @rechazo_duplicado NOT IN (2601, 2627)
        THROW 58911, 'La linea acepto dos jefes vigentes a la vez.', 1;

    /* 3. Cerrar la vigencia permite reasignar la linea sin borrar historial. */
    UPDATE cfg.lineas_jefes
    SET asignado_hasta_utc = SYSUTCDATETIME()
    WHERE linea_id = @linea1_id AND asignado_hasta_utc IS NULL;
    INSERT cfg.lineas_jefes (linea_id, empleado_id, asignado_por_cuenta, motivo)
    VALUES (@linea1_id, @jefe_b_id, N'ZZTEST_049', N'Reasignacion sintetica');
    IF (SELECT COUNT(*) FROM cfg.lineas_jefes WHERE linea_id = @linea1_id) <> 2
     OR (SELECT empleado_id FROM cfg.lineas_jefes
         WHERE linea_id = @linea1_id AND asignado_hasta_utc IS NULL) <> @jefe_b_id
        THROW 58912, 'La reasignacion no conservo el historial o no quedo vigente.', 1;

    /* 4. Una vigencia invertida se rechaza por la restriccion CHECK. */
    DECLARE @rechazo_vigencia int = 0;
    BEGIN TRY
        INSERT cfg.lineas_jefes
            (linea_id, empleado_id, asignado_desde_utc, asignado_hasta_utc, asignado_por_cuenta)
        VALUES
            (@linea2_id, @jefe_b_id, SYSUTCDATETIME(), DATEADD(DAY, -1, SYSUTCDATETIME()), N'ZZTEST_049');
    END TRY
    BEGIN CATCH
        SET @rechazo_vigencia = ERROR_NUMBER();
    END CATCH;
    IF @rechazo_vigencia <> 547
        THROW 58913, 'La vigencia invertida no fue rechazada.', 1;

    /* 5. Sin autor (empleado ni cuenta) se rechaza. */
    DECLARE @rechazo_autor int = 0;
    BEGIN TRY
        INSERT cfg.lineas_jefes (linea_id, empleado_id)
        VALUES (@linea3_id, @jefe_b_id);
    END TRY
    BEGIN CATCH
        SET @rechazo_autor = ERROR_NUMBER();
    END CATCH;
    IF @rechazo_autor <> 547
        THROW 58914, 'La asignacion sin autor no fue rechazada.', 1;

    /* 6. La consulta del panel resuelve el jefe vigente de cada linea. */
    IF (SELECT e.codigo_nav
        FROM cfg.lineas l
        OUTER APPLY
        (
            SELECT TOP (1) e.codigo_nav
            FROM cfg.lineas_jefes lj
            JOIN seg.empleados e ON e.empleado_id = lj.empleado_id
            WHERE lj.linea_id = l.linea_id AND lj.asignado_hasta_utc IS NULL
            ORDER BY lj.asignado_desde_utc DESC
        ) e
        WHERE l.linea_id = @linea1_id) <> N'ZZ49-JEFE-B'
        THROW 58915, 'La consulta del panel no devuelve el jefe vigente.', 1;

    PRINT 'Prueba 049 correcta: dos jefes, reasignacion con historial y restricciones verificadas.';
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
