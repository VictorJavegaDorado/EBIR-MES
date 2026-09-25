/*
Paquete 052A - Lectura minima del seguimiento de solicitudes de material MES.
Base exclusiva: EBIR_MES_TEST.

Expone por sesion unicamente el contexto necesario para consultar en NAV el
estado de las solicitudes creadas desde el MES. La correlacion permanece en
aud.eventos y no se concede SELECT directo sobre el esquema de auditoria.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'[log].solicitudes_reaprovisionamiento', N'U') IS NULL
 OR OBJECT_ID(N'nav.componentes_orden', N'U') IS NULL
 OR OBJECT_ID(N'aud.eventos', N'U') IS NULL
    THROW 57400, 'El paquete 052A requiere solicitudes, componentes y auditoria.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
    THROW 57401, 'El principal mes_runtime no existe.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC(N'
CREATE OR ALTER PROCEDURE [log].listar_seguimiento_solicitudes_material_mes
    @sesion_linea_id bigint
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    IF @sesion_linea_id IS NULL OR @sesion_linea_id <= 0
        THROW 57402, ''La sesion de linea debe ser positiva.'', 1;

    SELECT TOP (10)
           r.solicitud_id,
           correlacion.correlacion_id,
           c.codigo_componente,
           c.descripcion,
           r.cantidad_solicitada,
           r.solicitada_utc
    FROM [log].solicitudes_reaprovisionamiento r
    INNER JOIN nav.componentes_orden c
      ON c.componente_orden_id = r.componente_orden_id
    CROSS APPLY
    (
        SELECT TOP (1) a.correlacion_id
        FROM aud.eventos a
        WHERE a.entidad = N''log.solicitudes_reaprovisionamiento''
          AND a.entidad_id = r.solicitud_id
          AND a.tipo_evento = N''REAPROVISIONAMIENTO_SOLICITADO''
        ORDER BY a.evento_auditoria_id
    ) correlacion
    WHERE r.sesion_linea_id = @sesion_linea_id
    ORDER BY r.solicitada_utc DESC, r.solicitud_id DESC;
END;');

    GRANT EXECUTE
        ON OBJECT::[log].listar_seguimiento_solicitudes_material_mes
        TO mes_runtime;

    IF OBJECT_ID(N'[log].listar_seguimiento_solicitudes_material_mes', N'P') IS NULL
        THROW 57403, 'No se ha creado el procedimiento de seguimiento.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.database_permissions dp
        WHERE dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
          AND dp.class = 1
          AND dp.major_id = OBJECT_ID(N'[log].listar_seguimiento_solicitudes_material_mes')
          AND dp.permission_name = N'EXECUTE'
          AND dp.state IN (N'G', N'W')
    )
        THROW 57404, 'No se ha concedido EXECUTE a mes_runtime.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
