/*
Paquete 012E - Correccion supervisada de fichaje en sesion activa.
Estado: preparado para revision estatica; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

CREATE OR ALTER PROCEDURE prod.corregir_fichaje_turno_actual
    @fichaje_id bigint,
    @entrada_utc_corregida datetime2(3),
    @salida_utc_corregida datetime2(3) = NULL,
    @supervisor_id bigint,
    @motivo nvarchar(500),
    @correlacion_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @motivo = NULLIF(LTRIM(RTRIM(@motivo)), N'');

    IF @correlacion_id IS NULL
        THROW 52600, 'La correlacion es obligatoria.', 1;

    IF @entrada_utc_corregida IS NULL
        THROW 52601, 'La entrada corregida es obligatoria.', 1;

    IF @salida_utc_corregida IS NOT NULL
       AND @salida_utc_corregida < @entrada_utc_corregida
        THROW 52602, 'La salida corregida no puede ser anterior a la entrada.', 1;

    IF @motivo IS NULL
        THROW 52603, 'El motivo de correccion es obligatorio.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM seg.empleados e
        JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
        JOIN seg.roles r ON r.rol_id = er.rol_id
        WHERE e.empleado_id = @supervisor_id
          AND e.activo_nav = 1
          AND e.activo_mes = 1
          AND e.anonimizado_utc IS NULL
          AND er.hasta_utc IS NULL
          AND r.codigo = N'SUPERVISOR'
          AND r.activo = 1
    )
        THROW 52604, 'La correccion requiere un supervisor activo.', 1;

    DECLARE
        @ahora_utc datetime2(3) = SYSUTCDATETIME(),
        @sesion_linea_id bigint,
        @linea_id bigint,
        @empleado_id bigint,
        @entrada_anterior datetime2(3),
        @salida_anterior datetime2(3),
        @estado_anterior nvarchar(20),
        @cerrado_sistema_anterior bit,
        @orden_id bigint,
        @orden_bloqueada_id bigint,
        @sesion_orden_id bigint,
        @sesion_linea_bloqueada_id bigint,
        @sesion_cargada_utc datetime2(3),
        @estado_sesion nvarchar(30),
        @estado_linea nvarchar(30),
        @sesion_estado_linea_id bigint,
        @tiempo_nav decimal(12,1),
        @inicio_reconstruccion datetime2(3),
        @instante datetime2(3),
        @instante_siguiente datetime2(3),
        @recursos int,
        @recursos_actuales int,
        @parada_abierta bit,
        @capacidad decimal(18,4),
        @bloqueo_count int,
        @valor_anterior nvarchar(max),
        @valor_nuevo nvarchar(max);

    /*
    Lectura inicial sin bloqueo para obtener el contexto. Se revalida por
    completo dentro de la transaccion.
    */
    SELECT
        @sesion_linea_id = sesion_linea_id,
        @linea_id = linea_id,
        @empleado_id = empleado_id
    FROM prod.fichajes
    WHERE fichaje_id = @fichaje_id;

    IF @sesion_linea_id IS NULL
        THROW 52605, 'Fichaje no encontrado.', 1;

    SELECT @orden_id = orden_id
    FROM prod.sesiones_linea
    WHERE sesion_linea_id = @sesion_linea_id;

    IF @orden_id IS NULL
        THROW 52606, 'Sesion del fichaje no encontrada.', 1;

    IF @entrada_utc_corregida > @ahora_utc
       OR @salida_utc_corregida > @ahora_utc
        THROW 52607, 'La correccion no admite instantes futuros.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @orden_bloqueada_id = orden_id,
            @tiempo_nav = tiempo_ejecucion_nav_min
        FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
        WHERE orden_id = @orden_id;

        IF @orden_bloqueada_id IS NULL
            THROW 52608, 'Orden no encontrada.', 1;

        SELECT
            @sesion_orden_id = orden_id,
            @sesion_linea_bloqueada_id = linea_id,
            @sesion_cargada_utc = cargada_utc,
            @estado_sesion = estado
        FROM prod.sesiones_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id
          AND finalizada_utc IS NULL;

        IF @sesion_orden_id IS NULL
            THROW 52609, 'Solo se corrigen fichajes de una sesion activa.', 1;

        IF @sesion_orden_id <> @orden_id
           OR @sesion_linea_bloqueada_id <> @linea_id
            THROW 52610, 'La sesion cambio durante la operacion.', 1;

        IF @estado_sesion NOT IN
           (N'PRODUCIENDO', N'SIN_OPERARIOS', N'STANDBY', N'BLOQUEADA')
            THROW 52611, 'El estado de la sesion no admite correcciones.', 1;

        IF @entrada_utc_corregida < @sesion_cargada_utc
            THROW 52612, 'La entrada corregida precede a la carga de la sesion.', 1;

        SELECT
            @estado_linea = estado,
            @sesion_estado_linea_id = sesion_linea_id
        FROM prod.estados_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE linea_id = @linea_id;

        IF @sesion_estado_linea_id <> @sesion_linea_id
            THROW 52613, 'La linea no corresponde a la sesion activa.', 1;

        SELECT
            @entrada_anterior = entrada_utc,
            @salida_anterior = salida_utc,
            @estado_anterior = estado,
            @cerrado_sistema_anterior = cerrado_por_sistema
        FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
        WHERE fichaje_id = @fichaje_id
          AND sesion_linea_id = @sesion_linea_id
          AND linea_id = @linea_id
          AND empleado_id = @empleado_id;

        IF @entrada_anterior IS NULL
            THROW 52614, 'El fichaje cambio durante la operacion.', 1;

        /* Bloquea el conjunto de fichajes de la sesion antes de validar. */
        SELECT @recursos = COUNT(*)
        FROM prod.fichajes WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id;

        SELECT @bloqueo_count = COUNT(*)
        FROM prod.paros_operario po WITH (UPDLOCK, HOLDLOCK)
        JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
        WHERE f.sesion_linea_id = @sesion_linea_id;

        IF @salida_utc_corregida IS NULL
           AND EXISTS
           (
               SELECT 1
               FROM prod.fichajes
               WHERE empleado_id = @empleado_id
                 AND fichaje_id <> @fichaje_id
                 AND salida_utc IS NULL
           )
            THROW 52615, 'El empleado ya tiene otro fichaje abierto.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.fichajes f
            WHERE f.empleado_id = @empleado_id
              AND f.fichaje_id <> @fichaje_id
              AND f.entrada_utc <
                  COALESCE(@salida_utc_corregida, CONVERT(datetime2(3), '9999-12-31'))
              AND COALESCE(f.salida_utc, CONVERT(datetime2(3), '9999-12-31'))
                  > @entrada_utc_corregida
        )
            THROW 52616, 'El intervalo corregido solapa otro fichaje del empleado.', 1;

        /*
        Los paros y sustituciones ligados al fichaje deben seguir contenidos
        en el nuevo intervalo. Se bloquean antes de reconstruir los tramos.
        */
        IF EXISTS
        (
            SELECT 1
            FROM prod.paros_operario
            WHERE fichaje_id = @fichaje_id
              AND
              (
                  inicio_utc < @entrada_utc_corregida
                  OR
                  (
                      @salida_utc_corregida IS NOT NULL
                      AND COALESCE(fin_utc, @ahora_utc) > @salida_utc_corregida
                  )
              )
        )
            THROW 52617, 'La correccion dejaria un paro fuera del fichaje.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM prod.sustituciones_capacidad WITH (UPDLOCK, HOLDLOCK)
            WHERE fichaje_operario_id = @fichaje_id
               OR fichaje_supervisor_id = @fichaje_id
        )
        BEGIN
            IF EXISTS
            (
                SELECT 1
                FROM prod.sustituciones_capacidad
                WHERE
                    (fichaje_operario_id = @fichaje_id
                     OR fichaje_supervisor_id = @fichaje_id)
                  AND
                  (
                      inicio_utc < @entrada_utc_corregida
                      OR
                      (
                          @salida_utc_corregida IS NOT NULL
                          AND COALESCE(fin_utc, @ahora_utc) > @salida_utc_corregida
                      )
                  )
            )
                THROW 52618, 'La correccion dejaria una sustitucion fuera del fichaje.', 1;

            IF EXISTS
            (
                SELECT 1
                FROM prod.sustituciones_capacidad
                WHERE
                    (fichaje_operario_id = @fichaje_id
                     OR fichaje_supervisor_id = @fichaje_id)
                  AND fin_utc IS NULL
            )
                THROW 52619, 'No se corrige un fichaje ligado a sustitucion activa.', 1;
        END;

        SELECT @bloqueo_count = COUNT(*)
        FROM prod.sustituciones_capacidad WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id;

        SELECT @bloqueo_count = COUNT(*)
        FROM prod.paradas_linea WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id;

        SELECT @bloqueo_count = COUNT(*)
        FROM prod.tramos_capacidad WITH (UPDLOCK, HOLDLOCK)
        WHERE sesion_linea_id = @sesion_linea_id;

        /* Revalida y bloquea al supervisor dentro de la transaccion. */
        IF NOT EXISTS
        (
            SELECT 1
            FROM seg.empleados e WITH (UPDLOCK, HOLDLOCK)
            JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
            JOIN seg.roles r ON r.rol_id = er.rol_id
            WHERE e.empleado_id = @supervisor_id
              AND e.activo_nav = 1
              AND e.activo_mes = 1
              AND e.anonimizado_utc IS NULL
              AND er.hasta_utc IS NULL
              AND r.codigo = N'SUPERVISOR'
              AND r.activo = 1
        )
            THROW 52620, 'El corrector dejo de ser supervisor activo.', 1;

        SELECT @valor_anterior =
        (
            SELECT
                @entrada_anterior AS entrada_utc,
                @salida_anterior AS salida_utc,
                @estado_anterior AS estado,
                @cerrado_sistema_anterior AS cerrado_por_sistema
            FOR JSON PATH, INCLUDE_NULL_VALUES,
                WITHOUT_ARRAY_WRAPPER
        );

        UPDATE prod.fichajes
        SET entrada_utc = @entrada_utc_corregida,
            salida_utc = @salida_utc_corregida,
            estado = N'CORREGIDO',
            cerrado_por_sistema = 0,
            corregido_por_empleado_id = @supervisor_id,
            motivo_correccion = @motivo
        WHERE fichaje_id = @fichaje_id;

        /*
        Reconstruccion determinista. Los limites proceden de fichajes, paros,
        paradas de linea y el instante actual. Las sustituciones ya estan
        representadas por los fichajes de supervisor que enlazan.
        */
        DECLARE @limites TABLE
        (
            instante datetime2(3) NOT NULL PRIMARY KEY
        );

        INSERT @limites (instante)
        SELECT entrada_utc
        FROM prod.fichajes
        WHERE sesion_linea_id = @sesion_linea_id
          AND entrada_utc <= @ahora_utc
        UNION
        SELECT salida_utc
        FROM prod.fichajes
        WHERE sesion_linea_id = @sesion_linea_id
          AND salida_utc IS NOT NULL
          AND salida_utc <= @ahora_utc
        UNION
        SELECT po.inicio_utc
        FROM prod.paros_operario po
        JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
        WHERE f.sesion_linea_id = @sesion_linea_id
          AND po.inicio_utc <= @ahora_utc
        UNION
        SELECT po.fin_utc
        FROM prod.paros_operario po
        JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
        WHERE f.sesion_linea_id = @sesion_linea_id
          AND po.fin_utc IS NOT NULL
          AND po.fin_utc <= @ahora_utc
        UNION
        SELECT inicio_utc
        FROM prod.paradas_linea
        WHERE sesion_linea_id = @sesion_linea_id
          AND inicio_utc <= @ahora_utc
        UNION
        SELECT fin_utc
        FROM prod.paradas_linea
        WHERE sesion_linea_id = @sesion_linea_id
          AND fin_utc IS NOT NULL
          AND fin_utc <= @ahora_utc
        UNION
        SELECT @ahora_utc;

        SELECT @inicio_reconstruccion = MIN(entrada_utc)
        FROM prod.fichajes
        WHERE sesion_linea_id = @sesion_linea_id;

        IF @inicio_reconstruccion IS NULL
            THROW 52621, 'La sesion no conserva fichajes para reconstruir.', 1;

        DELETE FROM prod.tramos_capacidad
        WHERE sesion_linea_id = @sesion_linea_id;

        DECLARE limites_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT instante
            FROM @limites
            WHERE instante >= @inicio_reconstruccion
            ORDER BY instante;

        OPEN limites_cursor;
        FETCH NEXT FROM limites_cursor INTO @instante;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SELECT @instante_siguiente = MIN(instante)
            FROM @limites
            WHERE instante > @instante;

            IF @instante_siguiente IS NOT NULL
            BEGIN
                SELECT @recursos = COUNT(*)
                FROM prod.fichajes f
                WHERE f.sesion_linea_id = @sesion_linea_id
                  AND f.entrada_utc <= @instante
                  AND (f.salida_utc IS NULL OR f.salida_utc > @instante)
                  AND NOT EXISTS
                  (
                      SELECT 1
                      FROM prod.paros_operario po
                      WHERE po.fichaje_id = f.fichaje_id
                        AND po.inicio_utc <= @instante
                        AND (po.fin_utc IS NULL OR po.fin_utc > @instante)
                  );

                SET @parada_abierta =
                    CASE WHEN EXISTS
                    (
                        SELECT 1
                        FROM prod.paradas_linea pl
                        WHERE pl.sesion_linea_id = @sesion_linea_id
                          AND pl.inicio_utc <= @instante
                          AND (pl.fin_utc IS NULL OR pl.fin_utc > @instante)
                    )
                    THEN 1 ELSE 0 END;

                IF @recursos > 0 AND @parada_abierta = 0
                BEGIN
                    SET @capacidad =
                        CONVERT(decimal(18,4),
                                (CONVERT(decimal(18,4), 60) / @tiempo_nav)
                                * @recursos);

                    INSERT prod.tramos_capacidad
                    (
                        sesion_linea_id, inicio_utc, fin_utc,
                        recursos_activos, tiempo_nav_min_unidad,
                        capacidad_teorica_hora, segundos_productivos,
                        motivo_inicio
                    )
                    VALUES
                    (
                        @sesion_linea_id, @instante, @instante_siguiente,
                        @recursos, @tiempo_nav, @capacidad,
                        DATEDIFF(SECOND, @instante, @instante_siguiente),
                        N'RECONSTRUCCION_CORRECCION'
                    );
                END;
            END;

            FETCH NEXT FROM limites_cursor INTO @instante;
        END;

        CLOSE limites_cursor;
        DEALLOCATE limites_cursor;

        SELECT @recursos_actuales = COUNT(*)
        FROM prod.fichajes f
        WHERE f.sesion_linea_id = @sesion_linea_id
          AND f.entrada_utc <= @ahora_utc
          AND f.salida_utc IS NULL
          AND NOT EXISTS
          (
              SELECT 1
              FROM prod.paros_operario po
              WHERE po.fichaje_id = f.fichaje_id
                AND po.inicio_utc <= @ahora_utc
                AND po.fin_utc IS NULL
          );

        SET @parada_abierta =
            CASE WHEN EXISTS
            (
                SELECT 1
                FROM prod.paradas_linea
                WHERE sesion_linea_id = @sesion_linea_id
                  AND inicio_utc <= @ahora_utc
                  AND fin_utc IS NULL
            )
            THEN 1 ELSE 0 END;

        IF @recursos_actuales > 0 AND @parada_abierta = 0
        BEGIN
            SET @capacidad =
                CONVERT(decimal(18,4),
                        (CONVERT(decimal(18,4), 60) / @tiempo_nav)
                        * @recursos_actuales);

            INSERT prod.tramos_capacidad
            (
                sesion_linea_id, inicio_utc, recursos_activos,
                tiempo_nav_min_unidad, capacidad_teorica_hora,
                segundos_productivos, motivo_inicio
            )
            VALUES
            (
                @sesion_linea_id, @ahora_utc, @recursos_actuales,
                @tiempo_nav, @capacidad,
                0, N'RECONSTRUCCION_CORRECCION'
            );
        END;

        UPDATE prod.sesiones_linea
        SET iniciada_utc = @inicio_reconstruccion,
            estado =
                CASE
                    WHEN @parada_abierta = 1 THEN estado
                    WHEN @recursos_actuales > 0 THEN N'PRODUCIENDO'
                    ELSE N'SIN_OPERARIOS'
                END
        WHERE sesion_linea_id = @sesion_linea_id;

        IF @estado_linea NOT IN (N'PENDIENTE_NAV', N'BLOQUEADA')
           AND @parada_abierta = 0
            UPDATE prod.estados_linea
            SET estado =
                    CASE WHEN @recursos_actuales > 0
                         THEN N'PRODUCIENDO'
                         ELSE N'SIN_OPERARIOS' END,
                motivo_bloqueo = NULL,
                actualizado_utc = @ahora_utc
            WHERE linea_id = @linea_id
              AND sesion_linea_id = @sesion_linea_id;

        SELECT @valor_nuevo =
        (
            SELECT
                @entrada_utc_corregida AS entrada_utc,
                @salida_utc_corregida AS salida_utc,
                N'CORREGIDO' AS estado,
                @supervisor_id AS corregido_por_empleado_id,
                @recursos_actuales AS recursos_actuales
            FOR JSON PATH, INCLUDE_NULL_VALUES,
                WITHOUT_ARRAY_WRAPPER
        );

        EXEC aud.registrar_evento
            @tipo_evento = N'FICHAJE_CORREGIDO',
            @empleado_id = @supervisor_id,
            @rol_usado = N'SUPERVISOR',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'prod.fichajes',
            @entidad_id = @fichaje_id,
            @valor_anterior = @valor_anterior,
            @valor_nuevo = @valor_nuevo,
            @motivo = @motivo,
            @correlacion_id = @correlacion_id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'limites_cursor') >= 0
            CLOSE limites_cursor;
        IF CURSOR_STATUS('local', 'limites_cursor') > -3
            DEALLOCATE limites_cursor;
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NOT NULL
    GRANT EXECUTE ON OBJECT::prod.corregir_fichaje_turno_actual TO mes_runtime;
GO
