/*
Pruebas 011 - apertura de sesiones y entradas productivas.
Estado: preparado para revision; no ejecutado.
Requiere haber instalado 011A y 011B y creado los fixtures 011.
No llama a NAV, RFID, dispositivos ni impresoras.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 53100, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'prod.abrir_sesion_linea', N'P') IS NULL
 OR OBJECT_ID(N'prod.registrar_entrada_productiva', N'P') IS NULL
    THROW 53101, 'Los procedimientos 011A y 011B no estan instalados.', 1;

IF (SELECT COUNT(*) FROM cfg.lineas WHERE codigo LIKE N'ZZ11-%') <> 6
 OR (SELECT COUNT(*) FROM seg.empleados WHERE codigo_nav LIKE N'ZZ11-%') <> 5
 OR (SELECT COUNT(*) FROM prod.ordenes WHERE numero_orden LIKE N'ZZ11-%') <> 4
    THROW 53102, 'Los fixtures 011 no existen o estan incompletos.', 1;

IF EXISTS
(
    SELECT 1
    FROM prod.sesiones_linea s
    JOIN prod.ordenes o ON o.orden_id = s.orden_id
    WHERE o.numero_orden LIKE N'ZZ11-%'
)
    THROW 53103, 'Las pruebas 01 ya se iniciaron; limpiar antes de repetir.', 1;

DECLARE
    @supervisor_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-SUP'),
    @operario_1_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP1'),
    @operario_2_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP2'),
    @operario_3_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP3'),
    @dual_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-DUAL'),
    @orden_normal_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ11-FL-NORMAL'),
    @orden_multi_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ11-FL-MULTI'),
    @orden_turno_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ11-FL-TURNO'),
    @orden_print_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ11-FL-PRINT'),
    @linea_1_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ11-L01'),
    @linea_2_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ11-L02'),
    @linea_3_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ11-L03'),
    @linea_4_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ11-L04'),
    @linea_5_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ11-L05'),
    @linea_6_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ11-L06'),
    @formato_normal_id bigint =
        (SELECT f.formato_palet_orden_id
         FROM prod.formatos_palet_orden f
         JOIN prod.ordenes o ON o.orden_id = f.orden_id
         WHERE o.numero_orden = N'ZZ11-FL-NORMAL'),
    @formato_multi_id bigint =
        (SELECT f.formato_palet_orden_id
         FROM prod.formatos_palet_orden f
         JOIN prod.ordenes o ON o.orden_id = f.orden_id
         WHERE o.numero_orden = N'ZZ11-FL-MULTI'),
    @formato_turno_id bigint =
        (SELECT f.formato_palet_orden_id
         FROM prod.formatos_palet_orden f
         JOIN prod.ordenes o ON o.orden_id = f.orden_id
         WHERE o.numero_orden = N'ZZ11-FL-TURNO'),
    @formato_print_id bigint =
        (SELECT f.formato_palet_orden_id
         FROM prod.formatos_palet_orden f
         JOIN prod.ordenes o ON o.orden_id = f.orden_id
         WHERE o.numero_orden = N'ZZ11-FL-PRINT'),
    @sesion_normal_id bigint,
    @sesion_multi_a_id bigint,
    @sesion_multi_b_id bigint,
    @sesion_turno_id bigint,
    @sesion_print_id bigint,
    @sesion_salida bigint,
    @fichaje_id bigint,
    @reserva_id bigint,
    @reserva_inicial_id bigint,
    @error_obtenido int,
    @correlacion uniqueidentifier;

/* Tabla determinista de la regla horaria acordada. */
DECLARE @casos_hora TABLE
(
    hora time(0) NOT NULL,
    turno_esperado nvarchar(20) NOT NULL,
    dias_fecha_operativa int NOT NULL,
    fuera_horario_esperado bit NOT NULL
);

INSERT @casos_hora
VALUES
('05:59', N'TARDE', -1, 1),
('06:00', N'MANANA', 0, 0),
('13:59', N'MANANA', 0, 0),
('14:00', N'TARDE', 0, 0),
('21:59', N'TARDE', 0, 0),
('22:00', N'TARDE', 0, 1);

