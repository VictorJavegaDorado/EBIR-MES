/*
Pruebas 012 - cliente A de concurrencia de sustitucion.
Ejecutar en conexion independiente junto con 06_CONCURRENCIA_B.sql.
Estado: preparado para revision estatica; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 54500, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

DECLARE
    @inicio_carrera datetime2(3) = '2099-01-01T00:00:00.000', -- REVISAR
    @sesion_id bigint =
    (
        SELECT s.sesion_linea_id
        FROM prod.sesiones_linea s
        JOIN cfg.lineas l ON l.linea_id = s.linea_id
        WHERE l.codigo = N'ZZ12-L01'
          AND s.finalizada_utc IS NULL
    ),
    @operario_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-OP1'),
    @supervisor_id bigint =
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-SUP'),
    @paro_id bigint,
    @sustitucion_id bigint,
    @fichaje_supervisor_id bigint,
    @recursos int,
    @error int,
    @trancount_despues int,
    @xact_state_despues int;

IF @inicio_carrera <= DATEADD(SECOND, 2, SYSUTCDATETIME())
 OR @inicio_carrera > DATEADD(MINUTE, 2, SYSUTCDATETIME())
    THROW 54501, 'La marca debe ser futura y estar dentro de dos minutos UTC.', 1;

IF @sesion_id IS NULL OR @operario_id IS NULL OR @supervisor_id IS NULL
    THROW 54502, 'Falta el estado previo requerido para concurrencia.', 1;

IF EXISTS
(
    SELECT 1
    FROM prod.sustituciones_capacidad
    WHERE operario_sustituido_id = @operario_id
      AND fin_utc IS NULL
)
 OR EXISTS
(
    SELECT 1
    FROM prod.paros_operario po
    JOIN prod.fichajes f ON f.fichaje_id = po.fichaje_id
    WHERE f.sesion_linea_id = @sesion_id
      AND f.empleado_id = @operario_id
      AND po.fin_utc IS NULL
)
    THROW 54503, 'La carrera ya se inicio o el estado no esta limpio.', 1;

/* Preparacion unica del cliente A antes de la marca comun. */
EXEC prod.iniciar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_id,
    @motivo = N'WC',
    @correlacion_id = '12050000-0000-0000-0000-000000000001',
    @paro_operario_id = @paro_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @paro_id IS NULL OR @recursos <> 1
    THROW 54504, 'No se pudo preparar el paro de la carrera.', 1;

WHILE SYSUTCDATETIME() < @inicio_carrera
    WAITFOR DELAY '00:00:00.050';

SET @error = NULL;
SET @sustitucion_id = NULL;
SET @fichaje_supervisor_id = NULL;
SET @recursos = -1;
BEGIN TRY
    EXEC prod.iniciar_sustitucion_capacidad
        @sesion_linea_id = @sesion_id,
        @operario_sustituido_id = @operario_id,
        @supervisor_sustituto_id = @supervisor_id,
        @motivo = N'Carrera cliente A',
        @correlacion_id = '12050000-0000-0000-0000-000000000002',
        @sustitucion_capacidad_id = @sustitucion_id OUTPUT,
        @fichaje_supervisor_id = @fichaje_supervisor_id OUTPUT,
        @recursos_activos = @recursos OUTPUT;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    IF @error <> 52415
        THROW;
END CATCH;

SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error IS NULL
   AND (@sustitucion_id IS NULL OR @fichaje_supervisor_id IS NULL OR @recursos <> 2)
    THROW 54505, 'El cliente A gano sin devolver el estado esperado.', 1;

IF @error = 52415
   AND
   (
       @sustitucion_id IS NOT NULL
       OR @fichaje_supervisor_id IS NOT NULL
       OR @recursos <> -1
       OR @trancount_despues <> 0
       OR @xact_state_despues <> 0
   )
    THROW 54506, 'El rechazo del cliente A no fue limpio.', 1;

SELECT
    N'A' AS cliente,
    CASE WHEN @error IS NULL THEN N'GANADOR' ELSE N'RECHAZADO_ESPERADO' END
        AS resultado,
    @sustitucion_id AS sustitucion_capacidad_id,
    @fichaje_supervisor_id AS fichaje_supervisor_id,
    @error AS error_numero;

PRINT N'CLIENTE A CONCURRENCIA 012 COMPLETADO';
