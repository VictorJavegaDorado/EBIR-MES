/*
Pruebas 011 - cambio pendiente y finalizacion de sesion de turno.
Estado: preparado para revision; no ejecutado.
Requiere haber completado 02_SALIDAS_Y_RETORNO.sql.
No llama a NAV, RFID, dispositivos ni impresoras.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 53300, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'prod.registrar_entrada_productiva', N'P') IS NULL
 OR OBJECT_ID(N'prod.marcar_cambio_turno_pendiente', N'P') IS NULL
 OR OBJECT_ID(N'prod.finalizar_sesion_turno', N'P') IS NULL
 OR OBJECT_ID(N'prod.cancelar_reserva_palet', N'P') IS NULL
    THROW 53301, 'Faltan procedimientos requeridos para las pruebas 03.', 1;

IF (SELECT COUNT(*) FROM cfg.lineas WHERE codigo LIKE N'ZZ11-%') <> 6
 OR (SELECT COUNT(*) FROM seg.empleados WHERE codigo_nav LIKE N'ZZ11-%') <> 5
 OR (SELECT COUNT(*) FROM prod.ordenes WHERE numero_orden LIKE N'ZZ11-%') <> 4
    THROW 53302, 'Los fixtures 011 no existen o estan incompletos.', 1;

DECLARE
    @supervisor_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-SUP'),
    @operario_2_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP2'),
    @orden_turno_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ11-FL-TURNO'),
    @linea_5_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ11-L05'),
    @sesion_turno_id bigint =
        (SELECT s.sesion_linea_id
         FROM prod.sesiones_linea s
         JOIN prod.ordenes o ON o.orden_id = s.orden_id
         JOIN cfg.lineas l ON l.linea_id = s.linea_id
         WHERE o.numero_orden = N'ZZ11-FL-TURNO'
           AND l.codigo = N'ZZ11-L05'
           AND s.finalizada_utc IS NULL),
    @fecha_operativa_original date,
    @reserva_id bigint,
    @reserva_auxiliar_id bigint,
    @fichaje_operario_id bigint,
    @fichaje_supervisor_id bigint,
    @paro_operario_id bigint,
    @sustitucion_id bigint,
    @parada_linea_id bigint,
    @palet_auxiliar_id bigint,
    @operacion_auxiliar_id bigint,
    @etiqueta_auxiliar_id bigint,
    @fichajes_cerrados int,
    @cambio_marcado bit,
    @error_obtenido int,
    @trancount_despues int,
    @xact_state_despues int,
    @auditoria_antes int,
    @auditoria_despues int,
    @operaciones_nav_antes int,
    @correlacion uniqueidentifier,
    @ahora_madrid datetimeoffset(3) =
        SYSUTCDATETIME() AT TIME ZONE N'UTC'
                         AT TIME ZONE N'Romance Standard Time';

IF @supervisor_id IS NULL OR @operario_2_id IS NULL
 OR @orden_turno_id IS NULL OR @linea_5_id IS NULL
 OR @sesion_turno_id IS NULL
    THROW 53303, 'Falta el estado heredado requerido de los bloques 01-02.', 1;

SELECT @fecha_operativa_original = fecha_operativa
FROM prod.sesiones_linea
WHERE sesion_linea_id = @sesion_turno_id;

/*
Prepara la sesion. Si un intento anterior se detuvo despues de esta preparacion,
admite exclusivamente ese estado exacto para poder reanudar el bloque.
*/
IF NOT EXISTS
(
    SELECT 1 FROM prod.fichajes
    WHERE sesion_linea_id = @sesion_turno_id
)
AND NOT EXISTS
(
    SELECT 1 FROM prod.reservas_palet
    WHERE sesion_linea_id = @sesion_turno_id
)
BEGIN
    SET @correlacion = NEWID();
    EXEC prod.registrar_entrada_productiva
        @sesion_linea_id = @sesion_turno_id,
        @empleado_id = @operario_2_id,
        @correlacion_id = @correlacion,
        @fichaje_id = @fichaje_operario_id OUTPUT,
        @reserva_palet_id = @reserva_id OUTPUT;
