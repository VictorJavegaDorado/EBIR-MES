/* Prueba transaccional 050. No ejecutar sin autorizacion. */
SET NOCOUNT ON;
/* XACT_ABORT OFF: las violaciones esperadas (57001/57003/57004) se capturan
   sin condenar la transaccion exterior, que siempre termina en ROLLBACK. */
SET XACT_ABORT OFF;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 58900, 'Prueba permitida unicamente en EBIR_MES_TEST.', 1;
IF OBJECT_ID(N'cfg.asignar_mesas_propias', N'P') IS NULL
    THROW 58920, 'El paquete 050A no esta instalado.', 1;
IF EXISTS (SELECT 1 FROM cfg.lineas WHERE codigo LIKE N'ZZ50-%')
 OR EXISTS (SELECT 1 FROM seg.empleados WHERE codigo_nav LIKE N'ZZ50-%')
    THROW 58921, 'Existen fixtures ZZ50 pendientes de revision.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE
        @centro_id bigint =
            (SELECT TOP (1) centro_trabajo_id FROM cfg.centros_trabajo ORDER BY centro_trabajo_id),
        @rol_supervisor_id smallint =
            (SELECT rol_id FROM seg.roles WHERE codigo = N'SUPERVISOR' AND activo = 1),
        @rol_operario_id smallint =
            (SELECT rol_id FROM seg.roles WHERE codigo = N'OPERARIO' AND activo = 1);
    IF @centro_id IS NULL OR @rol_supervisor_id IS NULL
        THROW 58922, 'Faltan catalogos base para la prueba.', 1;

    INSERT cfg.lineas (centro_trabajo_id, codigo, nombre, descripcion, activa)
    VALUES (@centro_id, N'ZZ50-L1', N'ZZTEST 050 linea 1', N'Sintetica', 1);
    DECLARE @linea1_id bigint = SCOPE_IDENTITY();
    INSERT cfg.lineas (centro_trabajo_id, codigo, nombre, descripcion, activa)
    VALUES (@centro_id, N'ZZ50-L2', N'ZZTEST 050 linea 2', N'Sintetica', 1);
    DECLARE @linea2_id bigint = SCOPE_IDENTITY();
    INSERT cfg.lineas (centro_trabajo_id, codigo, nombre, descripcion, activa)
    VALUES (@centro_id, N'ZZ50-L3', N'ZZTEST 050 linea 3', N'Sintetica', 1);
    DECLARE @linea3_id bigint = SCOPE_IDENTITY();
    INSERT cfg.lineas
        (centro_trabajo_id, codigo, nombre, descripcion, activa, desactivado_utc)
    VALUES
        (@centro_id, N'ZZ50-L4', N'ZZTEST 050 linea 4', N'Sintetica', 0, SYSUTCDATETIME());
    DECLARE @linea_inactiva_id bigint = SCOPE_IDENTITY();

    INSERT seg.empleados (codigo_nav, nombre_completo, activo_nav, activo_mes, sincronizado_nav_utc)
    VALUES (N'ZZ50-JEFE-A', N'ZZTEST 050 Jefa A', 1, 1, SYSUTCDATETIME());
    DECLARE @jefe_a_id bigint = SCOPE_IDENTITY();
    INSERT seg.empleados (codigo_nav, nombre_completo, activo_nav, activo_mes, sincronizado_nav_utc)
    VALUES (N'ZZ50-JEFE-B', N'ZZTEST 050 Jefe B', 1, 1, SYSUTCDATETIME());
    DECLARE @jefe_b_id bigint = SCOPE_IDENTITY();
    INSERT seg.empleados (codigo_nav, nombre_completo, activo_nav, activo_mes, sincronizado_nav_utc)
    VALUES (N'ZZ50-OPERARIO', N'ZZTEST 050 Operario', 1, 1, SYSUTCDATETIME());
    DECLARE @operario_id bigint = SCOPE_IDENTITY();

    INSERT seg.empleados_roles (empleado_id, rol_id, desde_utc, asignado_por_cuenta, motivo)
    VALUES (@jefe_a_id, @rol_supervisor_id, SYSUTCDATETIME(), N'ZZTEST_050', N'Fixture sintetico'),
           (@jefe_b_id, @rol_supervisor_id, SYSUTCDATETIME(), N'ZZTEST_050', N'Fixture sintetico');
    IF @rol_operario_id IS NOT NULL
        INSERT seg.empleados_roles (empleado_id, rol_id, desde_utc, asignado_por_cuenta, motivo)
        VALUES (@operario_id, @rol_operario_id, SYSUTCDATETIME(), N'ZZTEST_050', N'Fixture sintetico');

    /* 1. La jefa A toma dos lineas libres. */
    EXEC cfg.asignar_mesas_propias
        @empleado_id = @jefe_a_id,
        @lineas_csv = N'';
    DECLARE @csv_1_2 nvarchar(50) = CONCAT(@linea1_id, N',', @linea2_id);
    EXEC cfg.asignar_mesas_propias @empleado_id = @jefe_a_id, @lineas_csv = @csv_1_2;
    IF (SELECT COUNT(*) FROM cfg.lineas_jefes
        WHERE empleado_id = @jefe_a_id AND asignado_hasta_utc IS NULL) <> 2
        THROW 58930, 'La jefa A deberia tener dos lineas vigentes.', 1;

    /* 2. El jefe B no puede tomar una linea que ya lleva la jefa A. */
    DECLARE @rechazo_bloqueada int = 0;
    BEGIN TRY
        EXEC cfg.asignar_mesas_propias @empleado_id = @jefe_b_id, @lineas_csv = @linea1_id;
    END TRY
    BEGIN CATCH
        SET @rechazo_bloqueada = ERROR_NUMBER();
    END CATCH;
    IF @rechazo_bloqueada <> 57004
        THROW 58931, 'La linea bloqueada no rechazo con 57004.', 1;
    IF (SELECT empleado_id FROM cfg.lineas_jefes
        WHERE linea_id = @linea1_id AND asignado_hasta_utc IS NULL) <> @jefe_a_id
        THROW 58932, 'El intento rechazado no debio tocar la vigencia de la jefa A.', 1;

    /* 3. La jefa A cambia su seleccion: suelta L2, conserva L1, toma L3. */
    DECLARE @csv_1_3 nvarchar(50) = CONCAT(@linea1_id, N',', @linea3_id);
    EXEC cfg.asignar_mesas_propias @empleado_id = @jefe_a_id, @lineas_csv = @csv_1_3;
    IF (SELECT COUNT(*) FROM cfg.lineas_jefes
        WHERE empleado_id = @jefe_a_id AND asignado_hasta_utc IS NULL) <> 2
        THROW 58933, 'La jefa A deberia conservar dos lineas vigentes tras el cambio.', 1;
    IF EXISTS (SELECT 1 FROM cfg.lineas_jefes
               WHERE linea_id = @linea2_id AND asignado_hasta_utc IS NULL)
        THROW 58934, 'La linea 2 deberia haber quedado libre.', 1;
    IF NOT EXISTS (SELECT 1 FROM cfg.lineas_jefes WHERE linea_id = @linea2_id)
        THROW 58935, 'La linea 2 perdio su historial en lugar de cerrarse.', 1;

    /* 4. Ahora el jefe B puede tomar la linea 2, que quedo libre. */
    EXEC cfg.asignar_mesas_propias @empleado_id = @jefe_b_id, @lineas_csv = @linea2_id;
    IF (SELECT empleado_id FROM cfg.lineas_jefes
        WHERE linea_id = @linea2_id AND asignado_hasta_utc IS NULL) <> @jefe_b_id
        THROW 58936, 'El jefe B deberia haber tomado la linea liberada.', 1;

    /* 5. Un operario sin rol de supervisor vigente se rechaza. */
    DECLARE @rechazo_no_supervisor int = 0;
    BEGIN TRY
        EXEC cfg.asignar_mesas_propias @empleado_id = @operario_id, @lineas_csv = @linea1_id;
    END TRY
    BEGIN CATCH
        SET @rechazo_no_supervisor = ERROR_NUMBER();
    END CATCH;
    IF @rechazo_no_supervisor <> 57001
        THROW 58937, 'El operario no supervisor no fue rechazado con 57001.', 1;

    /* 6. Una linea inactiva se rechaza. */
    DECLARE @rechazo_inactiva int = 0;
    BEGIN TRY
        EXEC cfg.asignar_mesas_propias @empleado_id = @jefe_a_id, @lineas_csv = @linea_inactiva_id;
    END TRY
    BEGIN CATCH
        SET @rechazo_inactiva = ERROR_NUMBER();
    END CATCH;
    IF @rechazo_inactiva <> 57003
        THROW 58938, 'La linea inactiva no fue rechazada con 57003.', 1;

    PRINT 'Prueba 050 correcta: seleccion propia, bloqueo de linea ajena, liberacion con historial y validaciones verificadas.';
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
