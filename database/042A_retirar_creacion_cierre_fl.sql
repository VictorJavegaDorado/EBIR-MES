/*
Paquete 042A - Retirada general de la intencion CIERRE_FL sin consumidor.
Base exclusiva: EBIR_MES_TEST.

No modifica datos existentes ni contacta NAV. La impresion del ultimo palet
conserva la orden en PENDIENTE_CIERRE para el contrato local de finalizacion.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'imp.confirmar_trabajo_impresion', N'P') IS NULL
 OR OBJECT_ID(N'prod.recursos_efectivos_sesion', N'IF') IS NULL
 OR OBJECT_ID(N'aud.registrar_evento', N'P') IS NULL
    THROW 51081, 'El paquete 042A requiere impresion, recursos y auditoria.', 1;

IF EXISTS
(
    SELECT 1 FROM imp.trabajos_impresion WHERE estado=N'PROCESANDO'
)
    THROW 51082, 'Existen impresiones en proceso; no se puede instalar 042A.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC sys.sp_executesql N'
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
            @es_ultimo bit,
            @sesion_linea_id bigint,
            @linea_id bigint,
            @recursos_activos int,
            @estado_desbloqueo nvarchar(30);

        SELECT @etiqueta_id=etiqueta_id
        FROM imp.trabajos_impresion WITH (UPDLOCK, HOLDLOCK)
        WHERE trabajo_impresion_id=@trabajo_impresion_id
          AND estado IN (N''PENDIENTE'', N''PROCESANDO'');

        IF @etiqueta_id IS NULL
            THROW 51600, ''Trabajo de impresion no encontrado o no confirmable.'', 1;

        IF NOT EXISTS
        (
            SELECT 1 FROM cfg.impresoras
            WHERE impresora_id=@impresora_utilizada_id AND activa=1
        )
            THROW 51601, ''La impresora utilizada no existe o no esta activa.'', 1;

        SELECT
            @tipo_etiqueta=e.tipo,
            @orden_id=e.orden_id,
            @palet_id=e.palet_id
        FROM imp.etiquetas e WITH (UPDLOCK, HOLDLOCK)
        WHERE e.etiqueta_id=@etiqueta_id AND e.estado=N''LISTA'';

        IF @tipo_etiqueta IS NULL
            THROW 51602, ''La etiqueta no esta lista para confirmar su impresion.'', 1;

        UPDATE imp.trabajos_impresion
        SET impresora_utilizada_id=@impresora_utilizada_id,
            estado=N''COMPLETADO'',
            procesado_utc=SYSUTCDATETIME()
        WHERE trabajo_impresion_id=@trabajo_impresion_id;

        UPDATE imp.etiquetas
        SET estado=N''IMPRESA'', impresa_utc=SYSUTCDATETIME()
        WHERE etiqueta_id=@etiqueta_id;

        IF @tipo_etiqueta=N''PALET''
        BEGIN
            SELECT
                @es_ultimo=p.es_ultimo,
                @sesion_linea_id=p.sesion_linea_id,
                @linea_id=s.linea_id
            FROM prod.palets p
            JOIN prod.sesiones_linea s
              ON s.sesion_linea_id=p.sesion_linea_id
            WHERE p.palet_id=@palet_id AND p.orden_id=@orden_id;

            IF @es_ultimo=0
            BEGIN
                SELECT @recursos_activos=recursos_activos
                FROM prod.recursos_efectivos_sesion(@sesion_linea_id);

                SET @estado_desbloqueo=CASE WHEN @recursos_activos > 0
                    THEN N''PRODUCIENDO'' ELSE N''SIN_OPERARIOS'' END;

                UPDATE prod.sesiones_linea
                SET estado=@estado_desbloqueo
                WHERE sesion_linea_id=@sesion_linea_id
                  AND finalizada_utc IS NULL;

                UPDATE prod.estados_linea
                SET estado=@estado_desbloqueo,
                    motivo_bloqueo=NULL,
                    actualizado_utc=SYSUTCDATETIME()
                WHERE linea_id=@linea_id
                  AND sesion_linea_id=@sesion_linea_id
                  AND estado=N''PENDIENTE_NAV'';
            END
            ELSE
            BEGIN
                /*
                La salida del ultimo palet ya deja la orden PENDIENTE_CIERRE.
                Imprimir no crea escrituras NAV ni impide una impresion tardia
                posterior a la liberacion local de la orden.
                */
                UPDATE prod.estados_linea
                SET motivo_bloqueo=N''ORDEN_PENDIENTE_CIERRE'',
                    actualizado_utc=SYSUTCDATETIME()
                WHERE linea_id=@linea_id
                  AND sesion_linea_id=@sesion_linea_id
                  AND estado=N''PENDIENTE_NAV'';
            END;
        END;

        EXEC aud.registrar_evento
            @tipo_evento=N''ETIQUETA_IMPRESA'',
            @cuenta_dominio=N''EBIR\MES$'',
            @linea_id=@linea_id,
            @orden_id=@orden_id,
            @sesion_linea_id=@sesion_linea_id,
            @entidad=N''imp.trabajos_impresion'',
            @entidad_id=@trabajo_impresion_id,
            @correlacion_id=@correlacion_id;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    GRANT EXECUTE ON OBJECT::imp.confirmar_trabajo_impresion TO mes_runtime;

    DECLARE @definicion nvarchar(max)=
        OBJECT_DEFINITION(OBJECT_ID(N'imp.confirmar_trabajo_impresion'));
    IF @definicion LIKE N'%MES:CIERRE_FL:%'
     OR @definicion LIKE N'%N''CIERRE_FL''%'
     OR @definicion LIKE N'%SET estado = N''PENDIENTE_NAV''%orden_id%'
     OR @definicion NOT LIKE N'%ORDEN_PENDIENTE_CIERRE%'
     OR @definicion NOT LIKE N'%prod.recursos_efectivos_sesion%'
        THROW 51083, 'El contrato 042A no quedo publicado completamente.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
