/*
Pruebas 011 - desbloqueo posterior a impresion sin operarios.
Estado: preparado para revision; no ejecutado.
Requiere haber completado 03_CAMBIO_Y_FIN_TURNO.sql.
Todas las confirmaciones son locales; no llama a NAV ni a impresoras.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 53400, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'prod.registrar_entrada_productiva', N'P') IS NULL
 OR OBJECT_ID(N'prod.registrar_salida_productiva', N'P') IS NULL
 OR OBJECT_ID(N'prod.cerrar_palet', N'P') IS NULL
 OR OBJECT_ID(N'nav.confirmar_salida_palet', N'P') IS NULL
 OR OBJECT_ID(N'imp.confirmar_trabajo_impresion', N'P') IS NULL
    THROW 53401, 'Faltan procedimientos requeridos para las pruebas 04.', 1;

IF (SELECT COUNT(*) FROM cfg.lineas WHERE codigo LIKE N'ZZ11-%') <> 6
 OR (SELECT COUNT(*) FROM seg.empleados WHERE codigo_nav LIKE N'ZZ11-%') <> 5
 OR (SELECT COUNT(*) FROM prod.ordenes WHERE numero_orden LIKE N'ZZ11-%') <> 4
    THROW 53402, 'Los fixtures 011 no existen o estan incompletos.', 1;

DECLARE
    @operario_2_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP2'),
    @orden_print_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ11-FL-PRINT'),
    @linea_6_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ11-L06'),
    @sesion_print_id bigint =
        (SELECT s.sesion_linea_id
         FROM prod.sesiones_linea s
         JOIN prod.ordenes o ON o.orden_id = s.orden_id
         JOIN cfg.lineas l ON l.linea_id = s.linea_id
         WHERE o.numero_orden = N'ZZ11-FL-PRINT'
           AND l.codigo = N'ZZ11-L06'
           AND s.finalizada_utc IS NULL),
    @impresora_id bigint =
        (SELECT impresora_id FROM cfg.impresoras WHERE codigo = N'ZZ11-PRN'),
    @fichaje_id bigint,
    @reserva_inicial_id bigint,
    @reserva_siguiente_id bigint,
    @palet_id bigint,
    @operacion_nav_id bigint,
    @etiqueta_id bigint,
    @trabajo_impresion_id bigint,
    @recursos_activos int,
    @correlacion uniqueidentifier;

IF @operario_2_id IS NULL OR @orden_print_id IS NULL
 OR @linea_6_id IS NULL OR @sesion_print_id IS NULL
 OR @impresora_id IS NULL
    THROW 53403, 'Falta el estado heredado requerido de los bloques 01-03.', 1;

IF EXISTS
(
    SELECT 1
    FROM prod.fichajes
    WHERE sesion_linea_id = @sesion_print_id
)
 OR EXISTS
(
    SELECT 1
    FROM prod.reservas_palet
    WHERE sesion_linea_id = @sesion_print_id
)
 OR EXISTS
(
    SELECT 1
    FROM prod.palets
    WHERE sesion_linea_id = @sesion_print_id
)
    THROW 53404, 'La sesion de L06 ya fue utilizada; limpiar antes de repetir 04.', 1;

/* F33: inicia L06 y cierra un palet ordinario, no el ultimo. */
SET @correlacion = NEWID();
EXEC prod.registrar_entrada_productiva
    @sesion_linea_id = @sesion_print_id,
    @empleado_id = @operario_2_id,
    @correlacion_id = @correlacion,
    @fichaje_id = @fichaje_id OUTPUT,
    @reserva_palet_id = @reserva_inicial_id OUTPUT;

IF @fichaje_id IS NULL OR @reserva_inicial_id IS NULL
    THROW 53405, 'F33: no se pudo iniciar la sesion de impresion.', 1;

SET @correlacion = NEWID();
EXEC prod.cerrar_palet
    @reserva_palet_id = @reserva_inicial_id,
    @cantidad_buena = 20,
    @cerrado_por_empleado_id = @operario_2_id,
    @supervisor_autorizador_id = NULL,
    @es_parcial = 0,
    @motivo_parcial = NULL,
    @correlacion_id = @correlacion,
    @palet_id = @palet_id OUTPUT;

SELECT
    @operacion_nav_id = operacion_nav_id
FROM nav.operaciones
WHERE palet_id = @palet_id
  AND orden_id = @orden_print_id
  AND tipo = N'SALIDA_PALET';

SELECT
    @etiqueta_id = etiqueta_id
FROM imp.etiquetas
WHERE palet_id = @palet_id
  AND orden_id = @orden_print_id
  AND tipo = N'PALET';

SELECT
    @reserva_siguiente_id = reserva_palet_id
FROM prod.reservas_palet
WHERE sesion_linea_id = @sesion_print_id
  AND estado = N'ACTIVA';

IF @palet_id IS NULL OR @operacion_nav_id IS NULL
 OR @etiqueta_id IS NULL OR @reserva_siguiente_id IS NULL
 OR @reserva_siguiente_id = @reserva_inicial_id
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.palets
     WHERE palet_id = @palet_id
       AND cantidad_buena = 20
       AND es_ultimo = 0
       AND estado = N'CERRADO'
 )
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.reservas_palet
     WHERE reserva_palet_id = @reserva_inicial_id
       AND estado = N'CONSUMIDA'
 )
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.estados_linea
     WHERE linea_id = @linea_6_id
       AND sesion_linea_id = @sesion_print_id
       AND estado = N'PENDIENTE_NAV'
       AND motivo_bloqueo = N'SALIDA_PALET_PENDIENTE'
 )
    THROW 53406, 'F33: cierre ordinario o objetos derivados incorrectos.', 1;

