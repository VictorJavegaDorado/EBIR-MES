/*
Pruebas funcionales 012 - Correcciones y reconstruccion de tramos.
Requiere 00, 01 y 02 ejecutados previamente.
Estado: preparado para revision estatica; no ejecutado.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 54300, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;

DECLARE
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
    @fichaje_id bigint,
    @entrada_original datetime2(3),
    @entrada_corregida datetime2(3),
    @entrada_paro datetime2(3),
    @entrada_invalida datetime2(3),
    @salida_invalida datetime2(3),
    @paro_id bigint,
    @sustitucion_id bigint,
    @fichaje_supervisor_id bigint,
    @sustitucion_devuelta_id bigint,
    @recursos int,
    @error int,
    @trancount_despues int,
    @xact_state_despues int;

SELECT
    @fichaje_id = fichaje_id,
    @entrada_original = entrada_utc
FROM prod.fichajes
WHERE sesion_linea_id = @sesion_id
  AND empleado_id = @operario_id
  AND salida_utc IS NULL;

IF @sesion_id IS NULL OR @fichaje_id IS NULL OR @entrada_original IS NULL
 OR @supervisor_id IS NULL
    THROW 54301, 'Faltan el estado previo o fixtures requeridos para 03.', 1;

IF EXISTS
(
    SELECT 1
    FROM prod.fichajes
    WHERE fichaje_id = @fichaje_id
      AND estado = N'CORREGIDO'
      AND salida_utc IS NULL
      AND corregido_por_empleado_id = @supervisor_id
      AND motivo_correccion = N'Ajuste sintetico de entrada'
)
BEGIN
    IF
    (
        SELECT COUNT(*)
        FROM aud.eventos
        WHERE entidad = N'prod.fichajes'
          AND entidad_id = @fichaje_id
          AND tipo_evento = N'FICHAJE_CORREGIDO'
    ) <> 1
        THROW 54301, 'El estado existente no es el parcial exacto C01.', 1;

    SET @entrada_corregida = @entrada_original;
    GOTO REANUDAR_C02;
END;

/* C01: correccion valida reconstruye tramos y conserva el fichaje abierto. */
SET @entrada_corregida = DATEADD(MILLISECOND, 1, @entrada_original);

EXEC prod.corregir_fichaje_turno_actual
    @fichaje_id = @fichaje_id,
    @entrada_utc_corregida = @entrada_corregida,
    @salida_utc_corregida = NULL,
    @supervisor_id = @supervisor_id,
    @motivo = N'Ajuste sintetico de entrada',
    @correlacion_id = '12030000-0000-0000-0000-000000000001';

IF NOT EXISTS
(
    SELECT 1
    FROM prod.fichajes
    WHERE fichaje_id = @fichaje_id
      AND entrada_utc = @entrada_corregida
      AND salida_utc IS NULL
      AND estado = N'CORREGIDO'
      AND corregido_por_empleado_id = @supervisor_id
      AND motivo_correccion = N'Ajuste sintetico de entrada'
)
 OR
 (
     SELECT COUNT(*)
     FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_id
       AND fin_utc IS NULL
 ) <> 1
 OR EXISTS
 (
     SELECT 1
     FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_id
       AND fin_utc IS NOT NULL
       AND
       (
           segundos_productivos <> DATEDIFF(SECOND, inicio_utc, fin_utc)
           OR motivo_inicio <> N'RECONSTRUCCION_CORRECCION'
       )
 )
    THROW 54302, 'C01: la correccion valida no reconstruyo correctamente.', 1;

;WITH tramos AS
(
    SELECT
        inicio_utc,
        fin_utc,
        LAG(fin_utc) OVER (ORDER BY inicio_utc, tramo_capacidad_id) AS fin_anterior
    FROM prod.tramos_capacidad
    WHERE sesion_linea_id = @sesion_id
)
SELECT @error = COUNT(*)
FROM tramos
WHERE fin_anterior IS NOT NULL
  AND inicio_utc < fin_anterior;

IF @error <> 0
    THROW 54303, 'C01: la reconstruccion genero tramos solapados.', 1;

/* C02: fechas futuras se rechazan antes de modificar. */
REANUDAR_C02:
SET @error = NULL;

BEGIN TRY
    EXEC prod.corregir_fichaje_turno_actual
        @fichaje_id = @fichaje_id,
        @entrada_utc_corregida = '2099-01-01T00:00:00.000',
        @salida_utc_corregida = NULL,
        @supervisor_id = @supervisor_id,
        @motivo = N'Futuro invalido',
        @correlacion_id = '12030000-0000-0000-0000-000000000002';
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;

SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error <> 52607 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
 OR (SELECT entrada_utc FROM prod.fichajes WHERE fichaje_id = @fichaje_id)
      <> @entrada_corregida
    THROW 54304, 'C02: la fecha futura no se rechazo limpiamente.', 1;

/* C03: un paro historico no puede quedar fuera del intervalo corregido. */
SELECT @entrada_paro = MIN(po.inicio_utc)
FROM prod.paros_operario po
WHERE po.fichaje_id = @fichaje_id;

IF @entrada_paro IS NULL
    THROW 54305, 'C03 requiere paros historicos creados por 01 y 02.', 1;

SET @error = NULL;
SET @entrada_invalida = DATEADD(MILLISECOND, 1, @entrada_paro);

