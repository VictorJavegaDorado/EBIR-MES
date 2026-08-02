SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'tempdb..#pilot_linea') IS NULL
 OR OBJECT_ID(N'tempdb..#pilot_impresora') IS NULL
 OR OBJECT_ID(N'tempdb..#pilot_dispositivo') IS NULL
 OR OBJECT_ID(N'tempdb..#pilot_empleados') IS NULL
    THROW 51026, 'El paquete 019 requiere configuracion externa parametrizada.', 1;

IF OBJECT_ID(N'cfg.centros_trabajo', N'U') IS NULL
 OR OBJECT_ID(N'cfg.lineas', N'U') IS NULL
 OR OBJECT_ID(N'cfg.impresoras', N'U') IS NULL
 OR OBJECT_ID(N'cfg.dispositivos', N'U') IS NULL
 OR OBJECT_ID(N'cfg.lineas_impresoras', N'U') IS NULL
 OR OBJECT_ID(N'cfg.lineas_dispositivos', N'U') IS NULL
 OR OBJECT_ID(N'seg.empleados', N'U') IS NULL
 OR OBJECT_ID(N'seg.roles', N'U') IS NULL
 OR OBJECT_ID(N'seg.empleados_roles', N'U') IS NULL
 OR OBJECT_ID(N'seg.credenciales_rfid', N'U') IS NULL
 OR OBJECT_ID(N'aud.eventos', N'U') IS NULL
    THROW 51027, 'El paquete 019 requiere los paquetes base 001-009.', 1;

