/*
Pruebas 012 - desbloqueo posterior a impresion con fichaje en paro.
Estado: preparado para revision estatica; no ejecutado.
Requiere haber completado 00-03.
Todas las confirmaciones son locales; no llama a NAV ni a impresoras.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 54400, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'prod.registrar_entrada_productiva', N'P') IS NULL
 OR OBJECT_ID(N'prod.iniciar_paro_operario', N'P') IS NULL
 OR OBJECT_ID(N'prod.cerrar_palet', N'P') IS NULL
 OR OBJECT_ID(N'nav.confirmar_salida_palet', N'P') IS NULL
 OR OBJECT_ID(N'imp.confirmar_trabajo_impresion', N'P') IS NULL
    THROW 54401, 'Faltan procedimientos requeridos para las pruebas 04.', 1;

IF (SELECT COUNT(*) FROM cfg.lineas WHERE codigo LIKE N'ZZ12-%') <> 6
 OR (SELECT COUNT(*) FROM seg.empleados WHERE codigo_nav LIKE N'ZZ12-%') <> 6
 OR (SELECT COUNT(*) FROM prod.ordenes WHERE numero_orden LIKE N'ZZ12-%') <> 4
    THROW 54402, 'Los fixtures 012 no existen o estan incompletos.', 1;

DECLARE
    @operario_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-OP3'),
    @supervisor_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-SUP'),
    @orden_print_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ12-FL-PRINT'),
    @linea_6_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ12-L06'),
    @formato_id bigint,
    @sesion_print_id bigint,
    @impresora_id bigint =
        (SELECT impresora_id FROM cfg.impresoras WHERE codigo = N'ZZ12-PRN'),
    @fichaje_id bigint,
    @reserva_inicial_id bigint,
    @reserva_siguiente_id bigint,
    @palet_id bigint,
    @operacion_nav_id bigint,
    @etiqueta_id bigint,
    @trabajo_impresion_id bigint,
    @paro_id bigint,
    @recursos_activos int,
    @correlacion uniqueidentifier;

SELECT @formato_id = formato_palet_orden_id
FROM prod.formatos_palet_orden
WHERE orden_id = @orden_print_id
  AND activo = 1;

IF @operario_id IS NULL OR @supervisor_id IS NULL OR @orden_print_id IS NULL
 OR @linea_6_id IS NULL OR @formato_id IS NULL OR @impresora_id IS NULL
    THROW 54403, 'Faltan fixtures requeridos para 04.', 1;

IF EXISTS
(
    SELECT 1
    FROM prod.sesiones_linea
    WHERE linea_id = @linea_6_id
      AND finalizada_utc IS NULL
)
    THROW 54404, 'L06 ya tiene una sesion activa.', 1;

EXEC prod.abrir_sesion_linea
    @orden_id = @orden_print_id,
    @linea_id = @linea_6_id,
    @formato_palet_orden_id = @formato_id,
    @supervisor_id = @supervisor_id,
    @inicio_fuera_horario_confirmado = 1,
    @correlacion_id = '12040000-0000-0000-0000-000000000001',
    @sesion_linea_id = @sesion_print_id OUTPUT;

IF @sesion_print_id IS NULL
    THROW 54410, 'No se pudo abrir la sesion sintetica de L06.', 1;

/* D01: inicia L06 y cierra un palet ordinario, no el ultimo. */
SET @correlacion = NEWID();
EXEC prod.registrar_entrada_productiva
    @sesion_linea_id = @sesion_print_id,
    @empleado_id = @operario_id,
    @correlacion_id = @correlacion,
    @fichaje_id = @fichaje_id OUTPUT,
    @reserva_palet_id = @reserva_inicial_id OUTPUT;

IF @fichaje_id IS NULL OR @reserva_inicial_id IS NULL
    THROW 54405, 'D01: no se pudo iniciar la sesion de impresion.', 1;

SET @correlacion = NEWID();
EXEC prod.cerrar_palet
    @reserva_palet_id = @reserva_inicial_id,
    @cantidad_buena = 20,
    @cerrado_por_empleado_id = @operario_id,
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
    THROW 54406, 'D01: cierre ordinario o objetos derivados incorrectos.', 1;

/* D02: confirmacion NAV exclusivamente local; habilita etiqueta y trabajo. */
SET @correlacion = NEWID();
EXEC nav.confirmar_salida_palet
    @operacion_nav_id = @operacion_nav_id,
    @respuesta = N'{"origen":"ZZTEST_012","nav_real":false,"resultado":"OK"}',
    @identificador_externo = N'ZZ12-NAV-LOCAL-PRINT',
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
       AND identificador_externo = N'ZZ12-NAV-LOCAL-PRINT'
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
    THROW 54407, 'D02: confirmacion NAV local o preparacion de impresion incorrectas.', 1;

/* D03: el ultimo operario entra en WC mientras sigue PENDIENTE_NAV. */
SET @correlacion = NEWID();
EXEC prod.iniciar_paro_operario
    @sesion_linea_id = @sesion_print_id,
    @empleado_id = @operario_id,
    @motivo = N'WC',
    @correlacion_id = @correlacion,
    @paro_operario_id = @paro_id OUTPUT,
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
    THROW 54408, 'D03: paro durante PENDIENTE_NAV incorrecto.', 1;

/* D04: impresion local y desbloqueo a SIN_OPERARIOS. */
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
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.fichajes
     WHERE sesion_linea_id = @sesion_print_id
       AND salida_utc IS NULL
 )
 OR NOT EXISTS
 (
     SELECT 1
     FROM prod.paros_operario
     WHERE paro_operario_id = @paro_id
       AND fin_utc IS NULL
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
    THROW 54409, 'D04: impresion o desbloqueo a SIN_OPERARIOS incorrectos.', 1;

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

PRINT N'PRUEBAS 012 DESBLOQUEO IMPRESION: OK';