/* F34: confirmacion NAV exclusivamente local; habilita etiqueta y trabajo. */
SET @correlacion = NEWID();
EXEC nav.confirmar_salida_palet
    @operacion_nav_id = @operacion_nav_id,
    @respuesta = N'{"origen":"ZZTEST_011","nav_real":false,"resultado":"OK"}',
    @identificador_externo = N'ZZ11-NAV-LOCAL-PRINT',
    @correlacion_id = @correlacion;

SELECT
    @trabajo_impresion_id = trabajo_impresion_id
FROM imp.trabajos_impresion
WHERE etiqueta_id = @etiqueta_id
  AND es_reimpresion = 0;

IF @trabajo_impresion_id IS NULL
 OR NOT EXISTS
 (
     SELECT 1 FROM nav.operaciones
     WHERE operacion_nav_id = @operacion_nav_id
       AND estado = N'CONFIRMADA'
       AND identificador_externo = N'ZZ11-NAV-LOCAL-PRINT'
 )
 OR NOT EXISTS
 (
     SELECT 1 FROM imp.etiquetas
     WHERE etiqueta_id = @etiqueta_id
       AND estado = N'LISTA'
       AND habilitada_utc IS NOT NULL
 )
 OR NOT EXISTS
 (
     SELECT 1 FROM imp.trabajos_impresion
     WHERE trabajo_impresion_id = @trabajo_impresion_id
       AND impresora_solicitada_id = @impresora_id
       AND estado = N'PENDIENTE'
 )
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.estados_linea
     WHERE linea_id = @linea_6_id
       AND estado = N'PENDIENTE_NAV'
 )
    THROW 53407, 'F34: confirmacion NAV local o preparacion de impresion incorrectas.', 1;

/* F35: sale el ultimo operario mientras la linea sigue PENDIENTE_NAV. */
SET @correlacion = NEWID();
EXEC prod.registrar_salida_productiva
    @sesion_linea_id = @sesion_print_id,
    @empleado_id = @operario_2_id,
    @correlacion_id = @correlacion,
    @recursos_activos = @recursos_activos OUTPUT;

IF @recursos_activos <> 0
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.sesiones_linea
     WHERE sesion_linea_id = @sesion_print_id
       AND estado = N'SIN_OPERARIOS'
       AND finalizada_utc IS NULL
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.estados_linea
     WHERE linea_id = @linea_6_id
       AND sesion_linea_id = @sesion_print_id
       AND estado = N'PENDIENTE_NAV'
 )
 OR EXISTS
 (
     SELECT 1 FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_print_id
       AND fin_utc IS NULL
 )
    THROW 53408, 'F35: salida durante PENDIENTE_NAV incorrecta.', 1;

/* F36-F37: impresion local y desbloqueo a SIN_OPERARIOS. */
SET @correlacion = NEWID();
EXEC imp.confirmar_trabajo_impresion
    @trabajo_impresion_id = @trabajo_impresion_id,
    @impresora_utilizada_id = @impresora_id,
    @correlacion_id = @correlacion;

IF NOT EXISTS
(
    SELECT 1
    FROM imp.trabajos_impresion
    WHERE trabajo_impresion_id = @trabajo_impresion_id
      AND impresora_utilizada_id = @impresora_id
      AND estado = N'COMPLETADO'
      AND procesado_utc IS NOT NULL
)
 OR NOT EXISTS
 (
     SELECT 1
     FROM imp.etiquetas
     WHERE etiqueta_id = @etiqueta_id
       AND estado = N'IMPRESA'
       AND impresa_utc IS NOT NULL
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.sesiones_linea s
     JOIN prod.estados_linea el ON el.linea_id = s.linea_id
     WHERE s.sesion_linea_id = @sesion_print_id
       AND s.estado = N'SIN_OPERARIOS'
       AND s.finalizada_utc IS NULL
       AND el.sesion_linea_id = s.sesion_linea_id
       AND el.estado = N'SIN_OPERARIOS'
       AND el.motivo_bloqueo IS NULL
 )
 OR EXISTS
 (
     SELECT 1
     FROM prod.fichajes
     WHERE sesion_linea_id = @sesion_print_id
       AND salida_utc IS NULL
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.reservas_palet
     WHERE reserva_palet_id = @reserva_siguiente_id
       AND estado = N'ACTIVA'
       AND cantidad_reservada = 20
 )
 OR EXISTS
 (
     SELECT 1
     FROM nav.operaciones
     WHERE orden_id = @orden_print_id
       AND tipo = N'CIERRE_FL'
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM aud.eventos
     WHERE correlacion_id = @correlacion
       AND tipo_evento = N'ETIQUETA_IMPRESA'
       AND entidad_id = @trabajo_impresion_id
 )
    THROW 53409, 'F36-F37: impresion o desbloqueo a SIN_OPERARIOS incorrectos.', 1;

SELECT
    s.sesion_linea_id, l.codigo AS linea, o.numero_orden,
    s.estado AS estado_sesion, el.estado AS estado_linea,
    p.numero_palet, p.cantidad_buena,
    n.estado AS estado_nav, e.estado AS estado_etiqueta,
    ti.estado AS estado_impresion,
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
JOIN prod.palets p ON p.sesion_linea_id = s.sesion_linea_id
JOIN nav.operaciones n ON n.palet_id = p.palet_id
JOIN imp.etiquetas e ON e.palet_id = p.palet_id
JOIN imp.trabajos_impresion ti ON ti.etiqueta_id = e.etiqueta_id
WHERE s.sesion_linea_id = @sesion_print_id;

PRINT N'PRUEBAS 011 DESBLOQUEO IMPRESION: OK';