IF (SELECT COUNT_BIG(*) FROM #pilot_linea) <> 1
 OR (SELECT COUNT_BIG(*) FROM #pilot_impresora) <> 1
 OR (SELECT COUNT_BIG(*) FROM #pilot_dispositivo) <> 1
 OR (SELECT COUNT_BIG(*) FROM #pilot_empleados) <> 3
    THROW 51028, 'El piloto exige una linea, una impresora, un lector y tres empleados.', 1;

IF EXISTS
(
    SELECT 1
    FROM #pilot_linea
    WHERE NULLIF(LTRIM(RTRIM(centro_codigo)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(codigo)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(nombre)), N'') IS NULL
       OR LEN(LTRIM(RTRIM(codigo))) > 20
)
    THROW 51029, 'La configuracion de linea no es valida.', 1;

IF EXISTS
(
    SELECT 1
    FROM #pilot_impresora
    WHERE NULLIF(LTRIM(RTRIM(codigo)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(nombre)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(modelo)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(protocolo)), N'') IS NULL
       OR (NULLIF(LTRIM(RTRIM(nombre_red)), N'') IS NULL
           AND NULLIF(LTRIM(RTRIM(direccion_ip)), '') IS NULL)
       OR resolucion_dpi <= 0
)
    THROW 51030, 'La configuracion de impresora no es valida.', 1;

IF EXISTS
(
    SELECT 1
    FROM #pilot_dispositivo
    WHERE NULLIF(LTRIM(RTRIM(codigo)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(nombre)), N'') IS NULL
       OR tipo <> N'RFID'
       OR (NULLIF(LTRIM(RTRIM(nombre_equipo)), N'') IS NULL
           AND NULLIF(LTRIM(RTRIM(direccion_red)), N'') IS NULL)
)
    THROW 51031, 'La configuracion del lector RFID no es valida.', 1;

IF EXISTS
(
    SELECT 1
    FROM #pilot_empleados
    WHERE NULLIF(LTRIM(RTRIM(codigo_nav)), N'') IS NULL
       OR NULLIF(LTRIM(RTRIM(nombre_completo)), N'') IS NULL
       OR rol_codigo NOT IN (N'OPERARIO', N'SUPERVISOR')
       OR DATALENGTH(rfid_busqueda) <> 32
       OR sincronizado_nav_utc IS NULL
)
 OR EXISTS
(
    SELECT codigo_nav FROM #pilot_empleados
    GROUP BY codigo_nav HAVING COUNT_BIG(*) > 1
)
 OR EXISTS
(
    SELECT rfid_busqueda FROM #pilot_empleados
    GROUP BY rfid_busqueda HAVING COUNT_BIG(*) > 1
)
 OR (SELECT COUNT_BIG(*) FROM #pilot_empleados WHERE rol_codigo = N'OPERARIO') <> 2
 OR (SELECT COUNT_BIG(*) FROM #pilot_empleados WHERE rol_codigo = N'SUPERVISOR') <> 1
    THROW 51032, 'Los empleados TEST deben ser dos operarios y un supervisor con huellas RFID unicas.', 1;

DECLARE
    @centro_codigo nvarchar(30) = (SELECT centro_codigo FROM #pilot_linea),
    @linea_codigo nvarchar(20) = (SELECT codigo FROM #pilot_linea),
    @impresora_codigo nvarchar(30) = (SELECT codigo FROM #pilot_impresora),
    @dispositivo_codigo nvarchar(30) = (SELECT codigo FROM #pilot_dispositivo),
    @centro_trabajo_id bigint,
    @linea_id bigint,
    @impresora_id bigint,
    @dispositivo_id bigint,
    @ahora datetime2(3) = SYSUTCDATETIME(),
    @correlacion_id uniqueidentifier = NEWID();

SELECT @centro_trabajo_id = centro_trabajo_id
FROM cfg.centros_trabajo
WHERE codigo = @centro_codigo AND activo = 1;

IF @centro_trabajo_id IS NULL
    THROW 51033, 'El centro de trabajo configurado no existe o esta inactivo.', 1;

IF EXISTS (SELECT 1 FROM cfg.lineas WHERE centro_trabajo_id = @centro_trabajo_id AND codigo = @linea_codigo)
 OR EXISTS (SELECT 1 FROM cfg.impresoras WHERE codigo = @impresora_codigo)
 OR EXISTS (SELECT 1 FROM cfg.dispositivos WHERE codigo = @dispositivo_codigo)
 OR EXISTS (SELECT 1 FROM seg.empleados WHERE codigo_nav IN (SELECT codigo_nav FROM #pilot_empleados))
 OR EXISTS (SELECT 1 FROM seg.credenciales_rfid WHERE rfid_busqueda IN (SELECT rfid_busqueda FROM #pilot_empleados))
    THROW 51034, 'Los codigos o huellas del paquete 019 ya existen total o parcialmente.', 1;

IF NOT EXISTS (SELECT 1 FROM seg.roles WHERE codigo = N'OPERARIO' AND activo = 1)
 OR NOT EXISTS (SELECT 1 FROM seg.roles WHERE codigo = N'SUPERVISOR' AND activo = 1)
    THROW 51035, 'Los roles OPERARIO y SUPERVISOR deben existir y estar activos.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT cfg.lineas
    (
        centro_trabajo_id, codigo, nombre, descripcion, activa
    )
    SELECT
        @centro_trabajo_id, codigo, nombre, descripcion, 1
    FROM #pilot_linea;
    SET @linea_id = SCOPE_IDENTITY();

    INSERT cfg.impresoras
    (
        codigo, nombre, modelo, nombre_red, direccion_ip, protocolo,
        resolucion_dpi, activa
    )
    SELECT
        codigo, nombre, modelo, nombre_red, direccion_ip, protocolo,
        resolucion_dpi, 1
    FROM #pilot_impresora;
    SET @impresora_id = SCOPE_IDENTITY();

    INSERT cfg.dispositivos
    (
        codigo, nombre, tipo, nombre_equipo, direccion_red, activo
    )
    SELECT
        codigo, nombre, tipo, nombre_equipo, direccion_red, 1
    FROM #pilot_dispositivo;
    SET @dispositivo_id = SCOPE_IDENTITY();

    INSERT cfg.lineas_impresoras
    (
        linea_id, impresora_id, es_principal, asignado_desde_utc,
        asignado_por_cuenta, motivo
    )
    VALUES
    (
        @linea_id, @impresora_id, 1, @ahora,
        ORIGINAL_LOGIN(), N'Configuracion controlada del piloto TEST, paquete 019.'
    );

    INSERT cfg.lineas_dispositivos
    (
        linea_id, dispositivo_id, asignado_desde_utc,
        asignado_por_cuenta, motivo
    )
    VALUES
    (
        @linea_id, @dispositivo_id, @ahora,
        ORIGINAL_LOGIN(), N'Configuracion controlada del piloto TEST, paquete 019.'
    );

    DECLARE @empleados_insertados TABLE
    (
        empleado_id bigint NOT NULL,
        codigo_nav nvarchar(30) NOT NULL,
        rol_codigo nvarchar(30) NOT NULL,
        rfid_busqueda varbinary(32) NOT NULL,
        ultimos_caracteres nvarchar(8) NULL
    );

    MERGE seg.empleados AS destino
    USING #pilot_empleados AS origen
       ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT
        (
            codigo_nav, nombre_completo, cargo, alias, rol_interno_nav,
            proceso_codigo, tipo_mano_obra, grupo_turno,
            activo_nav, activo_mes, sincronizado_nav_utc
        )
        VALUES
        (
            origen.codigo_nav, origen.nombre_completo, origen.cargo,
            origen.alias, origen.rol_interno_nav, origen.proceso_codigo,
            origen.tipo_mano_obra, origen.grupo_turno,
            1, 1, origen.sincronizado_nav_utc
        )
    OUTPUT
        inserted.empleado_id, inserted.codigo_nav, origen.rol_codigo,
        origen.rfid_busqueda, origen.ultimos_caracteres
    INTO @empleados_insertados;

    INSERT seg.empleados_roles
    (
        empleado_id, rol_id, desde_utc, asignado_por_cuenta, motivo
    )
    SELECT
        e.empleado_id, r.rol_id, @ahora, ORIGINAL_LOGIN(),
        N'Rol controlado del piloto TEST, paquete 019.'
    FROM @empleados_insertados e
    JOIN seg.roles r ON r.codigo = e.rol_codigo AND r.activo = 1;

    INSERT seg.credenciales_rfid
    (
        empleado_id, rfid_busqueda, ultimos_caracteres,
        desde_utc, activa
    )
    SELECT
        empleado_id, rfid_busqueda, ultimos_caracteres,
        @ahora, 1
    FROM @empleados_insertados;

    DECLARE @resumen nvarchar(max) =
    (
        SELECT
            @linea_codigo AS linea,
            @impresora_codigo AS impresora,
            @dispositivo_codigo AS lector,
            3 AS empleados,
            3 AS credenciales_rfid
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    INSERT aud.eventos
    (
        tipo_evento, cuenta_dominio, entidad, entidad_id,
        valor_nuevo, motivo, fecha_utc, correlacion_id
    )
    VALUES
    (
        N'MAESTROS_PILOTO_CONFIGURADOS', ORIGINAL_LOGIN(), N'PAQUETE_019', NULL,
        @resumen, N'Alta controlada de maestros TEST revisados.', @ahora,
        @correlacion_id
    );

    IF (SELECT COUNT_BIG(*) FROM @empleados_insertados) <> 3
     OR NOT EXISTS
        (
            SELECT 1 FROM cfg.lineas_impresoras
            WHERE linea_id = @linea_id AND impresora_id = @impresora_id
              AND es_principal = 1 AND asignado_hasta_utc IS NULL
        )
     OR NOT EXISTS
        (
            SELECT 1 FROM cfg.lineas_dispositivos
            WHERE linea_id = @linea_id AND dispositivo_id = @dispositivo_id
              AND asignado_hasta_utc IS NULL
        )
        THROW 51036, 'No se crearon todos los maestros y asignaciones del paquete 019.', 1;

    COMMIT TRANSACTION;

    SELECT
        @linea_id AS linea_id,
        @impresora_id AS impresora_id,
        @dispositivo_id AS dispositivo_id,
        3 AS empleados_configurados,
        3 AS credenciales_configuradas,
        @correlacion_id AS correlacion_id;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