BEGIN TRY
    EXEC prod.corregir_fichaje_turno_actual
        @fichaje_id = @fichaje_id,
        @entrada_utc_corregida = @entrada_invalida,
        @salida_utc_corregida = NULL,
        @supervisor_id = @supervisor_id,
        @motivo = N'Excluiria paro',
        @correlacion_id = '12030000-0000-0000-0000-000000000003';
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;

SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error <> 52617 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
 OR (SELECT entrada_utc FROM prod.fichajes WHERE fichaje_id = @fichaje_id)
      <> @entrada_corregida
    THROW 54306, 'C03: el paro fuera de intervalo no se rechazo limpiamente.', 1;

/* C04: una sustitucion activa bloquea la correccion del fichaje ligado. */
EXEC prod.iniciar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_id,
    @motivo = N'WC',
    @correlacion_id = '12030000-0000-0000-0000-000000000004',
    @paro_operario_id = @paro_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

EXEC prod.iniciar_sustitucion_capacidad
    @sesion_linea_id = @sesion_id,
    @operario_sustituido_id = @operario_id,
    @supervisor_sustituto_id = @supervisor_id,
    @motivo = N'Cobertura para correccion',
    @correlacion_id = '12030000-0000-0000-0000-000000000005',
    @sustitucion_capacidad_id = @sustitucion_id OUTPUT,
    @fichaje_supervisor_id = @fichaje_supervisor_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

SET @error = NULL;
SET @salida_invalida = DATEADD(MILLISECOND, -1, @entrada_corregida);

BEGIN TRY
    EXEC prod.corregir_fichaje_turno_actual
        @fichaje_id = @fichaje_id,
        @entrada_utc_corregida = @entrada_corregida,
        @salida_utc_corregida = NULL,
        @supervisor_id = @supervisor_id,
        @motivo = N'Con sustitucion activa',
        @correlacion_id = '12030000-0000-0000-0000-000000000006';
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;

SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error <> 52619 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
 OR NOT EXISTS
 (
     SELECT 1 FROM prod.sustituciones_capacidad
     WHERE sustitucion_capacidad_id = @sustitucion_id
       AND fin_utc IS NULL
 )
    THROW 54307, 'C04: la sustitucion activa no bloqueo limpiamente.', 1;

EXEC prod.finalizar_paro_operario
    @sesion_linea_id = @sesion_id,
    @empleado_id = @operario_id,
    @correlacion_id = '12030000-0000-0000-0000-000000000007',
    @paro_operario_id = @paro_id OUTPUT,
    @sustitucion_finalizada_id = @sustitucion_devuelta_id OUTPUT,
    @recursos_activos = @recursos OUTPUT;

IF @sustitucion_devuelta_id <> @sustitucion_id OR @recursos <> 2
    THROW 54308, 'C04: la limpieza funcional posterior no fue correcta.', 1;

/* C05: motivo vacio e intervalo negativo se rechazan antes de transaccion. */
SET @error = NULL;

BEGIN TRY
    EXEC prod.corregir_fichaje_turno_actual
        @fichaje_id = @fichaje_id,
        @entrada_utc_corregida = @entrada_corregida,
        @salida_utc_corregida = NULL,
        @supervisor_id = @supervisor_id,
        @motivo = N'   ',
        @correlacion_id = '12030000-0000-0000-0000-000000000008';
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;

SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error <> 52603
 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
    THROW 54309, 'C05: el motivo vacio no fue rechazado.', 1;

SET @error = NULL;

BEGIN TRY
    EXEC prod.corregir_fichaje_turno_actual
        @fichaje_id = @fichaje_id,
        @entrada_utc_corregida = @entrada_corregida,
        @salida_utc_corregida = @salida_invalida,
        @supervisor_id = @supervisor_id,
        @motivo = N'Intervalo negativo',
        @correlacion_id = '12030000-0000-0000-0000-000000000009';
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
END CATCH;

SET @trancount_despues = @@TRANCOUNT;
SET @xact_state_despues = XACT_STATE();

IF @error <> 52602
 OR @trancount_despues <> 0 OR @xact_state_despues <> 0
    THROW 54310, 'C05: el intervalo negativo no fue rechazado.', 1;

IF
(
    SELECT COUNT(*)
    FROM aud.eventos
    WHERE entidad = N'prod.fichajes'
      AND entidad_id = @fichaje_id
      AND tipo_evento = N'FICHAJE_CORREGIDO'
) <> 1
 OR EXISTS
 (
     SELECT 1
     FROM aud.eventos
     WHERE entidad = N'prod.fichajes'
       AND entidad_id = @fichaje_id
       AND tipo_evento = N'FICHAJE_CORREGIDO'
       AND
       (
           valor_anterior IS NULL
           OR valor_nuevo IS NULL
           OR motivo IS NULL
       )
 )
    THROW 54311, 'La auditoria de correccion no conserva valores y motivo.', 1;

SELECT
    @sesion_id AS sesion_linea_id,
    @fichaje_id AS fichaje_corregido_id,
    @entrada_original AS entrada_original,
    @entrada_corregida AS entrada_corregida,
    (SELECT COUNT(*) FROM prod.tramos_capacidad
     WHERE sesion_linea_id = @sesion_id) AS tramos_reconstruidos,
    (SELECT recursos_activos FROM prod.recursos_efectivos_sesion(@sesion_id))
        AS recursos_finales;

PRINT N'03 CORRECCIONES Y TRAMOS COMPLETADO';
