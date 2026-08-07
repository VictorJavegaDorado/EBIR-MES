/*
Paquete 035A - Finalizacion de orden productiva y liberacion de linea.
Base exclusiva: EBIR_MES_TEST.

La accion Nueva orden completa la orden solo cuando produccion y todas las
salidas de palet ya estan confirmadas. Las etiquetas LISTA no bloquean la
liberacion: la impresion MES es un proceso independiente y puede continuar
despues de liberar la linea.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'prod.ordenes', N'U') IS NULL
 OR OBJECT_ID(N'prod.sesiones_linea', N'U') IS NULL
 OR OBJECT_ID(N'prod.estados_linea', N'U') IS NULL
 OR OBJECT_ID(N'prod.reservas_palet', N'U') IS NULL
 OR OBJECT_ID(N'prod.palets', N'U') IS NULL
 OR OBJECT_ID(N'nav.operaciones', N'U') IS NULL
 OR OBJECT_ID(N'imp.etiquetas', N'U') IS NULL
 OR OBJECT_ID(N'aud.registrar_evento', N'P') IS NULL
    THROW 51060, 'El paquete 035A requiere produccion, palets, NAV, etiquetas y auditoria.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
    THROW 51061, 'El principal mes_runtime no existe.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE prod.finalizar_orden_produccion
    @sesion_linea_id bigint,
    @correlacion_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @correlacion_id IS NULL
        THROW 52800, ''La correlacion es obligatoria.'', 1;

    DECLARE
        @ahora_utc datetime2(3) = SYSUTCDATETIME(),
        @orden_id bigint,
        @linea_id bigint,
        @orden_bloqueada_id bigint,
        @estado_orden nvarchar(30),
        @cantidad_objetivo int,
        @cantidad_buena int,
        @cantidad_reservada int,
        @sesion_bloqueada_id bigint,
        @estado_sesion nvarchar(30),
        @sesion_finalizada_utc datetime2(3),
        @estado_linea nvarchar(30),
        @sesion_estado_linea_id bigint,
        @palets_cerrados int,
        @cantidad_palets int,
        @palets_finales int;

    SELECT
        @orden_id = s.orden_id,
        @linea_id = s.linea_id
    FROM prod.sesiones_linea s
    WHERE s.sesion_linea_id = @sesion_linea_id;

    IF @orden_id IS NULL
        THROW 52801, ''Sesion de linea no encontrada.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* Orden global: orden -> sesion -> linea -> recursos -> palets -> integraciones. */
        SELECT
            @orden_bloqueada_id = o.orden_id,
            @estado_orden = o.estado,
            @cantidad_objetivo = o.cantidad_objetivo,
            @cantidad_buena = o.cantidad_buena_acumulada,
            @cantidad_reservada = o.cantidad_reservada_activa
        FROM prod.ordenes o WITH (UPDLOCK, HOLDLOCK)
        WHERE o.orden_id = @orden_id;

        IF @orden_bloqueada_id IS NULL
            THROW 52802, ''Orden no encontrada.'', 1;

        SELECT
            @sesion_bloqueada_id = s.sesion_linea_id,
            @estado_sesion = s.estado,
            @sesion_finalizada_utc = s.finalizada_utc
        FROM prod.sesiones_linea s WITH (UPDLOCK, HOLDLOCK)
        WHERE s.sesion_linea_id = @sesion_linea_id
          AND s.orden_id = @orden_id
          AND s.linea_id = @linea_id;

        IF @sesion_bloqueada_id IS NULL
            THROW 52801, ''Sesion de linea no encontrada.'', 1;

        SELECT
            @estado_linea = el.estado,
            @sesion_estado_linea_id = el.sesion_linea_id
        FROM prod.estados_linea el WITH (UPDLOCK, HOLDLOCK)
        WHERE el.linea_id = @linea_id;

        /* Repeticion segura despues de un exito confirmado. */
        IF @estado_orden = N''FINALIZADA''
           AND @estado_sesion = N''ORDEN_COMPLETADA''
           AND @sesion_finalizada_utc IS NOT NULL
        BEGIN
            COMMIT TRANSACTION;
            RETURN;
        END;

        IF @estado_orden <> N''PENDIENTE_CIERRE''
            THROW 52803, ''La orden no esta pendiente de cierre.'', 1;

        IF @estado_sesion <> N''SIN_OPERARIOS'' OR @sesion_finalizada_utc IS NOT NULL
            THROW 52804, ''La sesion debe estar activa y sin operarios.'', 1;

        IF @sesion_estado_linea_id <> @sesion_linea_id
            THROW 52805, ''La linea ya no corresponde a esta sesion.'', 1;

        IF @estado_linea NOT IN (N''SIN_OPERARIOS'', N''PENDIENTE_NAV'')
            THROW 52806, ''La linea no admite la liberacion de la orden.'', 1;

        IF @cantidad_buena <> @cantidad_objetivo OR @cantidad_reservada <> 0
            THROW 52807, ''La cantidad productiva de la orden no esta completa.'', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.fichajes f WITH (UPDLOCK, HOLDLOCK)
            WHERE f.sesion_linea_id = @sesion_linea_id
              AND f.salida_utc IS NULL
        )
        OR EXISTS
        (
            SELECT 1
            FROM prod.paros_operario po WITH (UPDLOCK, HOLDLOCK)
            JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
            WHERE f.sesion_linea_id = @sesion_linea_id
              AND po.fin_utc IS NULL
        )
        OR EXISTS
        (
            SELECT 1
            FROM prod.tramos_capacidad tc WITH (UPDLOCK, HOLDLOCK)
            WHERE tc.sesion_linea_id = @sesion_linea_id
              AND tc.fin_utc IS NULL
        )
            THROW 52808, ''La sesion mantiene recursos productivos abiertos.'', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.reservas_palet r WITH (UPDLOCK, HOLDLOCK)
            WHERE r.sesion_linea_id = @sesion_linea_id
              AND r.estado = N''ACTIVA''
        )
            THROW 52809, ''La sesion mantiene una reserva de palet activa.'', 1;

        SELECT
            @palets_cerrados = COUNT(*),
            @cantidad_palets = ISNULL(SUM(p.cantidad_buena), 0),
            @palets_finales = ISNULL(SUM(CONVERT(int, p.es_ultimo)), 0)
        FROM prod.palets p WITH (UPDLOCK, HOLDLOCK)
        WHERE p.sesion_linea_id = @sesion_linea_id
          AND p.orden_id = @orden_id
          AND p.estado = N''CERRADO'';

        IF @palets_cerrados <= 0
           OR @cantidad_palets <> @cantidad_objetivo
           OR @palets_finales <> 1
           OR EXISTS
              (
                  SELECT 1
                  FROM prod.palets p WITH (UPDLOCK, HOLDLOCK)
                  WHERE p.sesion_linea_id = @sesion_linea_id
                    AND p.orden_id = @orden_id
                    AND p.estado = N''CERRADO''
                    AND p.es_ultimo = 1
                    AND p.autorizado_por_supervisor_id IS NULL
              )
            THROW 52810, ''El ultimo palet no esta cerrado y autorizado correctamente.'', 1;

        IF EXISTS
        (
            SELECT p.palet_id
            FROM prod.palets p WITH (UPDLOCK, HOLDLOCK)
            LEFT JOIN nav.operaciones n WITH (UPDLOCK, HOLDLOCK)
              ON n.palet_id = p.palet_id
             AND n.orden_id = p.orden_id
             AND n.tipo = N''SALIDA_PALET''
            WHERE p.sesion_linea_id = @sesion_linea_id
              AND p.orden_id = @orden_id
              AND p.estado = N''CERRADO''
            GROUP BY p.palet_id
            HAVING COUNT(n.operacion_nav_id) <> 1
                OR SUM(CASE WHEN n.estado = N''CONFIRMADA'' THEN 1 ELSE 0 END) <> 1
        )
            THROW 52811, ''Todas las salidas de palet deben estar confirmadas.'', 1;

        IF EXISTS
        (
            SELECT p.palet_id
            FROM prod.palets p WITH (UPDLOCK, HOLDLOCK)
            LEFT JOIN imp.etiquetas e WITH (UPDLOCK, HOLDLOCK)
              ON e.palet_id = p.palet_id
             AND e.orden_id = p.orden_id
             AND e.tipo = N''PALET''
            WHERE p.sesion_linea_id = @sesion_linea_id
              AND p.orden_id = @orden_id
              AND p.estado = N''CERRADO''
            GROUP BY p.palet_id
            HAVING COUNT(e.etiqueta_id) <> 1
                OR SUM(CASE WHEN e.estado IN (N''LISTA'', N''IMPRESA'') THEN 1 ELSE 0 END) <> 1
        )
            THROW 52812, ''Todas las etiquetas deben estar listas o impresas.'', 1;

        UPDATE prod.ordenes
        SET estado = N''FINALIZADA'',
            finalizada_utc = @ahora_utc
        WHERE orden_id = @orden_id
          AND estado = N''PENDIENTE_CIERRE''
          AND cantidad_buena_acumulada = cantidad_objetivo
          AND cantidad_reservada_activa = 0;

        IF @@ROWCOUNT <> 1
            THROW 52813, ''La orden cambio durante la finalizacion.'', 1;

        UPDATE prod.sesiones_linea
        SET estado = N''ORDEN_COMPLETADA'',
            finalizada_utc = @ahora_utc,
            motivo_fin = N''ORDEN_COMPLETADA'',
            cerrada_por_empleado_id = NULL
        WHERE sesion_linea_id = @sesion_linea_id
          AND estado = N''SIN_OPERARIOS''
          AND finalizada_utc IS NULL;

        IF @@ROWCOUNT <> 1
            THROW 52813, ''La sesion cambio durante la finalizacion.'', 1;

        UPDATE prod.estados_linea
        SET sesion_linea_id = NULL,
            estado = N''LIBRE'',
            motivo_bloqueo = NULL,
            actualizado_utc = @ahora_utc
        WHERE linea_id = @linea_id
          AND sesion_linea_id = @sesion_linea_id
          AND estado IN (N''SIN_OPERARIOS'', N''PENDIENTE_NAV'');

        IF @@ROWCOUNT <> 1
            THROW 52813, ''La linea cambio durante la finalizacion.'', 1;

        EXEC aud.registrar_evento
            @tipo_evento = N''ORDEN_PRODUCCION_COMPLETADA'',
            @cuenta_dominio = N''MES'',
            @rol_usado = N''SISTEMA'',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N''prod.ordenes'',
            @entidad_id = @orden_id,
            @valor_anterior = N''{"estado":"PENDIENTE_CIERRE"}'',
            @valor_nuevo = N''{"estado":"FINALIZADA","linea":"LIBRE"}'',
            @motivo = N''Cantidad completa, salidas NAV confirmadas y mesa sin operarios'',
            @correlacion_id = @correlacion_id;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    GRANT EXECUTE ON OBJECT::prod.finalizar_orden_produccion TO mes_runtime;

    IF OBJECT_DEFINITION(OBJECT_ID(N'prod.finalizar_orden_produccion'))
       NOT LIKE N'%e.estado IN (N''LISTA'', N''IMPRESA'')%'
        THROW 51062, 'La finalizacion no desacopla correctamente la impresion.', 1;

    IF OBJECT_DEFINITION(OBJECT_ID(N'prod.finalizar_orden_produccion'))
       NOT LIKE N'%n.estado = N''CONFIRMADA''%'
        THROW 51063, 'La finalizacion no exige las salidas NAV confirmadas.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.database_permissions
        WHERE class = 1
          AND major_id = OBJECT_ID(N'prod.finalizar_orden_produccion')
          AND minor_id = 0
          AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
          AND permission_name = N'EXECUTE'
          AND state IN (N'G', N'W')
    )
        THROW 51064, 'mes_runtime no puede finalizar la orden productiva.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
