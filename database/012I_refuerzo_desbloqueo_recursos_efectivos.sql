/*
Paquete 012I - Desbloqueo posterior a impresion con recursos efectivos.
Estado: preparado para revision estatica; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO
CREATE OR ALTER PROCEDURE imp.confirmar_trabajo_impresion
    @trabajo_impresion_id bigint,
    @impresora_utilizada_id bigint,
    @correlacion_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

    DECLARE
        @etiqueta_id bigint,
        @tipo_etiqueta nvarchar(30),
        @orden_id bigint,
        @palet_id bigint,
        @palet_uid uniqueidentifier,
        @es_ultimo bit,
        @sesion_linea_id bigint,
        @linea_id bigint,
        @numero_orden nvarchar(30),
        @payload_cierre nvarchar(max),
        @recursos_activos int,
        @bloqueo_paros int,
        @estado_desbloqueo nvarchar(30);

    SELECT @etiqueta_id = etiqueta_id
    FROM imp.trabajos_impresion WITH (UPDLOCK, HOLDLOCK)
    WHERE trabajo_impresion_id = @trabajo_impresion_id
      AND estado IN (N'PENDIENTE', N'PROCESANDO');

    IF @etiqueta_id IS NULL
        THROW 51600, 'Trabajo de impresion no encontrado o no confirmable.', 1;

    IF NOT EXISTS
    (
        SELECT 1 FROM cfg.impresoras
        WHERE impresora_id = @impresora_utilizada_id
          AND activa = 1
    )
        THROW 51601, 'La impresora utilizada no existe o no esta activa.', 1;

    SELECT
        @tipo_etiqueta = e.tipo,
        @orden_id = e.orden_id,
        @palet_id = e.palet_id
    FROM imp.etiquetas e WITH (UPDLOCK, HOLDLOCK)
    WHERE e.etiqueta_id = @etiqueta_id
      AND e.estado = N'LISTA';

    IF @tipo_etiqueta IS NULL
        THROW 51602, 'La etiqueta no esta lista para confirmar su impresion.', 1;

    UPDATE imp.trabajos_impresion
    SET impresora_utilizada_id = @impresora_utilizada_id,
        estado = N'COMPLETADO',
        procesado_utc = SYSUTCDATETIME()
    WHERE trabajo_impresion_id = @trabajo_impresion_id;

    UPDATE imp.etiquetas
    SET estado = N'IMPRESA',
        impresa_utc = SYSUTCDATETIME()
    WHERE etiqueta_id = @etiqueta_id;

    IF @tipo_etiqueta = N'PALET'
    BEGIN
        SELECT
            @palet_uid = p.palet_uid,
            @es_ultimo = p.es_ultimo,
            @sesion_linea_id = p.sesion_linea_id,
            @linea_id = s.linea_id,
            @numero_orden = o.numero_orden
        FROM prod.palets p
        JOIN prod.sesiones_linea s ON s.sesion_linea_id = p.sesion_linea_id
        JOIN prod.ordenes o ON o.orden_id = p.orden_id
        WHERE p.palet_id = @palet_id
          AND p.orden_id = @orden_id;

        IF @es_ultimo = 0
        BEGIN
            SELECT @recursos_activos = COUNT(*)
            FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
            WHERE sesion_linea_id = @sesion_linea_id
              AND salida_utc IS NULL;

            SELECT @bloqueo_paros = COUNT(*)
            FROM prod.paros_operario po WITH (UPDLOCK, HOLDLOCK)
            JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
            WHERE f.sesion_linea_id = @sesion_linea_id
              AND po.fin_utc IS NULL;

            SELECT @recursos_activos = recursos_activos
            FROM prod.recursos_efectivos_sesion(@sesion_linea_id);

            SET @estado_desbloqueo =
                CASE WHEN @recursos_activos > 0
                     THEN N'PRODUCIENDO' ELSE N'SIN_OPERARIOS' END;

            UPDATE prod.sesiones_linea
            SET estado = @estado_desbloqueo
            WHERE sesion_linea_id = @sesion_linea_id
              AND finalizada_utc IS NULL;

            UPDATE prod.estados_linea
            SET estado = @estado_desbloqueo,
                motivo_bloqueo = NULL,
                actualizado_utc = SYSUTCDATETIME()
            WHERE linea_id = @linea_id
              AND sesion_linea_id = @sesion_linea_id
              AND estado = N'PENDIENTE_NAV';
        END
        ELSE
        BEGIN
            SELECT @payload_cierre =
            (
                SELECT
                    @orden_id AS orden_id,
                    @numero_orden AS numero_orden,
                    @palet_uid AS ultimo_palet_uid
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            IF NOT EXISTS
            (
                SELECT 1 FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
                WHERE clave_idempotencia = CONCAT(N'MES:CIERRE_FL:', CONVERT(nvarchar(20), @orden_id))
            )
                INSERT nav.operaciones
                (
                    clave_idempotencia, tipo, orden_id, estado,
                    payload, proximo_intento_utc
                )
                VALUES
                (
                    CONCAT(N'MES:CIERRE_FL:', CONVERT(nvarchar(20), @orden_id)),
                    N'CIERRE_FL', @orden_id, N'PENDIENTE',
                    @payload_cierre, SYSUTCDATETIME()
                );

            UPDATE prod.ordenes
            SET estado = N'PENDIENTE_NAV'
            WHERE orden_id = @orden_id;

            UPDATE prod.estados_linea
            SET estado = N'PENDIENTE_NAV',
                motivo_bloqueo = N'CIERRE_FL_PENDIENTE',
                actualizado_utc = SYSUTCDATETIME()
            WHERE linea_id = @linea_id
              AND sesion_linea_id = @sesion_linea_id;
        END;
    END;

    EXEC aud.registrar_evento
        @tipo_evento = N'ETIQUETA_IMPRESA',
        @cuenta_dominio = N'EBIR\MES$',
        @linea_id = @linea_id,
        @orden_id = @orden_id,
        @sesion_linea_id = @sesion_linea_id,
        @entidad = N'imp.trabajos_impresion',
        @entidad_id = @trabajo_impresion_id,
        @correlacion_id = @correlacion_id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO
