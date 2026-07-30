/*
Pruebas 013 - auditoria y permisos efectivos.
Requiere bloques 01-04 y concurrencia 05-06 completados.
No modifica datos ni llama a sistemas externos.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 56700, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF USER_ID(N'EBIR\MES$') IS NULL
 OR DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
 OR NOT EXISTS
 (
     SELECT 1
     FROM sys.database_role_members
     WHERE role_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
       AND member_principal_id = USER_ID(N'EBIR\MES$')
 )
    THROW 56701, 'El runtime o su pertenencia a mes_runtime no son correctos.', 1;

IF (SELECT COUNT(*) FROM prod.ordenes WHERE numero_orden LIKE N'ZZ13-%') <> 3
 OR (SELECT COUNT(*) FROM [log].scrap s
     JOIN prod.ordenes o ON o.orden_id = s.orden_id
     WHERE o.numero_orden LIKE N'ZZ13-%') < 3
 OR (SELECT COUNT(*) FROM [log].solicitudes_reaprovisionamiento) NOT IN (8, 9)
    THROW 56702, 'No se completaron los bloques funcionales previos.', 1;

DECLARE @tipos TABLE
(
    tipo_evento nvarchar(80) NOT NULL PRIMARY KEY
);

INSERT @tipos
VALUES
(N'SCRAP_REGISTRADO'),
(N'SCRAP_CORREGIDO'),
(N'SCRAP_ANULADO'),
(N'REAPROVISIONAMIENTO_SOLICITADO'),
(N'REAPROVISIONAMIENTO_ACEPTADO'),
(N'REAPROVISIONAMIENTO_EN_CAMINO'),
(N'REAPROVISIONAMIENTO_ENTREGADO'),
(N'REAPROVISIONAMIENTO_RECHAZADO'),
(N'REAPROVISIONAMIENTO_CANCELADO');

IF EXISTS
(
    SELECT 1
    FROM @tipos t
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM aud.eventos a
        JOIN prod.ordenes o ON o.orden_id = a.orden_id
        WHERE o.numero_orden LIKE N'ZZ13-%'
          AND a.tipo_evento = t.tipo_evento
    )
)
    THROW 56703, 'Falta al menos un tipo de auditoria 013.', 1;

IF EXISTS
(
    SELECT 1
    FROM aud.eventos a
    JOIN prod.ordenes o ON o.orden_id = a.orden_id
    JOIN @tipos t ON t.tipo_evento = a.tipo_evento
    WHERE o.numero_orden LIKE N'ZZ13-%'
      AND
      (
          a.correlacion_id IS NULL
          OR a.fecha_utc IS NULL
          OR a.empleado_id IS NULL
          OR a.linea_id IS NULL
          OR a.sesion_linea_id IS NULL
          OR NULLIF(LTRIM(RTRIM(a.entidad)), N'') IS NULL
          OR a.entidad_id IS NULL
      )
)
    THROW 56704, 'Existe auditoria 013 sin autor, correlacion o contexto.', 1;

IF EXISTS
(
    SELECT 1
    FROM aud.eventos a
    JOIN prod.ordenes o ON o.orden_id = a.orden_id
    JOIN @tipos t ON t.tipo_evento = a.tipo_evento
    WHERE o.numero_orden LIKE N'ZZ13-%'
      AND
      (
          LOWER(COALESCE(a.valor_anterior, N'')) LIKE N'%rfid%'
          OR LOWER(COALESCE(a.valor_nuevo, N'')) LIKE N'%rfid%'
          OR LOWER(COALESCE(a.motivo, N'')) LIKE N'%rfid%'
          OR LOWER(COALESCE(a.valor_anterior, N'')) LIKE N'%password%'
          OR LOWER(COALESCE(a.valor_nuevo, N'')) LIKE N'%password%'
          OR LOWER(COALESCE(a.valor_anterior, N'')) LIKE N'%secret%'
          OR LOWER(COALESCE(a.valor_nuevo, N'')) LIKE N'%secret%'
      )
)
    THROW 56705, 'La auditoria 013 contiene una posible referencia sensible.', 1;

IF EXISTS
(
    SELECT 1
    FROM aud.eventos a
    JOIN prod.ordenes o ON o.orden_id = a.orden_id
    WHERE o.numero_orden LIKE N'ZZ13-%'
      AND a.tipo_evento IN (N'SCRAP_CORREGIDO', N'SCRAP_ANULADO')
      AND
      (
          a.rol_usado <> N'SUPERVISOR'
          OR a.valor_anterior IS NULL
          OR a.valor_nuevo IS NULL
          OR NULLIF(LTRIM(RTRIM(a.motivo)), N'') IS NULL
      )
)
    THROW 56706, 'Una revision de scrap carece de rol, valores o motivo.', 1;

IF EXISTS
(
    SELECT 1
    FROM aud.eventos a
    JOIN prod.ordenes o ON o.orden_id = a.orden_id
    WHERE o.numero_orden LIKE N'ZZ13-%'
      AND a.tipo_evento LIKE N'REAPROVISIONAMIENTO_%'
      AND a.tipo_evento <> N'REAPROVISIONAMIENTO_SOLICITADO'
      AND
      (
          a.rol_usado <> N'APROVISIONADOR'
          OR a.valor_anterior IS NULL
          OR a.valor_nuevo IS NULL
      )
)
    THROW 56707, 'Una transicion carece de rol o valores auditados.', 1;

IF EXISTS
(
    SELECT 1
    FROM aud.eventos a
    JOIN prod.ordenes o ON o.orden_id = a.orden_id
    WHERE o.numero_orden LIKE N'ZZ13-%'
      AND a.tipo_evento IN
          (N'REAPROVISIONAMIENTO_RECHAZADO',
           N'REAPROVISIONAMIENTO_CANCELADO')
      AND NULLIF(LTRIM(RTRIM(a.motivo)), N'') IS NULL
)
    THROW 56708, 'Un rechazo o cancelacion auditado carece de motivo.', 1;

EXECUTE AS USER = N'EBIR\MES$';
BEGIN TRY
    IF EXISTS
    (
        SELECT 1
        FROM
        (
            VALUES
            (N'log.registrar_scrap'),
            (N'log.revisar_scrap'),
            (N'log.crear_solicitud_reaprovisionamiento'),
            (N'log.transicionar_solicitud_reaprovisionamiento')
        ) p(objeto)
        WHERE COALESCE(HAS_PERMS_BY_NAME(p.objeto, N'OBJECT', N'EXECUTE'), 0) <> 1
    )
        THROW 56709, 'Runtime sin EXECUTE en algun procedimiento 013.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM
        (
            VALUES
            (N'log.scrap'),
            (N'log.revisiones_scrap'),
            (N'log.solicitudes_reaprovisionamiento'),
            (N'log.historial_solicitudes'),
            (N'nav.componentes_orden'),
            (N'nav.operaciones')
        ) p(objeto)
        WHERE COALESCE(HAS_PERMS_BY_NAME(p.objeto, N'OBJECT', N'SELECT'), 0) <> 1
    )
        THROW 56710, 'Runtime sin lectura funcional requerida por 013.', 1;

    IF HAS_PERMS_BY_NAME(N'aud.eventos', N'OBJECT', N'SELECT') <> 0
        THROW 56711, 'Runtime puede leer auditoria.', 1;

    IF HAS_PERMS_BY_NAME(N'aud.registrar_evento', N'OBJECT', N'EXECUTE') <> 0
        THROW 56712, 'Runtime puede invocar directamente auditoria.', 1;

    IF HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CONTROL') <> 0
     OR HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'ALTER') <> 0
     OR HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CREATE TABLE') <> 0
     OR HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CREATE PROCEDURE') <> 0
        THROW 56713, 'Runtime conserva permisos administrativos.', 1;

    IF HAS_PERMS_BY_NAME(N'log.scrap', N'OBJECT', N'INSERT') <> 0
     OR HAS_PERMS_BY_NAME(N'log.scrap', N'OBJECT', N'UPDATE') <> 0
     OR HAS_PERMS_BY_NAME(N'log.scrap', N'OBJECT', N'DELETE') <> 0
     OR HAS_PERMS_BY_NAME
        (N'log.solicitudes_reaprovisionamiento', N'OBJECT', N'INSERT') <> 0
     OR HAS_PERMS_BY_NAME
        (N'log.solicitudes_reaprovisionamiento', N'OBJECT', N'UPDATE') <> 0
     OR HAS_PERMS_BY_NAME(N'nav.operaciones', N'OBJECT', N'INSERT') <> 0
        THROW 56714, 'Runtime puede escribir directamente datos 013.', 1;
END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;
REVERT;

SELECT
    a.tipo_evento,
    COUNT(*) eventos,
    COUNT(DISTINCT a.correlacion_id) correlaciones
FROM aud.eventos a
JOIN prod.ordenes o ON o.orden_id = a.orden_id
JOIN @tipos t ON t.tipo_evento = a.tipo_evento
WHERE o.numero_orden LIKE N'ZZ13-%'
GROUP BY a.tipo_evento
ORDER BY a.tipo_evento;

PRINT N'PRUEBAS 013 AUDITORIA Y PERMISOS: OK';