END
ELSE
BEGIN
    SELECT @fichaje_operario_id = fichaje_id
    FROM prod.fichajes
    WHERE sesion_linea_id = @sesion_turno_id
      AND empleado_id = @operario_2_id
      AND salida_utc IS NULL
      AND estado = N'ABIERTO';

    SELECT @reserva_id = reserva_palet_id
    FROM prod.reservas_palet
    WHERE sesion_linea_id = @sesion_turno_id
      AND estado = N'ACTIVA';

    IF (SELECT COUNT(*) FROM prod.fichajes
        WHERE sesion_linea_id = @sesion_turno_id) <> 1
     OR (SELECT COUNT(*) FROM prod.reservas_palet
         WHERE sesion_linea_id = @sesion_turno_id) <> 1
     OR @fichaje_operario_id IS NULL
     OR @reserva_id IS NULL
     OR NOT EXISTS
     (
         SELECT 1 FROM prod.tramos_capacidad
         WHERE sesion_linea_id = @sesion_turno_id
           AND fin_utc IS NULL
           AND recursos_activos = 1
           AND motivo_inicio = N'PRIMER_RECURSO'
     )
        THROW 53304, 'La sesion de L05 tiene un estado parcial no reanudable.', 1;
END;

IF @fichaje_operario_id IS NULL OR @reserva_id IS NULL
    THROW 53305, 'No se pudo preparar la sesion de fin de turno.', 1;

/* D21: una fecha operativa futura garantiza que el limite no se alcanzo. */
UPDATE prod.sesiones_linea
SET fecha_operativa = DATEADD(DAY, 1, CONVERT(date, @ahora_madrid)),
    cambio_turno_pendiente = 0
WHERE sesion_linea_id = @sesion_turno_id;

SET @correlacion = NEWID();
SET @cambio_marcado = NULL;
SET @error_obtenido = NULL;
BEGIN TRY
    EXEC prod.marcar_cambio_turno_pendiente
        @sesion_linea_id = @sesion_turno_id,
        @correlacion_id = @correlacion,
        @cambio_marcado = @cambio_marcado OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;
SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error_obtenido <> 52002
 OR EXISTS
 (
     SELECT 1 FROM aud.eventos
     WHERE correlacion_id = @correlacion
       AND tipo_evento = N'CAMBIO_TURNO_PENDIENTE'
 )
 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
BEGIN
    UPDATE prod.sesiones_linea
    SET fecha_operativa = @fecha_operativa_original
    WHERE sesion_linea_id = @sesion_turno_id;
    THROW 53306, 'D21: marcado previo al limite no rechazado limpiamente.', 1;
END;

/* D22: una fecha operativa anterior garantiza que el limite se alcanzo. */
UPDATE prod.sesiones_linea
SET fecha_operativa = DATEADD(DAY, -1, CONVERT(date, @ahora_madrid))
WHERE sesion_linea_id = @sesion_turno_id;

SET @correlacion = NEWID();
SELECT @auditoria_antes = COUNT(*)
FROM aud.eventos
WHERE sesion_linea_id = @sesion_turno_id
  AND tipo_evento = N'CAMBIO_TURNO_PENDIENTE';

EXEC prod.marcar_cambio_turno_pendiente
    @sesion_linea_id = @sesion_turno_id,
    @correlacion_id = @correlacion,
    @cambio_marcado = @cambio_marcado OUTPUT;

SELECT @auditoria_despues = COUNT(*)
FROM aud.eventos
WHERE sesion_linea_id = @sesion_turno_id
  AND tipo_evento = N'CAMBIO_TURNO_PENDIENTE';

IF @cambio_marcado <> 1
 OR @auditoria_despues - @auditoria_antes <> 1
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.sesiones_linea
     WHERE sesion_linea_id = @sesion_turno_id
       AND cambio_turno_pendiente = 1
 )
    THROW 53307, 'D22: el cambio pendiente no se marco o audito una vez.', 1;

/* D23: segunda llamada idempotente, sin una segunda auditoria. */
SET @correlacion = NEWID();
EXEC prod.marcar_cambio_turno_pendiente
    @sesion_linea_id = @sesion_turno_id,
    @correlacion_id = @correlacion,
    @cambio_marcado = @cambio_marcado OUTPUT;

IF @cambio_marcado <> 0
 OR (SELECT COUNT(*) FROM aud.eventos
     WHERE sesion_linea_id = @sesion_turno_id
       AND tipo_evento = N'CAMBIO_TURNO_PENDIENTE') <> @auditoria_despues
    THROW 53308, 'D23: el segundo marcado no fue idempotente.', 1;

UPDATE prod.sesiones_linea
SET fecha_operativa = @fecha_operativa_original
WHERE sesion_linea_id = @sesion_turno_id;

/* D24: el marcado no cierra sesion, fichaje, tramo ni reserva. */
IF NOT EXISTS
(
    SELECT 1
    FROM prod.sesiones_linea s
    JOIN prod.fichajes f ON f.sesion_linea_id = s.sesion_linea_id
    JOIN prod.reservas_palet r ON r.sesion_linea_id = s.sesion_linea_id
    JOIN prod.tramos_capacidad tc ON tc.sesion_linea_id = s.sesion_linea_id
    WHERE s.sesion_linea_id = @sesion_turno_id
      AND s.finalizada_utc IS NULL
      AND s.cambio_turno_pendiente = 1
      AND f.fichaje_id = @fichaje_operario_id
      AND f.salida_utc IS NULL
      AND r.reserva_palet_id = @reserva_id
      AND r.estado = N'ACTIVA'
      AND tc.fin_utc IS NULL
)
    THROW 53309, 'D24: el marcado altero operaciones que debian seguir abiertas.', 1;

/* E25: no se puede finalizar mientras exista una reserva activa. */
SET @correlacion = NEWID();
SET @error_obtenido = NULL;
BEGIN TRY
    EXEC prod.finalizar_sesion_turno
        @sesion_linea_id = @sesion_turno_id,
        @supervisor_id = @supervisor_id,
        @correlacion_id = @correlacion,
        @fichajes_cerrados = @fichajes_cerrados OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;
SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error_obtenido <> 52109
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.reservas_palet
     WHERE reserva_palet_id = @reserva_id
       AND estado = N'ACTIVA'
 )
 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
    THROW 53310, 'E25: fin con reserva activa no rechazado limpiamente.', 1;

/* E26: el supervisor cancela la reserva con motivo y auditoria. */
SET @correlacion = NEWID();
EXEC prod.cancelar_reserva_palet
    @reserva_palet_id = @reserva_id,
    @supervisor_id = @supervisor_id,
    @motivo = N'ZZTEST 011 fin de turno',
    @correlacion_id = @correlacion;

IF NOT EXISTS
(
    SELECT 1
    FROM prod.reservas_palet
    WHERE reserva_palet_id = @reserva_id
      AND estado = N'CANCELADA'
      AND cancelada_por_empleado_id = @supervisor_id
      AND motivo_cancelacion = N'ZZTEST 011 fin de turno'
)
 OR (SELECT cantidad_reservada_activa
     FROM prod.ordenes WHERE orden_id = @orden_turno_id) <> 0
 OR NOT EXISTS
 (
     SELECT 1 FROM aud.eventos
     WHERE correlacion_id = @correlacion
       AND tipo_evento = N'RESERVA_PALET_CANCELADA'
 )
    THROW 53311, 'E26: cancelacion de reserva o auditoria incorrectas.', 1;

/*
E32: crea un palet auxiliar puramente local para alcanzar las validaciones
especificas de NAV y etiqueta. Se elimina antes del fin de turno.
*/
INSERT prod.reservas_palet
(
    orden_id, sesion_linea_id, cantidad_reservada, estado,
    creada_por_empleado_id, cerrada_utc
)
VALUES
(
    @orden_turno_id, @sesion_turno_id, 1, N'CONSUMIDA',
    @operario_2_id, SYSUTCDATETIME()
);
SET @reserva_auxiliar_id = SCOPE_IDENTITY();

INSERT prod.palets
(
    orden_id, sesion_linea_id, reserva_palet_id,
    numero_palet, codigo_visible, cantidad_buena,
    es_parcial, motivo_parcial, es_ultimo,
    cerrado_por_empleado_id, supervisor_responsable_id,
    autorizado_por_supervisor_id, estado
)
VALUES
(
    @orden_turno_id, @sesion_turno_id, @reserva_auxiliar_id,
    900011, CONCAT(N'ZZ11-TURNO-', CONVERT(nvarchar(36), NEWID())), 1,
    0, NULL, 0,
    @operario_2_id, @supervisor_id,
    NULL, N'CERRADO'
);
SET @palet_auxiliar_id = SCOPE_IDENTITY();

