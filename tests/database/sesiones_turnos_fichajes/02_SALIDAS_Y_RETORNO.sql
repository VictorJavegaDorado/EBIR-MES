/*
Pruebas 011 - salidas productivas y retorno desde SIN_OPERARIOS.
Estado: preparado para revision; no ejecutado.
Requiere haber completado 01_APERTURA_Y_ENTRADAS.sql.
No llama a NAV, RFID, dispositivos ni impresoras.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 53200, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'prod.registrar_entrada_productiva', N'P') IS NULL
 OR OBJECT_ID(N'prod.registrar_salida_productiva', N'P') IS NULL
    THROW 53201, 'Los procedimientos 011B y 011C no estan instalados.', 1;

IF (SELECT COUNT(*) FROM cfg.lineas WHERE codigo LIKE N'ZZ11-%') <> 6
 OR (SELECT COUNT(*) FROM seg.empleados WHERE codigo_nav LIKE N'ZZ11-%') <> 5
 OR (SELECT COUNT(*) FROM prod.ordenes WHERE numero_orden LIKE N'ZZ11-%') <> 4
    THROW 53202, 'Los fixtures 011 no existen o estan incompletos.', 1;

DECLARE
    @supervisor_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-SUP'),
    @operario_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP1'),
    @operario_2_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP2'),
    @operario_3_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP3'),
    @sesion_normal_id bigint =
        (SELECT s.sesion_linea_id
         FROM prod.sesiones_linea s
         JOIN prod.ordenes o ON o.orden_id = s.orden_id
         JOIN cfg.lineas l ON l.linea_id = s.linea_id
         WHERE o.numero_orden = N'ZZ11-FL-NORMAL'
           AND l.codigo = N'ZZ11-L01'
           AND s.finalizada_utc IS NULL),
    @sesion_multi_a_id bigint =
        (SELECT s.sesion_linea_id
         FROM prod.sesiones_linea s
         JOIN prod.ordenes o ON o.orden_id = s.orden_id
         JOIN cfg.lineas l ON l.linea_id = s.linea_id
         WHERE o.numero_orden = N'ZZ11-FL-MULTI'
           AND l.codigo = N'ZZ11-L03'
           AND s.finalizada_utc IS NULL),
    @reserva_inicial_id bigint,
    @iniciada_utc_original datetime2(3),
    @fichaje_id bigint,
    @fichaje_supervisor_id bigint,
    @paro_operario_id bigint,
    @sustitucion_id bigint,
    @reserva_salida_id bigint,
    @recursos_activos int,
    @error_obtenido int,
    @auditoria_antes int,
    @auditoria_despues int,
    @fichaje_se_mantuvo_abierto bit,
    @correlacion uniqueidentifier;

IF @supervisor_id IS NULL OR @operario_1_id IS NULL
 OR @operario_2_id IS NULL OR @operario_3_id IS NULL
 OR @sesion_normal_id IS NULL OR @sesion_multi_a_id IS NULL
    THROW 53203, 'Falta el estado heredado requerido del bloque 01.', 1;

SELECT
    @reserva_inicial_id = reserva_palet_id
FROM prod.reservas_palet
WHERE sesion_linea_id = @sesion_normal_id
  AND estado = N'ACTIVA';

SELECT
    @iniciada_utc_original = iniciada_utc
FROM prod.sesiones_linea
WHERE sesion_linea_id = @sesion_normal_id;

IF @reserva_inicial_id IS NULL
 OR @iniciada_utc_original IS NULL
 OR (SELECT COUNT(*) FROM prod.fichajes
     WHERE sesion_linea_id = @sesion_normal_id
       AND salida_utc IS NULL) <> 2
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_normal_id
       AND fin_utc IS NULL
       AND recursos_activos = 2
       AND motivo_inicio = N'ENTRADA_RECURSO'
 )
    THROW 53204, 'El bloque 01 no dejo L01 con dos recursos y una reserva activa.', 1;

/* C16: sale OP2; queda OP1 y se abre un tramo con un recurso. */
SET @correlacion = NEWID();
SELECT @auditoria_antes = COUNT(*)
FROM aud.eventos
WHERE correlacion_id = @correlacion;

EXEC prod.registrar_salida_productiva
    @sesion_linea_id = @sesion_normal_id,
    @empleado_id = @operario_2_id,
    @correlacion_id = @correlacion,
    @recursos_activos = @recursos_activos OUTPUT;

SELECT @auditoria_despues = COUNT(*)
FROM aud.eventos
WHERE correlacion_id = @correlacion
  AND tipo_evento = N'FICHAJE_SALIDA_PRODUCTIVA';

