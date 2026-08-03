SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Paquete permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'seg.empleados', N'U') IS NULL
 OR OBJECT_ID(N'seg.roles', N'U') IS NULL
 OR OBJECT_ID(N'seg.empleados_roles', N'U') IS NULL
 OR OBJECT_ID(N'seg.credenciales_rfid', N'U') IS NULL
 OR OBJECT_ID(N'aud.eventos', N'U') IS NULL
    THROW 51040, 'El paquete 020 requiere los objetos base de seguridad y auditoria.', 1;

IF OBJECT_ID(N'tempdb..#pilot_rfid_rotations') IS NULL
    THROW 51041, 'Falta la tabla temporal protegida del paquete 020.', 1;

IF (SELECT COUNT_BIG(*) FROM #pilot_rfid_rotations) <> 2
 OR (SELECT COUNT_BIG(DISTINCT codigo_nav) FROM #pilot_rfid_rotations) <> 2
 OR (SELECT COUNT_BIG(DISTINCT rfid_busqueda) FROM #pilot_rfid_rotations) <> 2
    THROW 51042, 'El paquete 020 requiere exactamente dos rotaciones distintas.', 1;

IF EXISTS
(
    SELECT 1
    FROM #pilot_rfid_rotations
    WHERE codigo_nav NOT IN (N'325', N'884')
       OR rol_codigo <> N'OPERARIO'
       OR DATALENGTH(rfid_busqueda) <> 32
)
 OR NOT EXISTS (SELECT 1 FROM #pilot_rfid_rotations WHERE codigo_nav = N'325')
 OR NOT EXISTS (SELECT 1 FROM #pilot_rfid_rotations WHERE codigo_nav = N'884')
    THROW 51043, 'Los destinatarios o roles de la rotacion 020 no son validos.', 1;

IF
(
    SELECT COUNT_BIG(*)
    FROM #pilot_rfid_rotations r
    JOIN seg.empleados e
      ON e.codigo_nav = r.codigo_nav
     AND e.activo_nav = 1
     AND e.activo_mes = 1
    WHERE EXISTS
    (
        SELECT 1
        FROM seg.empleados_roles er
        JOIN seg.roles rol ON rol.rol_id = er.rol_id
        WHERE er.empleado_id = e.empleado_id
          AND er.hasta_utc IS NULL
          AND rol.codigo = N'OPERARIO'
          AND rol.activo = 1
    )
) <> 2
    THROW 51044, 'Los dos empleados TEST deben existir, estar activos y conservar rol OPERARIO.', 1;

IF
(
    SELECT COUNT_BIG(*)
    FROM seg.credenciales_rfid c
    JOIN seg.empleados e ON e.empleado_id = c.empleado_id
    JOIN #pilot_rfid_rotations r ON r.codigo_nav = e.codigo_nav
    WHERE c.activa = 1 AND c.hasta_utc IS NULL
) <> 2
    THROW 51045, 'Cada empleado de la rotacion debe tener una unica credencial activa.', 1;

IF EXISTS
(
    SELECT 1
    FROM seg.credenciales_rfid c
    JOIN #pilot_rfid_rotations r ON r.rfid_busqueda = c.rfid_busqueda
)
    THROW 51046, 'Una credencial nueva ya existe en el historial RFID.', 1;

DECLARE
    @ahora datetime2(3) = SYSUTCDATETIME(),
    @correlacion_id uniqueidentifier = NEWID();

DECLARE @credenciales_revocadas TABLE
(
    credencial_rfid_id bigint NOT NULL,
    empleado_id bigint NOT NULL
);

DECLARE @credenciales_nuevas TABLE
(
    credencial_rfid_id bigint NOT NULL,
    empleado_id bigint NOT NULL
);

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE c
    SET
        activa = 0,
        hasta_utc = @ahora,
        motivo_baja = N'Rotacion controlada de credencial RFID del piloto TEST, paquete 020.'
    OUTPUT inserted.credencial_rfid_id, inserted.empleado_id
        INTO @credenciales_revocadas (credencial_rfid_id, empleado_id)
    FROM seg.credenciales_rfid c
    JOIN seg.empleados e ON e.empleado_id = c.empleado_id
    JOIN #pilot_rfid_rotations r ON r.codigo_nav = e.codigo_nav
    WHERE c.activa = 1 AND c.hasta_utc IS NULL;

    IF (SELECT COUNT_BIG(*) FROM @credenciales_revocadas) <> 2
        THROW 51047, 'No se revocaron exactamente dos credenciales vigentes.', 1;

    INSERT seg.credenciales_rfid
    (
        empleado_id, rfid_busqueda, ultimos_caracteres,
        desde_utc, hasta_utc, activa, motivo_baja
    )
    OUTPUT inserted.credencial_rfid_id, inserted.empleado_id
        INTO @credenciales_nuevas (credencial_rfid_id, empleado_id)
    SELECT
        e.empleado_id, r.rfid_busqueda, NULL,
        @ahora, NULL, 1, NULL
    FROM #pilot_rfid_rotations r
    JOIN seg.empleados e ON e.codigo_nav = r.codigo_nav;

    IF (SELECT COUNT_BIG(*) FROM @credenciales_nuevas) <> 2
     OR
       (
           SELECT COUNT_BIG(*)
           FROM seg.credenciales_rfid c
           JOIN seg.empleados e ON e.empleado_id = c.empleado_id
           JOIN #pilot_rfid_rotations r ON r.codigo_nav = e.codigo_nav
           WHERE c.activa = 1 AND c.hasta_utc IS NULL
       ) <> 2
        THROW 51048, 'No quedaron exactamente dos credenciales nuevas activas.', 1;

    DECLARE @resumen nvarchar(max) =
    (
        SELECT
            2 AS empleados,
            2 AS credenciales_revocadas,
            2 AS credenciales_activas
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    INSERT aud.eventos
    (
        tipo_evento, cuenta_dominio, entidad, entidad_id,
        valor_nuevo, motivo, fecha_utc, correlacion_id
    )
    VALUES
    (
        N'CREDENCIALES_RFID_ROTADAS', ORIGINAL_LOGIN(), N'PAQUETE_020', NULL,
        @resumen, N'Rotacion controlada de credenciales RFID TEST.', @ahora,
        @correlacion_id
    );

    COMMIT TRANSACTION;

    SELECT
        2 AS empleados_configurados,
        2 AS credenciales_revocadas,
        2 AS credenciales_configuradas,
        @correlacion_id AS correlacion_id;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
