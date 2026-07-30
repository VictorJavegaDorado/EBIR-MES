/*
Paquete 014A - Contrato idempotente para el cierre manual de palé.
Estado: preparado para revisión estática; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

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
        UPPER(NULLIF(LTRIM(RTRIM(@motivo_parcial)), N''));

    IF @correlacion_id IS NULL
        THROW 55400, 'La correlacion es obligatoria.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @resultado_bloqueo int,
            @recurso_bloqueo nvarchar(255),
            @evento_existente_tipo nvarchar(80),
            @evento_existente_entidad nvarchar(80),
            @evento_existente_id bigint;

        SET @recurso_bloqueo =
            CONCAT(N'MES:CORRELACION:', CONVERT(nvarchar(36), @correlacion_id));

        EXEC @resultado_bloqueo = sys.sp_getapplock
            @Resource = @recurso_bloqueo,
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000,
            @DbPrincipal = N'public';

        IF @resultado_bloqueo < 0
            THROW 55401, 'No se pudo obtener el bloqueo de idempotencia.', 1;

        SELECT TOP (1)
            @evento_existente_tipo = tipo_evento,
            @evento_existente_entidad = entidad,
            @evento_existente_id = entidad_id
        FROM aud.eventos WITH (UPDLOCK, HOLDLOCK)
        WHERE correlacion_id = @correlacion_id
        ORDER BY evento_auditoria_id;

        IF @evento_existente_tipo IS NOT NULL
        BEGIN
            IF @evento_existente_tipo <> N'PALET_CERRADO'
               OR @evento_existente_entidad <> N'prod.palets'
               OR @evento_existente_id IS NULL
                THROW 55402, 'La correlacion ya pertenece a otra operacion.', 1;

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
                THROW 55403, 'La correlacion ya se uso con parametros diferentes.', 1;

            IF NOT EXISTS
            (
                SELECT 1
                FROM nav.operaciones n WITH (UPDLOCK, HOLDLOCK)
                WHERE n.palet_id = @palet_id
                  AND n.tipo = N'SALIDA_PALET'
            )
               OR NOT EXISTS
            (
                SELECT 1
                FROM imp.etiquetas e WITH (UPDLOCK, HOLDLOCK)
                WHERE e.palet_id = @palet_id
                  AND e.tipo = N'PALET'
            )
                THROW 55404, 'El cierre idempotente anterior esta incompleto.', 1;

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
            THROW 55404, 'El cierre no devolvio un palet completo.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        SET @palet_id = NULL;
        THROW;
    END CATCH;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NOT NULL
BEGIN
    REVOKE EXECUTE ON OBJECT::prod.cerrar_palet FROM mes_runtime;
    GRANT EXECUTE ON OBJECT::prod.cerrar_palet_idempotente TO mes_runtime;
END;
GO
