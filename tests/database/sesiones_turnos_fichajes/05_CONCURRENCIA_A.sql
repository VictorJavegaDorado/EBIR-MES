/*
Pruebas 011 - cliente A de concurrencia.
Estado: preparado para revision; no ejecutado.
Ejecutar en una conexion distinta y a la vez que 06_CONCURRENCIA_B.sql.
No llama a NAV, RFID, dispositivos ni impresoras.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 53500, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'prod.registrar_entrada_productiva', N'P') IS NULL
 OR OBJECT_ID(N'prod.abrir_sesion_linea', N'P') IS NULL
    THROW 53501, 'Faltan procedimientos requeridos para concurrencia.', 1;

/*
Antes de ejecutar, sustituir ambas marcas por horas UTC futuras.
Usar exactamente los mismos valores en los clientes A y B.
Recomendacion: entrada = ahora + 15 s; apertura = ahora + 35 s.
*/
DECLARE
    @inicio_entrada datetime2(3) = '2099-01-01T00:00:00.000', -- REVISAR
    @inicio_apertura datetime2(3) = '2099-01-01T00:00:20.000'; -- REVISAR

IF @inicio_entrada <= SYSUTCDATETIME()
 OR @inicio_entrada > DATEADD(MINUTE, 2, SYSUTCDATETIME())
 OR @inicio_apertura <= @inicio_entrada
 OR @inicio_apertura > DATEADD(MINUTE, 2, SYSUTCDATETIME())
    THROW 53502, 'Las horas deben ser futuras, ordenadas y estar dentro de 2 minutos UTC.', 1;

DECLARE
    @operario_2_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-OP2'),
    @supervisor_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ11-SUP'),
    @sesion_normal_id bigint =
        (SELECT s.sesion_linea_id
         FROM prod.sesiones_linea s
         JOIN prod.ordenes o ON o.orden_id = s.orden_id
         JOIN cfg.lineas l ON l.linea_id = s.linea_id
         WHERE o.numero_orden = N'ZZ11-FL-NORMAL'
           AND l.codigo = N'ZZ11-L01'
           AND s.finalizada_utc IS NULL),
    @orden_turno_id bigint =
        (SELECT orden_id FROM prod.ordenes WHERE numero_orden = N'ZZ11-FL-TURNO'),
    @linea_2_id bigint =
        (SELECT linea_id FROM cfg.lineas WHERE codigo = N'ZZ11-L02'),
    @formato_turno_id bigint =
        (SELECT f.formato_palet_orden_id
         FROM prod.formatos_palet_orden f
         JOIN prod.ordenes o ON o.orden_id = f.orden_id
         WHERE o.numero_orden = N'ZZ11-FL-TURNO'
           AND f.activo = 1),
    @fichaje_id bigint,
    @reserva_id bigint,
    @sesion_nueva_id bigint,
    @error_entrada int,
    @error_apertura int,
    @correlacion uniqueidentifier;

IF @operario_2_id IS NULL OR @supervisor_id IS NULL
 OR @sesion_normal_id IS NULL
 OR @orden_turno_id IS NULL OR @linea_2_id IS NULL
 OR @formato_turno_id IS NULL
    THROW 53503, 'Falta el estado heredado requerido de los bloques 01-04.', 1;

IF EXISTS
(
    SELECT 1 FROM prod.fichajes
    WHERE empleado_id = @operario_2_id
      AND salida_utc IS NULL
)
 OR EXISTS
(
    SELECT 1 FROM prod.sesiones_linea
    WHERE orden_id = @orden_turno_id
      AND finalizada_utc IS NULL
)
    THROW 53504, 'La concurrencia 05-06 ya se inicio o el estado no esta limpio.', 1;

/* G38-A: OP2 intenta entrar en L01 al mismo tiempo que B lo hace en L04. */
WHILE SYSUTCDATETIME() < @inicio_entrada
    WAITFOR DELAY '00:00:00.050';

SET @correlacion = NEWID();
SET @error_entrada = NULL;
BEGIN TRY
    EXEC prod.registrar_entrada_productiva
        @sesion_linea_id = @sesion_normal_id,
        @empleado_id = @operario_2_id,
        @correlacion_id = @correlacion,
        @fichaje_id = @fichaje_id OUTPUT,
        @reserva_palet_id = @reserva_id OUTPUT;
END TRY
BEGIN CATCH
    SET @error_entrada = ERROR_NUMBER();
    IF @error_entrada <> 51808
        THROW;
END CATCH;

IF @error_entrada IS NULL AND @fichaje_id IS NULL
    THROW 53505, 'G38-A: la entrada confirmada no devolvio fichaje.', 1;

IF @error_entrada = 51808
   AND (@@TRANCOUNT <> 0 OR XACT_STATE() <> 0)
    THROW 53506, 'G38-A: el rechazo dejo la transaccion sucia.', 1;

SELECT
    N'A' AS cliente,
    N'ENTRADA_MISMO_EMPLEADO' AS carrera,
    CASE WHEN @error_entrada IS NULL
         THEN N'CONFIRMADA' ELSE N'RECHAZADA_ESPERADA' END AS resultado,
    @fichaje_id AS fichaje_id,
    @error_entrada AS error_numero;

/* G39-A: intenta abrir la FL NORMAL de turno en L02. */
WHILE SYSUTCDATETIME() < @inicio_apertura
    WAITFOR DELAY '00:00:00.050';

SET @correlacion = NEWID();
SET @error_apertura = NULL;
BEGIN TRY
    EXEC prod.abrir_sesion_linea
        @orden_id = @orden_turno_id,
        @linea_id = @linea_2_id,
        @formato_palet_orden_id = @formato_turno_id,
        @supervisor_id = @supervisor_id,
        @inicio_fuera_horario_confirmado = 1,
        @correlacion_id = @correlacion,
        @sesion_linea_id = @sesion_nueva_id OUTPUT;
END TRY
BEGIN CATCH
    SET @error_apertura = ERROR_NUMBER();
    IF @error_apertura <> 51710
        THROW;
END CATCH;

IF @error_apertura IS NULL AND @sesion_nueva_id IS NULL
    THROW 53507, 'G39-A: la apertura confirmada no devolvio sesion.', 1;

IF @error_apertura = 51710
   AND (@@TRANCOUNT <> 0 OR XACT_STATE() <> 0)
    THROW 53508, 'G39-A: el rechazo dejo la transaccion sucia.', 1;

SELECT
    N'A' AS cliente,
    N'APERTURA_FL_NORMAL' AS carrera,
    CASE WHEN @error_apertura IS NULL
         THEN N'CONFIRMADA' ELSE N'RECHAZADA_ESPERADA' END AS resultado,
    @sesion_nueva_id AS sesion_linea_id,
    @error_apertura AS error_numero;

PRINT N'CLIENTE A DE CONCURRENCIA 011: COMPLETADO';