IF EXISTS
(
    SELECT 1
    FROM @casos_hora
    WHERE turno_esperado <>
          CASE WHEN hora >= '06:00' AND hora < '14:00'
               THEN N'MANANA' ELSE N'TARDE' END
       OR dias_fecha_operativa <>
          CASE WHEN hora < '06:00' THEN -1 ELSE 0 END
       OR fuera_horario_esperado <>
          CASE WHEN hora < '06:00' OR hora >= '22:00'
               THEN 1 ELSE 0 END
)
    THROW 53104, 'Fallo en la tabla determinista de la regla horaria.', 1;

/* A1: apertura normal valida. La confirmacion=1 permite ejecutar a cualquier hora. */
SET @correlacion = NEWID();
EXEC prod.abrir_sesion_linea
    @orden_id = @orden_normal_id,
    @linea_id = @linea_1_id,
    @formato_palet_orden_id = @formato_normal_id,
    @supervisor_id = @supervisor_id,
    @inicio_fuera_horario_confirmado = 1,
    @correlacion_id = @correlacion,
    @sesion_linea_id = @sesion_normal_id OUTPUT;

IF @sesion_normal_id IS NULL
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.sesiones_linea s
     JOIN prod.estados_linea el ON el.linea_id = s.linea_id
     WHERE s.sesion_linea_id = @sesion_normal_id
       AND s.estado = N'CARGADA'
       AND el.sesion_linea_id = s.sesion_linea_id
       AND el.estado = N'ORDEN_CARGADA'
 )
    THROW 53105, 'A1: la sesion normal no quedo correctamente cargada.', 1;

/* Verifica también la rama horaria real aplicada por el procedimiento. */
DECLARE
    @ahora_madrid datetimeoffset(3) =
        SYSUTCDATETIME() AT TIME ZONE N'UTC'
                         AT TIME ZONE N'Romance Standard Time',
    @turno_real_esperado nvarchar(20),
    @fecha_real_esperada date,
    @fuera_real_esperado bit;

SET @turno_real_esperado =
    CASE WHEN CONVERT(time(0), @ahora_madrid) >= '06:00'
              AND CONVERT(time(0), @ahora_madrid) < '14:00'
         THEN N'MANANA' ELSE N'TARDE' END;
SET @fecha_real_esperada =
    DATEADD(DAY,
            CASE WHEN CONVERT(time(0), @ahora_madrid) < '06:00'
                 THEN -1 ELSE 0 END,
            CONVERT(date, @ahora_madrid));
SET @fuera_real_esperado =
    CASE WHEN CONVERT(time(0), @ahora_madrid) < '06:00'
              OR CONVERT(time(0), @ahora_madrid) >= '22:00'
         THEN 1 ELSE 0 END;

IF NOT EXISTS
(
    SELECT 1
    FROM prod.sesiones_linea s
    JOIN cfg.turnos t ON t.turno_id = s.turno_id
    WHERE s.sesion_linea_id = @sesion_normal_id
      AND t.codigo = @turno_real_esperado
      AND s.fecha_operativa = @fecha_real_esperada
      AND s.cambio_turno_pendiente = @fuera_real_esperado
)
    THROW 53106, 'A1: turno, fecha operativa o marca fuera de horario incorrectos.', 1;

/* Utilidad repetida: cada rechazo debe devolver el codigo esperado y transaccion limpia. */

/* A2: misma linea ocupada. */
SET @error_obtenido = NULL;
BEGIN TRY
    SET @sesion_salida = NULL;
    EXEC prod.abrir_sesion_linea
        @orden_id = @orden_turno_id, @linea_id = @linea_1_id,
        @formato_palet_orden_id = @formato_turno_id,
        @supervisor_id = @supervisor_id,
        @inicio_fuera_horario_confirmado = 1,
        @correlacion_id = @correlacion,
        @sesion_linea_id = @sesion_salida OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;
IF @error_obtenido <> 51705 OR @sesion_salida IS NOT NULL
 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53107, 'A2: rechazo de linea ocupada incorrecto o transaccion sucia.', 1;

/* A3: una FL NORMAL no puede abrir otra linea. */
SET @error_obtenido = NULL;
SET @sesion_salida = NULL;
BEGIN TRY
    EXEC prod.abrir_sesion_linea
        @orden_id = @orden_normal_id, @linea_id = @linea_2_id,
        @formato_palet_orden_id = @formato_normal_id,
        @supervisor_id = @supervisor_id,
        @inicio_fuera_horario_confirmado = 1,
        @correlacion_id = @correlacion,
        @sesion_linea_id = @sesion_salida OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;
