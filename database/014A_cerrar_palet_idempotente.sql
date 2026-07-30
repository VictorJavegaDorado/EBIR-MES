/*
Paquete 014A - Contrato idempotente para el cierre manual de palé.
Estado: preparado para revisión estática; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'prod.cerrar_palet', N'P') IS NULL
    THROW 51001, 'Falta el contrato delegado prod.cerrar_palet.', 1;

IF OBJECT_ID(N'aud.eventos', N'U') IS NULL
 OR OBJECT_ID(N'prod.palets', N'U') IS NULL
 OR OBJECT_ID(N'nav.operaciones', N'U') IS NULL
 OR OBJECT_ID(N'imp.etiquetas', N'U') IS NULL
    THROW 51002, 'Faltan objetos requeridos por el cierre idempotente.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
    THROW 51003, 'Falta el rol mes_runtime.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @definicion nvarchar(max) = N'
CREATE OR ALTER PROCEDURE prod.cerrar_palet_idempotente
    @reserva_palet_id bigint,
    @cantidad_buena int,
    @cerrado_por_empleado_id bigint,
    @supervisor_autorizador_id bigint = NULL,
    @es_parcial bit = 0,
    @motivo_parcial nvarchar(30) = NULL,
    @correlacion_id uniqueidentifier,
    @palet_id bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @palet_id = NULL;
    SET @motivo_parcial =
        UPPER(NULLIF(LTRIM(RTRIM(@motivo_parcial)), N''''));

    IF @correlacion_id IS NULL
        THROW 55400, ''La correlacion es obligatoria.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @resultado_bloqueo int,
            @recurso_bloqueo nvarchar(255),
            @evento_existente_tipo nvarchar(80),
            @evento_existente_entidad nvarchar(80),
            @evento_existente_id bigint;

        SET @recurso_bloqueo =
            CONCAT(N''MES:CORRELACION:'', CONVERT(nvarchar(36), @correlacion_id));

        EXEC @resultado_bloqueo = sys.sp_getapplock
            @Resource = @recurso_bloqueo,
            @LockMode = N''Exclusive'',
            @LockOwner = N''Transaction'',
            @LockTimeout = 10000,
            @DbPrincipal = N''public'';

        IF @resultado_bloqueo < 0
            THROW 55401, ''No se pudo obtener el bloqueo de idempotencia.'', 1;

        SELECT TOP (1)
            @evento_existente_tipo = tipo_evento,
            @evento_existente_entidad = entidad,
            @evento_existente_id = entidad_id
        FROM aud.eventos WITH (UPDLOCK, HOLDLOCK)
        WHERE correlacion_id = @correlacion_id
        ORDER BY evento_auditoria_id;

        IF @evento_existente_tipo IS NOT NULL
        BEGIN
            IF @evento_existente_tipo <> N''PALET_CERRADO''
               OR @evento_existente_entidad <> N''prod.palets''
               OR @evento_existente_id IS NULL
                THROW 55402, ''La correlacion ya pertenece a otra operacion.'', 1;

            SET @palet_id = @evento_existente_id;

            IF NOT EXISTS
            (
                SELECT 1
                FROM prod.palets p WITH (UPDLOCK, HOLDLOCK)
                WHERE p.palet_id = @palet_id
                  AND p.reserva_palet_id = @reserva_palet_id
                  AND p.cantidad_buena = @cantidad_buena
                  AND p.cerrado_por_empleado_id = @cerrado_por_empleado_id
                  AND p.es_parcial = @es_parcial
                  AND
                  (
                      p.autorizado_por_supervisor_id = @supervisor_autorizador_id
                      OR
                      (
                          p.autorizado_por_supervisor_id IS NULL
                          AND @supervisor_autorizador_id IS NULL
                      )
                  )
                  AND
                  (
                      p.motivo_parcial = @motivo_parcial
                      OR
                      (
                          p.motivo_parcial IS NULL
                          AND @motivo_parcial IS NULL
                      )
                  )
            )
                THROW 55403, ''La correlacion ya se uso con parametros diferentes.'', 1;

            IF NOT EXISTS
            (
                SELECT 1
                FROM nav.operaciones n WITH (UPDLOCK, HOLDLOCK)
                WHERE n.palet_id = @palet_id
                  AND n.tipo = N''SALIDA_PALET''
            )
               OR NOT EXISTS
            (
                SELECT 1
                FROM imp.etiquetas e WITH (UPDLOCK, HOLDLOCK)
                WHERE e.palet_id = @palet_id
                  AND e.tipo = N''PALET''
            )
                THROW 55404, ''El cierre idempotente anterior esta incompleto.'', 1;

            COMMIT TRANSACTION;
            RETURN;
        END;

        EXEC prod.cerrar_palet
            @reserva_palet_id = @reserva_palet_id,
            @cantidad_buena = @cantidad_buena,
            @cerrado_por_empleado_id = @cerrado_por_empleado_id,
            @supervisor_autorizador_id = @supervisor_autorizador_id,
            @es_parcial = @es_parcial,
            @motivo_parcial = @motivo_parcial,
            @correlacion_id = @correlacion_id,
            @palet_id = @palet_id OUTPUT;

        IF @palet_id IS NULL
            THROW 55404, ''El cierre no devolvio un palet completo.'', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        SET @palet_id = NULL;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql @definicion;

    REVOKE EXECUTE ON OBJECT::prod.cerrar_palet FROM mes_runtime;
    GRANT EXECUTE ON OBJECT::prod.cerrar_palet_idempotente TO mes_runtime;

    DECLARE @runtime_id int = DATABASE_PRINCIPAL_ID(N'mes_runtime');

    IF OBJECT_ID(N'prod.cerrar_palet_idempotente', N'P') IS NULL
        THROW 51004, 'No se creo prod.cerrar_palet_idempotente.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.database_permissions
        WHERE class = 1
          AND major_id = OBJECT_ID(N'prod.cerrar_palet_idempotente')
          AND minor_id = 0
          AND grantee_principal_id = @runtime_id
          AND permission_name = N'EXECUTE'
          AND state IN (N'G', N'W')
    )
        THROW 51005, 'mes_runtime no recibio el contrato idempotente.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM sys.database_permissions
        WHERE class = 1
          AND major_id = OBJECT_ID(N'prod.cerrar_palet')
          AND minor_id = 0
          AND grantee_principal_id = @runtime_id
          AND permission_name = N'EXECUTE'
          AND state IN (N'G', N'W')
    )
        THROW 51006, 'mes_runtime conserva el contrato anterior.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
