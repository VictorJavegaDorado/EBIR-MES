SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Prevuelo permitido unicamente en EBIR_MES_TEST.', 1;

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
    THROW 51027, 'Faltan objetos base requeridos por el paquete 019.', 1;

IF NOT EXISTS (SELECT 1 FROM cfg.centros_trabajo WHERE codigo = N'CT-01' AND activo = 1)
    THROW 51033, 'El centro de trabajo CT-01 no existe o esta inactivo.', 1;

IF NOT EXISTS (SELECT 1 FROM seg.roles WHERE codigo = N'OPERARIO' AND activo = 1)
 OR NOT EXISTS (SELECT 1 FROM seg.roles WHERE codigo = N'SUPERVISOR' AND activo = 1)
    THROW 51035, 'Los roles base del piloto no estan disponibles.', 1;

SELECT N'lineas' AS entidad, COUNT_BIG(*) AS filas FROM cfg.lineas
UNION ALL SELECT N'impresoras', COUNT_BIG(*) FROM cfg.impresoras
UNION ALL SELECT N'asignaciones_impresora', COUNT_BIG(*) FROM cfg.lineas_impresoras
UNION ALL SELECT N'dispositivos', COUNT_BIG(*) FROM cfg.dispositivos
UNION ALL SELECT N'asignaciones_dispositivo', COUNT_BIG(*) FROM cfg.lineas_dispositivos
UNION ALL SELECT N'empleados', COUNT_BIG(*) FROM seg.empleados
UNION ALL SELECT N'credenciales_rfid', COUNT_BIG(*) FROM seg.credenciales_rfid;

SELECT
    DB_NAME() AS base_datos,
    ORIGINAL_LOGIN() AS ejecutado_por,
    N'PREVUELO_019_CORRECTO' AS resultado;