IF @error_obtenido <> 51710 OR @sesion_salida IS NOT NULL
 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53108, 'A3: rechazo multilínea de orden NORMAL incorrecto.', 1;

/* A4: la misma FL MULTILINEA puede abrir dos lineas distintas. */
EXEC prod.abrir_sesion_linea
    @orden_id = @orden_multi_id, @linea_id = @linea_3_id,
    @formato_palet_orden_id = @formato_multi_id,
    @supervisor_id = @supervisor_id,
    @inicio_fuera_horario_confirmado = 1,
    @correlacion_id = @correlacion,
    @sesion_linea_id = @sesion_multi_a_id OUTPUT;

EXEC prod.abrir_sesion_linea
    @orden_id = @orden_multi_id, @linea_id = @linea_4_id,
    @formato_palet_orden_id = @formato_multi_id,
    @supervisor_id = @supervisor_id,
    @inicio_fuera_horario_confirmado = 1,
    @correlacion_id = @correlacion,
    @sesion_linea_id = @sesion_multi_b_id OUTPUT;

IF @sesion_multi_a_id IS NULL OR @sesion_multi_b_id IS NULL
 OR @sesion_multi_a_id = @sesion_multi_b_id
    THROW 53109, 'A4: no se abrieron las dos sesiones MULTILINEA.', 1;

/* A5: estado operativo bloqueado. Se restaura siempre el fixture. */
UPDATE prod.estados_linea
SET estado = N'BLOQUEADA', motivo_bloqueo = N'ZZTEST 011 bloqueo temporal'
WHERE linea_id = @linea_5_id;

SET @error_obtenido = NULL;
SET @sesion_salida = NULL;
BEGIN TRY
    EXEC prod.abrir_sesion_linea
        @orden_id = @orden_turno_id, @linea_id = @linea_5_id,
        @formato_palet_orden_id = @formato_turno_id,
        @supervisor_id = @supervisor_id,
        @inicio_fuera_horario_confirmado = 1,
        @correlacion_id = @correlacion,
        @sesion_linea_id = @sesion_salida OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;

UPDATE prod.estados_linea
SET estado = N'LIBRE', motivo_bloqueo = NULL
WHERE linea_id = @linea_5_id
  AND sesion_linea_id IS NULL;

IF @error_obtenido <> 51705 OR @sesion_salida IS NOT NULL
 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53110, 'A5: rechazo de linea bloqueada incorrecto.', 1;

/* A6: formato de otra orden. */
SET @error_obtenido = NULL;
SET @sesion_salida = NULL;
BEGIN TRY
    EXEC prod.abrir_sesion_linea
        @orden_id = @orden_turno_id, @linea_id = @linea_5_id,
        @formato_palet_orden_id = @formato_print_id,
        @supervisor_id = @supervisor_id,
        @inicio_fuera_horario_confirmado = 1,
        @correlacion_id = @correlacion,
        @sesion_linea_id = @sesion_salida OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;
IF @error_obtenido <> 51708 OR @sesion_salida IS NOT NULL
 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53111, 'A6: rechazo de formato ajeno incorrecto.', 1;

/* Abre las sesiones reservadas para pruebas posteriores. */
EXEC prod.abrir_sesion_linea
    @orden_id = @orden_turno_id, @linea_id = @linea_5_id,
    @formato_palet_orden_id = @formato_turno_id,
    @supervisor_id = @supervisor_id,
    @inicio_fuera_horario_confirmado = 1,
    @correlacion_id = @correlacion,
    @sesion_linea_id = @sesion_turno_id OUTPUT;

EXEC prod.abrir_sesion_linea
    @orden_id = @orden_print_id, @linea_id = @linea_6_id,
    @formato_palet_orden_id = @formato_print_id,
    @supervisor_id = @supervisor_id,
    @inicio_fuera_horario_confirmado = 1,
    @correlacion_id = @correlacion,
    @sesion_linea_id = @sesion_print_id OUTPUT;

/* B8-B10: primer operario, primera reserva y tramo de un recurso. */
SET @correlacion = NEWID();
EXEC prod.registrar_entrada_productiva
    @sesion_linea_id = @sesion_normal_id,
    @empleado_id = @operario_1_id,
    @correlacion_id = @correlacion,
    @fichaje_id = @fichaje_id OUTPUT,
    @reserva_palet_id = @reserva_id OUTPUT;
SET @reserva_inicial_id = @reserva_id;

