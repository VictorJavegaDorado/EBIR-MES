/*
Paquete 023A - Inicio atomico y lectura de la mesa de produccion.
Estado: preparado para revision estatica y validacion transaccional; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

INSERT prod.estados_linea
(
    linea_id,
    sesion_linea_id,
    estado,
    motivo_bloqueo,
    actualizado_utc
)
SELECT
    l.linea_id,
    NULL,
    N'LIBRE',
    NULL,
    SYSUTCDATETIME()
FROM cfg.lineas l
WHERE l.activa = 1
  AND NOT EXISTS
  (
      SELECT 1
      FROM prod.estados_linea el
      WHERE el.linea_id = l.linea_id
  );
GO

CREATE OR ALTER PROCEDURE prod.iniciar_o_incorporar_mesa
    @orden_id bigint,
    @linea_id bigint,
    @empleado_id bigint,
    @correlacion_id uniqueidentifier,
    @sesion_linea_id bigint OUTPUT,
    @fichaje_id bigint OUTPUT,
    @reserva_palet_id bigint OUTPUT,
    @sesion_creada bit OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @sesion_linea_id = NULL;
    SET @fichaje_id = NULL;
    SET @reserva_palet_id = NULL;
    SET @sesion_creada = 0;

    IF @correlacion_id IS NULL
        THROW 52709, 'La correlacion es obligatoria.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM seg.empleados e
        JOIN seg.empleados_roles er ON er.empleado_id = e.empleado_id
        JOIN seg.roles r ON r.rol_id = er.rol_id
        WHERE e.empleado_id = @empleado_id
          AND e.activo_nav = 1
          AND e.activo_mes = 1
          AND e.anonimizado_utc IS NULL
          AND er.hasta_utc IS NULL
          AND r.codigo = N'OPERARIO'
          AND r.es_productivo = 1
          AND r.activo = 1
          AND NOT EXISTS
          (
              SELECT 1
              FROM seg.empleados_roles ers
              JOIN seg.roles rs ON rs.rol_id = ers.rol_id
              WHERE ers.empleado_id = e.empleado_id
                AND ers.hasta_utc IS NULL
                AND rs.codigo = N'SUPERVISOR'
                AND rs.activo = 1
          )
    )
        THROW 52700, 'La mesa requiere un operario productivo activo.', 1;

    DECLARE
        @ahora_utc datetime2(3) = SYSUTCDATETIME(),
        @ahora_madrid datetimeoffset(3),
        @hora_madrid time(0),
        @fecha_madrid date,
        @turno_codigo nvarchar(20),
        @turno_id smallint,
        @estado_orden nvarchar(30),
        @modo_trabajo nvarchar(20),
        @estado_linea nvarchar(30),
        @sesion_estado_linea_id bigint,
        @sesion_orden_id bigint,
        @sesion_linea_bloqueada_id bigint,
        @formato_palet_orden_id bigint,
        @numero_formatos int,
        @resultado_bloqueo int,
        @recurso_bloqueo nvarchar(255),
        @valor_nuevo nvarchar(max),
        @evento_empleado_id bigint,
        @evento_orden_id bigint,
        @evento_linea_id bigint;

    BEGIN TRY
        BEGIN TRANSACTION;

        SET @recurso_bloqueo =
            CONCAT(N'MES:MESA:', CONVERT(nvarchar(36), @correlacion_id));

        EXEC @resultado_bloqueo = sys.sp_getapplock
            @Resource = @recurso_bloqueo,
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 5000;

        IF @resultado_bloqueo < 0
            THROW 52710, 'No se ha podido bloquear la operacion de mesa.', 1;

        SELECT TOP (1)
            @sesion_linea_id = ae.sesion_linea_id,
            @fichaje_id = ae.entidad_id,
            @evento_empleado_id = ae.empleado_id,
            @evento_orden_id = ae.orden_id,
            @evento_linea_id = ae.linea_id,
            @sesion_creada =
                CASE WHEN JSON_VALUE(ae.valor_nuevo, '$.sessionCreated') = N'true'
                     THEN 1 ELSE 0 END,
            @reserva_palet_id =
                TRY_CONVERT(bigint, JSON_VALUE(ae.valor_nuevo, '$.palletReservationId'))
        FROM aud.eventos ae WITH (UPDLOCK, HOLDLOCK)
        WHERE ae.correlacion_id = @correlacion_id
          AND ae.tipo_evento = N'MESA_OPERARIO_INCORPORADO'
        ORDER BY ae.evento_auditoria_id;

        IF @fichaje_id IS NOT NULL
        BEGIN
            IF @evento_empleado_id <> @empleado_id
               OR @evento_orden_id <> @orden_id
               OR @evento_linea_id <> @linea_id
                THROW 52709, 'La correlacion pertenece a otra operacion de mesa.', 1;

            COMMIT;
            RETURN;
        END;

        SELECT
            @estado_orden = o.estado,
            @modo_trabajo = o.modo_trabajo
        FROM prod.ordenes o WITH (UPDLOCK, HOLDLOCK)
        WHERE o.orden_id = @orden_id;

        IF @estado_orden IS NULL
           OR @estado_orden NOT IN (N'IMPORTADA', N'ABIERTA', N'PICO_PENDIENTE')
            THROW 52703, 'La orden no esta disponible para iniciar produccion.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM cfg.lineas WITH (UPDLOCK, HOLDLOCK)
            WHERE linea_id = @linea_id
              AND activa = 1
        )
            THROW 52704, 'La linea no existe o no esta activa.', 1;

        SELECT
            @estado_linea = el.estado,
            @sesion_estado_linea_id = el.sesion_linea_id
        FROM prod.estados_linea el WITH (UPDLOCK, HOLDLOCK)
        WHERE el.linea_id = @linea_id;

        IF @estado_linea IS NULL
            THROW 52705, 'La linea no dispone de estado operativo inicial.', 1;

        IF @sesion_estado_linea_id IS NOT NULL
        BEGIN
            SELECT
                @sesion_linea_id = s.sesion_linea_id,
                @sesion_orden_id = s.orden_id,
                @sesion_linea_bloqueada_id = s.linea_id
            FROM prod.sesiones_linea s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.sesion_linea_id = @sesion_estado_linea_id
              AND s.finalizada_utc IS NULL;

            IF @sesion_linea_id IS NULL
               OR @sesion_orden_id <> @orden_id
               OR @sesion_linea_bloqueada_id <> @linea_id
                THROW 52706, 'La linea esta ocupada por otra orden.', 1;
        END
        ELSE
        BEGIN
            IF @estado_linea <> N'LIBRE'
                THROW 52706, 'La linea no esta libre para iniciar la mesa.', 1;

            IF @modo_trabajo = N'NORMAL'
               AND EXISTS
               (
                   SELECT 1
                   FROM prod.sesiones_linea WITH (UPDLOCK, HOLDLOCK)
                   WHERE orden_id = @orden_id
                     AND finalizada_utc IS NULL
               )
                THROW 52708, 'La orden ya tiene una sesion activa en otra linea.', 1;

            SELECT
                @numero_formatos = COUNT(*),
                @formato_palet_orden_id = MIN(formato_palet_orden_id)
            FROM prod.formatos_palet_orden WITH (UPDLOCK, HOLDLOCK)
            WHERE orden_id = @orden_id
              AND codigo_formato = N'POK'
              AND es_predeterminado_nav = 1
              AND activo = 1;

            IF @numero_formatos <> 1
                THROW 52707, 'La orden no tiene un unico formato POK activo y predeterminado.', 1;

            SET @ahora_madrid =
                @ahora_utc AT TIME ZONE N'UTC'
                           AT TIME ZONE N'Romance Standard Time';
            SET @hora_madrid = CONVERT(time(0), @ahora_madrid);
            SET @fecha_madrid = CONVERT(date, @ahora_madrid);

            IF @hora_madrid < '06:00' OR @hora_madrid >= '22:00'
                THROW 52701, 'Inicio de produccion fuera del horario permitido.', 1;

            SET @turno_codigo =
                CASE WHEN @hora_madrid < '14:00' THEN N'MANANA' ELSE N'TARDE' END;

            SELECT @turno_id = turno_id
            FROM cfg.turnos WITH (UPDLOCK, HOLDLOCK)
            WHERE codigo = @turno_codigo
              AND activo = 1;

            IF @turno_id IS NULL
                THROW 52702, 'No existe el turno activo calculado para la sesion.', 1;

            INSERT prod.sesiones_linea
            (
                orden_id, linea_id, turno_id, formato_palet_orden_id,
                fecha_operativa, estado, cambio_turno_pendiente, cargada_utc,
                cargada_por_empleado_id
            )
            VALUES
            (
                @orden_id, @linea_id, @turno_id, @formato_palet_orden_id,
                @fecha_madrid, N'CARGADA', 0, @ahora_utc, @empleado_id
            );

            SET @sesion_linea_id = SCOPE_IDENTITY();
            SET @sesion_creada = 1;

            UPDATE prod.estados_linea
            SET sesion_linea_id = @sesion_linea_id,
                estado = N'ORDEN_CARGADA',
                motivo_bloqueo = NULL,
                actualizado_utc = @ahora_utc
            WHERE linea_id = @linea_id;

            EXEC aud.registrar_evento
                @tipo_evento = N'SESION_LINEA_ABIERTA_POR_OPERARIO',
                @empleado_id = @empleado_id,
                @rol_usado = N'OPERARIO',
                @linea_id = @linea_id,
                @orden_id = @orden_id,
                @sesion_linea_id = @sesion_linea_id,
                @entidad = N'prod.sesiones_linea',
                @entidad_id = @sesion_linea_id,
                @valor_nuevo = NULL,
                @motivo = NULL,
                @correlacion_id = @correlacion_id;
        END;

        EXEC prod.registrar_entrada_productiva
            @sesion_linea_id = @sesion_linea_id,
            @empleado_id = @empleado_id,
            @correlacion_id = @correlacion_id,
            @fichaje_id = @fichaje_id OUTPUT,
            @reserva_palet_id = @reserva_palet_id OUTPUT;

        SELECT @valor_nuevo =
        (
            SELECT
                @sesion_creada AS sessionCreated,
                @reserva_palet_id AS palletReservationId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC aud.registrar_evento
            @tipo_evento = N'MESA_OPERARIO_INCORPORADO',
            @empleado_id = @empleado_id,
            @rol_usado = N'OPERARIO',
            @linea_id = @linea_id,
            @orden_id = @orden_id,
            @sesion_linea_id = @sesion_linea_id,
            @entidad = N'prod.fichajes',
            @entidad_id = @fichaje_id,
            @valor_nuevo = @valor_nuevo,
            @motivo = NULL,
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

CREATE OR ALTER PROCEDURE prod.obtener_estado_mesa
    @orden_id bigint,
    @linea_id bigint
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @ahora_utc datetime2(3) = SYSUTCDATETIME(),
        @sesion_linea_id bigint;

    SELECT @sesion_linea_id = s.sesion_linea_id
    FROM prod.sesiones_linea s
    WHERE s.orden_id = @orden_id
      AND s.linea_id = @linea_id
      AND s.finalizada_utc IS NULL;

    IF @sesion_linea_id IS NULL
        RETURN;

    SELECT
        s.sesion_linea_id,
        s.orden_id,
        s.linea_id,
        s.estado,
        s.iniciada_utc,
        @ahora_utc AS servidor_utc,
        CONVERT(bigint, ISNULL((
            SELECT SUM(
                CASE WHEN tc.fin_utc IS NULL
                     THEN DATEDIFF_BIG(SECOND, tc.inicio_utc, @ahora_utc)
                     ELSE CONVERT(bigint, tc.segundos_productivos) END)
            FROM prod.tramos_capacidad tc
            WHERE tc.sesion_linea_id = s.sesion_linea_id
              AND tc.recursos_activos > 0
        ), 0)) AS segundos_productivos,
        CONVERT(int, ISNULL(re.recursos_activos, 0)) AS recursos_activos,
        CONVERT(decimal(18,4), ISNULL((
            SELECT TOP (1) tc.capacidad_teorica_hora
            FROM prod.tramos_capacidad tc
            WHERE tc.sesion_linea_id = s.sesion_linea_id
              AND tc.fin_utc IS NULL
            ORDER BY tc.tramo_capacidad_id DESC
        ), 0)) AS capacidad_teorica_hora,
        fp.codigo_formato,
        fp.unidades_por_palet
    FROM prod.sesiones_linea s
    JOIN prod.formatos_palet_orden fp
      ON fp.formato_palet_orden_id = s.formato_palet_orden_id
     AND fp.orden_id = s.orden_id
    OUTER APPLY prod.recursos_efectivos_sesion(s.sesion_linea_id) re
    WHERE s.sesion_linea_id = @sesion_linea_id;

    SELECT
        e.empleado_id,
        e.codigo_nav,
        e.nombre_completo,
        f.entrada_utc,
        CONVERT(bigint,
            DATEDIFF_BIG(SECOND, f.entrada_utc, @ahora_utc)
            - ISNULL((
                SELECT SUM(DATEDIFF_BIG(
                    SECOND,
                    po.inicio_utc,
                    COALESCE(po.fin_utc, @ahora_utc)))
                FROM prod.paros_operario po
                WHERE po.fichaje_id = f.fichaje_id
            ), 0)) AS segundos_productivos,
        CASE WHEN EXISTS
             (
                 SELECT 1
                 FROM prod.paros_operario po
                 WHERE po.fichaje_id = f.fichaje_id
                   AND po.fin_utc IS NULL
             ) THEN N'EN_PAUSA' ELSE N'PRODUCIENDO' END AS estado
    FROM prod.fichajes f
    JOIN seg.empleados e ON e.empleado_id = f.empleado_id
    WHERE f.sesion_linea_id = @sesion_linea_id
      AND f.salida_utc IS NULL
    ORDER BY f.entrada_utc, f.fichaje_id;
END;
GO

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NOT NULL
BEGIN
    GRANT EXECUTE ON OBJECT::prod.iniciar_o_incorporar_mesa TO mes_runtime;
    GRANT EXECUTE ON OBJECT::prod.obtener_estado_mesa TO mes_runtime;
END;
GO
