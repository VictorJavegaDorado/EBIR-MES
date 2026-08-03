SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Prevuelo permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'seg.empleados', N'U') IS NULL
 OR OBJECT_ID(N'seg.roles', N'U') IS NULL
 OR OBJECT_ID(N'seg.empleados_roles', N'U') IS NULL
 OR OBJECT_ID(N'seg.credenciales_rfid', N'U') IS NULL
 OR OBJECT_ID(N'aud.eventos', N'U') IS NULL
    THROW 51040, 'Faltan objetos base requeridos por el paquete 020.', 1;

IF
(
    SELECT COUNT_BIG(*)
    FROM seg.empleados e
    WHERE e.codigo_nav IN (N'325', N'884')
      AND e.activo_nav = 1
      AND e.activo_mes = 1
) <> 2
    THROW 51044, 'Los dos empleados TEST no estan activos.', 1;

IF
(
    SELECT COUNT_BIG(*)
    FROM seg.empleados e
    JOIN seg.empleados_roles er
      ON er.empleado_id = e.empleado_id AND er.hasta_utc IS NULL
    JOIN seg.roles r
      ON r.rol_id = er.rol_id AND r.codigo = N'OPERARIO' AND r.activo = 1
    WHERE e.codigo_nav IN (N'325', N'884')
) <> 2
    THROW 51044, 'Los dos empleados TEST no conservan rol OPERARIO.', 1;

IF
(
    SELECT COUNT_BIG(*)
    FROM seg.empleados e
    JOIN seg.credenciales_rfid c
      ON c.empleado_id = e.empleado_id AND c.activa = 1 AND c.hasta_utc IS NULL
    WHERE e.codigo_nav IN (N'325', N'884')
) <> 2
    THROW 51045, 'Los dos empleados TEST no tienen una credencial activa cada uno.', 1;

SELECT
    (SELECT COUNT_BIG(*) FROM seg.empleados WHERE codigo_nav IN (N'325', N'884')) AS empleados_objetivo,
    (
        SELECT COUNT_BIG(*)
        FROM seg.credenciales_rfid c
        JOIN seg.empleados e ON e.empleado_id = c.empleado_id
        WHERE e.codigo_nav IN (N'325', N'884') AND c.activa = 1
    ) AS credenciales_objetivo_activas,
    (SELECT COUNT_BIG(*) FROM seg.credenciales_rfid WHERE activa = 1) AS credenciales_activas_total,
    N'PREVUELO_020_CORRECTO' AS resultado;