INSERT nav.operaciones
(
    clave_idempotencia, tipo, orden_id, palet_id,
    estado, payload
)
VALUES
(
    CONCAT(N'ZZTEST_011-TURNO-NAV-', CONVERT(nvarchar(36), NEWID())),
    N'SALIDA_PALET', @orden_turno_id, @palet_auxiliar_id,
    N'PENDIENTE', N'{"origen":"ZZTEST_011","envio_real":false}'
);
SET @operacion_auxiliar_id = SCOPE_IDENTITY();

SET @error_obtenido = NULL;
BEGIN TRY
    EXEC prod.finalizar_sesion_turno
        @sesion_linea_id = @sesion_turno_id,
        @supervisor_id = @supervisor_id,
        @correlacion_id = @correlacion,
        @fichajes_cerrados = @fichajes_cerrados OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;

DELETE nav.operaciones
WHERE operacion_nav_id = @operacion_auxiliar_id;

IF @error_obtenido <> 52110
 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53312, 'E32: salida NAV pendiente no rechazo el fin de turno.', 1;

INSERT imp.etiquetas
(
    tipo, orden_id, palet_id, codigo_visible,
    plantilla_codigo, plantilla_version, datos_etiqueta,
    estado, numero_copias
)
VALUES
(
    N'PALET', @orden_turno_id, @palet_auxiliar_id,
    CONCAT(N'ZZ11-ET-TURNO-', CONVERT(nvarchar(36), NEWID())),
    N'ZZTEST_011', 1, N'{"origen":"ZZTEST_011","impresion_real":false}',
    N'PENDIENTE_NAV', 1
);
SET @etiqueta_auxiliar_id = SCOPE_IDENTITY();

SET @error_obtenido = NULL;
BEGIN TRY
    EXEC prod.finalizar_sesion_turno
        @sesion_linea_id = @sesion_turno_id,
        @supervisor_id = @supervisor_id,
        @correlacion_id = @correlacion,
        @fichajes_cerrados = @fichajes_cerrados OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;

DELETE imp.etiquetas
WHERE etiqueta_id = @etiqueta_auxiliar_id;

DELETE prod.palets
WHERE palet_id = @palet_auxiliar_id;

DELETE prod.reservas_palet
WHERE reserva_palet_id = @reserva_auxiliar_id;

IF @error_obtenido <> 52111
 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53313, 'E32: etiqueta pendiente no rechazo el fin de turno.', 1;

/* Prepara operaciones abiertas que el fin de turno debe cerrar. */
INSERT prod.paros_operario
(
    fichaje_id, motivo, inicio_utc, estado
)
VALUES
(
    @fichaje_operario_id, N'WC', SYSUTCDATETIME(), N'ABIERTO'
);
SET @paro_operario_id = SCOPE_IDENTITY();

INSERT prod.fichajes
(
    sesion_linea_id, linea_id, empleado_id,
    entrada_utc, estado, cerrado_por_sistema
)
VALUES
(
    @sesion_turno_id, @linea_5_id, @supervisor_id,
    SYSUTCDATETIME(), N'ABIERTO', 0
);
SET @fichaje_supervisor_id = SCOPE_IDENTITY();

INSERT prod.sustituciones_capacidad
(
    sesion_linea_id, operario_sustituido_id,
    supervisor_sustituto_id, fichaje_operario_id,
    fichaje_supervisor_id, inicio_utc, estado, motivo
)
VALUES
(
    @sesion_turno_id, @operario_2_id,
    @supervisor_id, @fichaje_operario_id,
    @fichaje_supervisor_id, SYSUTCDATETIME(),
    N'ACTIVA', N'ZZTEST 011 cierre por fin de turno'
);
SET @sustitucion_id = SCOPE_IDENTITY();

INSERT prod.paradas_linea
(
    sesion_linea_id, tipo, inicio_utc,
    iniciada_por_empleado_id
)
VALUES
(
    @sesion_turno_id, N'STANDBY_ALMUERZO',
    SYSUTCDATETIME(), @supervisor_id
);
SET @parada_linea_id = SCOPE_IDENTITY();