IF @fichaje_id IS NULL OR @reserva_inicial_id IS NULL
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.reservas_palet
     WHERE reserva_palet_id = @reserva_inicial_id
       AND cantidad_reservada = 20
       AND estado = N'ACTIVA'
 )
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_normal_id
       AND fin_utc IS NULL
       AND recursos_activos = 1
       AND motivo_inicio = N'PRIMER_RECURSO'
 )
    THROW 53112, 'B8-B10: primer fichaje, reserva o tramo incorrecto.', 1;

/* B11: segundo operario; no debe crear otra reserva. */
SET @reserva_id = NULL;
EXEC prod.registrar_entrada_productiva
    @sesion_linea_id = @sesion_normal_id,
    @empleado_id = @operario_2_id,
    @correlacion_id = @correlacion,
    @fichaje_id = @fichaje_id OUTPUT,
    @reserva_palet_id = @reserva_id OUTPUT;

IF @reserva_id IS NOT NULL
 OR (SELECT COUNT(*) FROM prod.reservas_palet
     WHERE sesion_linea_id = @sesion_normal_id) <> 1
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_normal_id
       AND fin_utc IS NULL
       AND recursos_activos = 2
       AND motivo_inicio = N'ENTRADA_RECURSO'
 )
    THROW 53113, 'B11: segunda entrada, tramo o no duplicacion de reserva incorrectos.', 1;

/* B12: doble fichaje del mismo empleado. */
SET @error_obtenido = NULL;
BEGIN TRY
    EXEC prod.registrar_entrada_productiva
        @sesion_linea_id = @sesion_normal_id,
        @empleado_id = @operario_2_id,
        @correlacion_id = @correlacion,
        @fichaje_id = @fichaje_id OUTPUT,
        @reserva_palet_id = @reserva_id OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;
IF @error_obtenido <> 51808 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53114, 'B12: doble fichaje no rechazado limpiamente.', 1;

/* B13: OP3 entra en L03 y no puede entrar simultaneamente en L01. */
EXEC prod.registrar_entrada_productiva
    @sesion_linea_id = @sesion_multi_a_id,
    @empleado_id = @operario_3_id,
    @correlacion_id = @correlacion,
    @fichaje_id = @fichaje_id OUTPUT,
    @reserva_palet_id = @reserva_id OUTPUT;

SET @error_obtenido = NULL;
BEGIN TRY
    EXEC prod.registrar_entrada_productiva
        @sesion_linea_id = @sesion_normal_id,
        @empleado_id = @operario_3_id,
        @correlacion_id = @correlacion,
        @fichaje_id = @fichaje_id OUTPUT,
        @reserva_palet_id = @reserva_id OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;
IF @error_obtenido <> 51808 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53115, 'B13: fichaje simultaneo en dos lineas no rechazado limpiamente.', 1;

/* B14-B15: supervisor y rol dual no son entradas productivas ordinarias. */
SET @error_obtenido = NULL;
BEGIN TRY
    EXEC prod.registrar_entrada_productiva
        @sesion_linea_id = @sesion_normal_id,
        @empleado_id = @supervisor_id,
        @correlacion_id = @correlacion,
        @fichaje_id = @fichaje_id OUTPUT,
        @reserva_palet_id = @reserva_id OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;
IF @error_obtenido <> 51800 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53116, 'B14: entrada ordinaria de supervisor no rechazada.', 1;

SET @error_obtenido = NULL;
BEGIN TRY
    EXEC prod.registrar_entrada_productiva
        @sesion_linea_id = @sesion_normal_id,
        @empleado_id = @dual_id,
        @correlacion_id = @correlacion,
        @fichaje_id = @fichaje_id OUTPUT,
        @reserva_palet_id = @reserva_id OUTPUT;
END TRY
BEGIN CATCH
    SET @error_obtenido = ERROR_NUMBER();
END CATCH;
IF @error_obtenido <> 51800 OR @@TRANCOUNT <> 0 OR XACT_STATE() <> 0
    THROW 53117, 'B15: entrada ordinaria del empleado dual no rechazada.', 1;

SELECT
    s.sesion_linea_id, l.codigo AS linea, o.numero_orden,
    s.estado AS estado_sesion, el.estado AS estado_linea,
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
WHERE o.numero_orden LIKE N'ZZ11-%'
ORDER BY l.codigo;

PRINT N'PRUEBAS 011 APERTURA Y ENTRADAS: OK';