IF @recursos_activos <> 1
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.fichajes
     WHERE sesion_linea_id = @sesion_normal_id
       AND empleado_id = @operario_2_id
       AND salida_utc IS NOT NULL
       AND estado = N'CERRADO'
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_normal_id
       AND fin_utc IS NULL
       AND recursos_activos = 1
       AND motivo_inicio = N'SALIDA_RECURSO'
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.sesiones_linea s
     JOIN prod.estados_linea el ON el.linea_id = s.linea_id
     WHERE s.sesion_linea_id = @sesion_normal_id
       AND s.estado = N'PRODUCIENDO'
       AND el.sesion_linea_id = s.sesion_linea_id
       AND el.estado = N'PRODUCIENDO'
 )
 OR @auditoria_despues - @auditoria_antes <> 1
    THROW 53205, 'C16: salida parcial, tramo, estados o auditoria incorrectos.', 1;

/* C17: sale el ultimo recurso; no queda tramo abierto y ambos estados cambian. */
SET @correlacion = NEWID();
EXEC prod.registrar_salida_productiva
    @sesion_linea_id = @sesion_normal_id,
    @empleado_id = @operario_1_id,
    @correlacion_id = @correlacion,
    @recursos_activos = @recursos_activos OUTPUT;

IF @recursos_activos <> 0
 OR EXISTS
 (
     SELECT 1
     FROM prod.fichajes
     WHERE sesion_linea_id = @sesion_normal_id
       AND salida_utc IS NULL
 )
 OR EXISTS
 (
     SELECT 1
     FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_normal_id
       AND fin_utc IS NULL
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.sesiones_linea s
     JOIN prod.estados_linea el ON el.linea_id = s.linea_id
     WHERE s.sesion_linea_id = @sesion_normal_id
       AND s.estado = N'SIN_OPERARIOS'
       AND el.sesion_linea_id = s.sesion_linea_id
       AND el.estado = N'SIN_OPERARIOS'
 )
    THROW 53206, 'C17: la salida del ultimo recurso no dejo SIN_OPERARIOS.', 1;

/* C18: OP1 regresa; no se duplica la reserva creada en el primer inicio. */
SET @correlacion = NEWID();
SET @fichaje_id = NULL;
SET @reserva_salida_id = NULL;

EXEC prod.registrar_entrada_productiva
    @sesion_linea_id = @sesion_normal_id,
    @empleado_id = @operario_1_id,
    @correlacion_id = @correlacion,
    @fichaje_id = @fichaje_id OUTPUT,
    @reserva_palet_id = @reserva_salida_id OUTPUT;

IF @fichaje_id IS NULL
 OR @reserva_salida_id IS NOT NULL
 OR (SELECT iniciada_utc FROM prod.sesiones_linea
     WHERE sesion_linea_id = @sesion_normal_id) <> @iniciada_utc_original
 OR (SELECT COUNT(*) FROM prod.reservas_palet
     WHERE sesion_linea_id = @sesion_normal_id) <> 1
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.reservas_palet
     WHERE reserva_palet_id = @reserva_inicial_id
       AND estado = N'ACTIVA'
       AND cantidad_reservada = 20
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_normal_id
       AND fin_utc IS NULL
       AND recursos_activos = 1
       AND motivo_inicio = N'RETORNO_RECURSO'
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.sesiones_linea s
     JOIN prod.estados_linea el ON el.linea_id = s.linea_id
     WHERE s.sesion_linea_id = @sesion_normal_id
       AND s.estado = N'PRODUCIENDO'
       AND el.sesion_linea_id = s.sesion_linea_id
       AND el.estado = N'PRODUCIENDO'
 )
    THROW 53207, 'C18: retorno, tramo o no duplicacion de reserva incorrectos.', 1;

/* C19: un paro abierto impide la salida y no cierra el fichaje. */
SELECT @fichaje_id = fichaje_id
FROM prod.fichajes
WHERE sesion_linea_id = @sesion_multi_a_id
  AND empleado_id = @operario_3_id
  AND salida_utc IS NULL;

IF @fichaje_id IS NULL
    THROW 53208, 'C19: no existe el fichaje abierto de OP3 heredado de 01.', 1;

INSERT prod.paros_operario
(
    fichaje_id, motivo, inicio_utc, estado
)
VALUES
(
    @fichaje_id, N'WC', SYSUTCDATETIME(), N'ABIERTO'
);
SET @paro_operario_id = SCOPE_IDENTITY();

SET @error_obtenido = NULL;
BEGIN TRY
    EXEC prod.registrar_salida_productiva
        @sesion_linea_id = @sesion_multi_a_id,
        @empleado_id = @operario_3_id,
        @correlacion_id = @correlacion,
        @recursos_activos = @recursos_activos OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;