/* E27-E31: finaliza, cierra operaciones, libera linea y no crea NAV parcial. */
SELECT @operaciones_nav_antes = COUNT(*)
FROM nav.operaciones
WHERE orden_id = @orden_turno_id;

SET @correlacion = NEWID();
EXEC prod.finalizar_sesion_turno
    @sesion_linea_id = @sesion_turno_id,
    @supervisor_id = @supervisor_id,
    @correlacion_id = @correlacion,
    @fichajes_cerrados = @fichajes_cerrados OUTPUT;

IF @fichajes_cerrados <> 2
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.sesiones_linea
     WHERE sesion_linea_id = @sesion_turno_id
       AND estado = N'FINALIZADA_TURNO'
       AND finalizada_utc IS NOT NULL
       AND motivo_fin = N'FIN_TURNO'
       AND cerrada_por_empleado_id = @supervisor_id
 )
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.estados_linea
     WHERE linea_id = @linea_5_id
       AND sesion_linea_id IS NULL
       AND estado = N'LIBRE'
 )
 OR EXISTS
 (
     SELECT 1 FROM prod.fichajes
     WHERE sesion_linea_id = @sesion_turno_id
       AND salida_utc IS NULL
 )
 OR EXISTS
 (
     SELECT 1 FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_turno_id
       AND fin_utc IS NULL
 )
 OR EXISTS
 (
     SELECT 1 FROM prod.paros_operario
     WHERE paro_operario_id = @paro_operario_id
       AND fin_utc IS NULL
 )
 OR EXISTS
 (
     SELECT 1 FROM prod.sustituciones_capacidad
     WHERE sustitucion_capacidad_id = @sustitucion_id
       AND fin_utc IS NULL
 )
 OR EXISTS
 (
     SELECT 1 FROM prod.paradas_linea
     WHERE parada_linea_id = @parada_linea_id
       AND fin_utc IS NULL
 )
    THROW 53314, 'E27-E29: finalizacion, cierres o liberacion incorrectos.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM prod.fichajes
    WHERE sesion_linea_id = @sesion_turno_id
      AND salida_utc IS NOT NULL
      AND estado = N'CERRADO'
      AND cerrado_por_sistema = 1
    GROUP BY sesion_linea_id
    HAVING COUNT(*) = 2
)
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.ordenes
     WHERE orden_id = @orden_turno_id
       AND estado IN (N'ABIERTA', N'PICO_PENDIENTE')
 )
 OR (SELECT COUNT(*) FROM nav.operaciones
     WHERE orden_id = @orden_turno_id) <> @operaciones_nav_antes
 OR EXISTS
 (
     SELECT 1 FROM nav.operaciones
     WHERE orden_id = @orden_turno_id
       AND tipo = N'CIERRE_FL'
 )
 OR NOT EXISTS
 (
     SELECT 1 FROM aud.eventos
     WHERE correlacion_id = @correlacion
       AND tipo_evento = N'SESION_FINALIZADA_TURNO'
       AND empleado_id = @supervisor_id
 )
    THROW 53315, 'E30-E31: orden, NAV o auditoria tras fin de turno incorrectos.', 1;

SELECT
    s.sesion_linea_id, l.codigo AS linea, o.numero_orden,
    s.estado AS estado_sesion, s.motivo_fin,
    el.estado AS estado_linea,
    (SELECT COUNT(*) FROM prod.fichajes f
     WHERE f.sesion_linea_id = s.sesion_linea_id
       AND f.salida_utc IS NULL) AS fichajes_abiertos,
    (SELECT COUNT(*) FROM prod.reservas_palet r
     WHERE r.sesion_linea_id = s.sesion_linea_id
       AND r.estado = N'ACTIVA') AS reservas_activas
FROM prod.sesiones_linea s
JOIN cfg.lineas l ON l.linea_id = s.linea_id
JOIN prod.ordenes o ON o.orden_id = s.orden_id
JOIN prod.estados_linea el ON el.linea_id = s.linea_id
WHERE s.sesion_linea_id = @sesion_turno_id;

PRINT N'PRUEBAS 011 CAMBIO Y FIN DE TURNO: OK';
