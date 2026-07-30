/*
Pruebas 012 - cliente B y verificacion de concurrencia de sustitucion.
Ejecutar en conexion independiente junto con 05_CONCURRENCIA_A.sql.
Estado: preparado para revision estatica; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 54600, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

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
        (SELECT empleado_id FROM seg.empleados WHERE codigo_nav = N'ZZ12-SUP2'),
    @sustitucion_id bigint,
    @fichaje_supervisor_id bigint,
    @recursos int,
    @error int,
    @trancount_despues int,
    @xact_state_despues int;

IF @inicio_carrera <= DATEADD(SECOND, 2, SYSUTCDATETIME())
 OR @inicio_carrera > DATEADD(MINUTE, 2, SYSUTCDATETIME())
    THROW 54601, 'La marca debe ser futura y estar dentro de dos minutos UTC.', 1;

IF @sesion_id IS NULL OR @operario_id IS NULL OR @supervisor_id IS NULL
    THROW 54602, 'Falta el estado previo requerido para concurrencia.', 1;

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
        @motivo = N'Carrera cliente B',
        @correlacion_id = '12060000-0000-0000-0000-000000000001',
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
    THROW 54603, 'El cliente B gano sin devolver el estado esperado.', 1;

IF @error = 52415
   AND
   (
       @sustitucion_id IS NOT NULL
       OR @fichaje_supervisor_id IS NOT NULL
       OR @recursos <> -1
       OR @trancount_despues <> 0
       OR @xact_state_despues <> 0
   )
    THROW 54604, 'El rechazo del cliente B no fue limpio.', 1;

IF
(
    SELECT COUNT(*)
    FROM prod.sustituciones_capacidad
    WHERE operario_sustituido_id = @operario_id
      AND fin_utc IS NULL
) <> 1
    THROW 54605, 'La carrera no termino con una sustitucion activa unica.', 1;

IF
(
    SELECT COUNT(*)
    FROM prod.sustituciones_capacidad sc
    JOIN prod.fichajes f ON f.fichaje_id = sc.fichaje_supervisor_id
    WHERE sc.operario_sustituido_id = @operario_id
      AND sc.fin_utc IS NULL
      AND f.salida_utc IS NULL
) <> 1
    THROW 54606, 'La carrera no dejo un unico fichaje sustituto abierto.', 1;

IF (SELECT recursos_activos FROM prod.recursos_efectivos_sesion(@sesion_id)) <> 2
    THROW 54607, 'La carrera altero indebidamente la dotacion total.', 1;

IF EXISTS
(
    SELECT operario_sustituido_id
    FROM prod.sustituciones_capacidad
    WHERE fin_utc IS NULL
    GROUP BY operario_sustituido_id
    HAVING COUNT(*) > 1
)
 OR EXISTS
(
    SELECT supervisor_sustituto_id
    FROM prod.sustituciones_capacidad
    WHERE fin_utc IS NULL
    GROUP BY supervisor_sustituto_id
    HAVING COUNT(*) > 1
)
    THROW 54608, 'La carrera incumplio la unicidad de sustituciones.', 1;

SELECT
    N'B' AS cliente,
    CASE WHEN @error IS NULL THEN N'GANADOR' ELSE N'RECHAZADO_ESPERADO' END
        AS resultado_cliente,
    sc.sustitucion_capacidad_id,
    eo.codigo_nav AS operario,
    es.codigo_nav AS supervisor_ganador,
    sc.estado
FROM prod.sustituciones_capacidad sc
JOIN seg.empleados eo ON eo.empleado_id = sc.operario_sustituido_id
JOIN seg.empleados es ON es.empleado_id = sc.supervisor_sustituto_id
WHERE sc.operario_sustituido_id = @operario_id
  AND sc.fin_utc IS NULL;

PRINT N'CLIENTE B Y CONCURRENCIA 012 COMPLETADO';