SET @fichaje_se_mantuvo_abierto =
    CASE WHEN EXISTS
    (
        SELECT 1 FROM prod.fichajes
        WHERE fichaje_id = @fichaje_id
          AND salida_utc IS NULL
          AND estado = N'ABIERTO'
    ) THEN 1 ELSE 0 END;

DELETE prod.paros_operario
WHERE paro_operario_id = @paro_operario_id;

IF @error_obtenido <> 51908
 OR @fichaje_se_mantuvo_abierto <> 1
 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53209, 'C19: salida con paro no rechazada limpiamente.', 1;

/* C20: una sustitucion activa impide la salida del operario sustituido. */
INSERT prod.fichajes
(
    sesion_linea_id, linea_id, empleado_id,
    entrada_utc, estado, cerrado_por_sistema
)
SELECT
    s.sesion_linea_id, s.linea_id, @supervisor_id,
    SYSUTCDATETIME(), N'ABIERTO', 0
FROM prod.sesiones_linea s
WHERE s.sesion_linea_id = @sesion_multi_a_id;
SET @fichaje_supervisor_id = SCOPE_IDENTITY();

INSERT prod.sustituciones_capacidad
(
    sesion_linea_id, operario_sustituido_id,
    supervisor_sustituto_id, fichaje_operario_id,
    fichaje_supervisor_id, inicio_utc, estado, motivo
)
VALUES
(
    @sesion_multi_a_id, @operario_3_id,
    @supervisor_id, @fichaje_id,
    @fichaje_supervisor_id, SYSUTCDATETIME(),
    N'ACTIVA', N'ZZTEST 011 rechazo de salida'
);
SET @sustitucion_id = SCOPE_IDENTITY();

SET @error_obtenido = NULL;
BEGIN TRY
    EXEC prod.registrar_salida_productiva
        @sesion_linea_id = @sesion_multi_a_id,
        @empleado_id = @operario_3_id,
        @correlacion_id = @correlacion,
        @recursos_activos = @recursos_activos OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;

SET @fichaje_se_mantuvo_abierto =
    CASE WHEN EXISTS
    (
        SELECT 1 FROM prod.fichajes
        WHERE fichaje_id = @fichaje_id
          AND salida_utc IS NULL
          AND estado = N'ABIERTO'
    ) THEN 1 ELSE 0 END;

DELETE prod.sustituciones_capacidad
WHERE sustitucion_capacidad_id = @sustitucion_id;

DELETE prod.fichajes
WHERE fichaje_id = @fichaje_supervisor_id;

IF @error_obtenido <> 51909
 OR @fichaje_se_mantuvo_abierto <> 1
 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53210, 'C20: salida con sustitucion no rechazada limpiamente.', 1;

IF EXISTS
(
    SELECT 1
    FROM prod.paros_operario po
    JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
    JOIN prod.sesiones_linea s ON s.sesion_linea_id = f.sesion_linea_id
    JOIN prod.ordenes o ON o.orden_id = s.orden_id
    WHERE o.numero_orden LIKE N'ZZ11-%'
      AND po.fin_utc IS NULL
)
 OR EXISTS
(
    SELECT 1
    FROM prod.sustituciones_capacidad sc
    JOIN prod.sesiones_linea s ON s.sesion_linea_id = sc.sesion_linea_id
    JOIN prod.ordenes o ON o.orden_id = s.orden_id
    WHERE o.numero_orden LIKE N'ZZ11-%'
      AND sc.fin_utc IS NULL
)
    THROW 53211, 'Quedaron paros o sustituciones auxiliares abiertos.', 1;

SELECT
    s.sesion_linea_id, l.codigo AS linea, o.numero_orden,
    s.estado AS estado_sesion, el.estado AS estado_linea,
    (SELECT COUNT(*) FROM prod.fichajes f
     WHERE f.sesion_linea_id = s.sesion_linea_id
       AND f.salida_utc IS NULL) AS fichajes_abiertos,
    (SELECT COUNT(*) FROM prod.tramos_capacidad tc
     WHERE tc.sesion_linea_id = s.sesion_linea_id
       AND tc.fin_utc IS NULL) AS tramos_abiertos,
    (SELECT COUNT(*) FROM prod.reservas_palet r
     WHERE r.sesion_linea_id = s.sesion_linea_id
       AND r.estado = N'ACTIVA') AS reservas_activas
FROM prod.sesiones_linea s
JOIN cfg.lineas l ON l.linea_id = s.linea_id
JOIN prod.ordenes o ON o.orden_id = s.orden_id
JOIN prod.estados_linea el ON el.linea_id = s.linea_id
WHERE o.numero_orden LIKE N'ZZ11-%'
ORDER BY l.codigo;

PRINT N'PRUEBAS 011 SALIDAS Y RETORNO: OK';
