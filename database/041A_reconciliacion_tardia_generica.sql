/*
Paquete 041A - Reconciliacion tardia generica de SALIDA_PALET.
Base exclusiva: EBIR_MES_TEST.

No contacta NAV ni modifica operaciones existentes. Publica una reserva que
distingue explicitamente envio y solo reconciliacion. Una salida desconocida
con foto previa valida se observa despues de esa foto y nunca se reenvia.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'nav.reservar_siguiente_salida_palet', N'P') IS NULL
 OR OBJECT_ID(N'nav.fallar_salida_palet', N'P') IS NULL
 OR OBJECT_ID(N'nav.operaciones', N'U') IS NULL
 OR OBJECT_ID(N'nav.intentos_operacion', N'U') IS NULL
    THROW 51071, 'El paquete 041A requiere la cola SALIDA_PALET instalada.', 1;
GO

IF EXISTS
(
    SELECT 1 FROM nav.operaciones
    WHERE tipo=N'SALIDA_PALET' AND estado=N'PROCESANDO'
)
    THROW 51072, 'Existen salidas de palet en proceso; no se puede instalar 041A.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE nav.reservar_siguiente_salida_palet
    @worker_id nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @worker_id = NULLIF(LTRIM(RTRIM(@worker_id)), N'''' );
    IF @worker_id IS NULL
        THROW 56000, ''La identidad del worker es obligatoria.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @ahora datetime2(3) = SYSUTCDATETIME();

        INSERT nav.intentos_operacion
        (
            operacion_nav_id, numero_intento, inicio_utc, fin_utc,
            resultado, error_normalizado, respuesta
        )
        SELECT
            operacion_nav_id, CONVERT(smallint, numero_intentos + 1),
            reservado_utc, @ahora, N''RESULTADO_DESCONOCIDO'',
            N''RESERVA_CADUCADA'',
            N''{"origen":"MES_WORKER","motivo":"reserva_caducada"}''
        FROM nav.operaciones WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE tipo=N''SALIDA_PALET''
          AND estado=N''PROCESANDO''
          AND reservado_utc < DATEADD(MINUTE, -5, @ahora);

        UPDATE nav.operaciones
        SET estado=N''RESULTADO_DESCONOCIDO'',
            numero_intentos=numero_intentos + 1,
            proximo_intento_utc=@ahora,
            procesada_utc=NULL,
            reservado_utc=NULL,
            reservado_por=NULL
        WHERE tipo=N''SALIDA_PALET''
          AND estado=N''PROCESANDO''
          AND reservado_utc < DATEADD(MINUTE, -5, @ahora);

        DECLARE @operacion_id bigint,
                @solo_reconciliacion bit,
                @baseline_maximum_id int;

        SELECT TOP (1)
            @operacion_id=n.operacion_nav_id,
            @solo_reconciliacion=CONVERT(bit,
                CASE WHEN n.estado=N''RESULTADO_DESCONOCIDO'' THEN 1 ELSE 0 END),
            @baseline_maximum_id=TRY_CONVERT(int,
                JSON_VALUE(ultimo_seguro.respuesta, ''$.baselineMaximumId''))
        FROM nav.operaciones n WITH (UPDLOCK, READPAST, ROWLOCK)
        OUTER APPLY
        (
            SELECT TOP (1) i.respuesta
            FROM nav.intentos_operacion i
            WHERE i.operacion_nav_id=n.operacion_nav_id
              AND ISJSON(i.respuesta)=1
              AND JSON_VALUE(i.respuesta, ''$.adapter'')=
                  N''NavisionSoapPalletOutputSender''
              AND JSON_VALUE(i.respuesta, ''$.outcome'')=N''UnknownResult''
              AND TRY_CONVERT(int,
                  JSON_VALUE(i.respuesta, ''$.baselineMaximumId'')) >= 0
            ORDER BY i.numero_intento DESC, i.intento_operacion_id DESC
        ) ultimo_seguro
        OUTER APPLY
        (
            SELECT TOP (1) i.respuesta
            FROM nav.intentos_operacion i
            WHERE i.operacion_nav_id=n.operacion_nav_id
            ORDER BY i.numero_intento DESC, i.intento_operacion_id DESC
        ) ultimo
        WHERE n.tipo=N''SALIDA_PALET''
          AND
          (
              (
                  n.estado IN (N''PENDIENTE'', N''ERROR_REINTENTABLE'')
                  AND n.numero_intentos < 3
                  AND (n.proximo_intento_utc IS NULL
                       OR n.proximo_intento_utc <= @ahora)
              )
              OR
              (
                  n.estado=N''RESULTADO_DESCONOCIDO''
                  AND n.numero_intentos < 12
                  AND (n.proximo_intento_utc IS NULL
                       OR n.proximo_intento_utc <= @ahora)
                  AND COALESCE(JSON_VALUE(ultimo.respuesta, ''$.reason''), N'''')
                      NOT IN
                      (
                          N''MultipleNewOutputs'', N''ReconciliationTruncated'',
                          N''ReconciliationMismatch'', N''ReconciliationRowNotUnique'',
                          N''ExternalIdentifierInvalid'', N''BaselineMaximumIdMissing''
                      )
                  AND
                  (
                      NULLIF(LTRIM(RTRIM(n.identificador_externo)), N'''')
                          IS NOT NULL
                      OR ultimo_seguro.respuesta IS NOT NULL
                  )
              )
          )
        ORDER BY
            CASE WHEN n.estado=N''RESULTADO_DESCONOCIDO'' THEN 0 ELSE 1 END,
            n.creada_utc,
            n.operacion_nav_id;

        IF @operacion_id IS NOT NULL
        BEGIN
            UPDATE nav.operaciones
            SET estado=N''PROCESANDO'',
                reservado_utc=@ahora,
                reservado_por=@worker_id,
                procesada_utc=NULL,
                proximo_intento_utc=NULL
            WHERE operacion_nav_id=@operacion_id;

            SELECT
                n.operacion_nav_id, n.operacion_uid, n.clave_idempotencia,
                o.numero_orden, o.producto_codigo, o.lote,
                e.codigo_nav, l.codigo, p.cantidad_buena,
                p.cerrado_utc, n.numero_intentos + 1 AS numero_intento,
                n.identificador_externo,
                @solo_reconciliacion AS solo_reconciliacion,
                @baseline_maximum_id AS baseline_maximum_id
            FROM nav.operaciones n
            JOIN prod.palets p
              ON p.palet_id=n.palet_id AND p.orden_id=n.orden_id
            JOIN prod.ordenes o ON o.orden_id=n.orden_id
            JOIN prod.sesiones_linea s
              ON s.sesion_linea_id=p.sesion_linea_id
             AND s.orden_id=p.orden_id
            JOIN cfg.lineas l ON l.linea_id=s.linea_id
            JOIN seg.empleados e
              ON e.empleado_id=p.cerrado_por_empleado_id
            WHERE n.operacion_nav_id=@operacion_id;
        END;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE nav.fallar_salida_palet
    @operacion_nav_id bigint,
    @numero_intento int,
    @resultado nvarchar(30),
    @identificador_externo nvarchar(100)=NULL,
    @codigo_http int=NULL,
    @datos_tecnicos nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @identificador_externo=
        NULLIF(LTRIM(RTRIM(@identificador_externo)), N'''' );
    IF @resultado NOT IN
       (N''ERROR_REINTENTABLE'', N''RESULTADO_DESCONOCIDO'', N''ERROR_DEFINITIVO'')
       OR ISJSON(@datos_tecnicos) <> 1
       OR (@codigo_http IS NOT NULL AND @codigo_http NOT BETWEEN 100 AND 599)
        THROW 56020, ''El fallo normalizado de NAV no es valido.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @inicio datetime2(3),
                @intentos int,
                @resultado_final nvarchar(30),
                @identificador_existente nvarchar(100),
                @continuar_reconciliacion bit=0,
                @motivo nvarchar(100)=JSON_VALUE(@datos_tecnicos, ''$.reason'');

        SELECT @inicio=reservado_utc,
               @intentos=numero_intentos,
               @identificador_existente=identificador_externo
        FROM nav.operaciones WITH (UPDLOCK, HOLDLOCK)
        WHERE operacion_nav_id=@operacion_nav_id
          AND tipo=N''SALIDA_PALET''
          AND estado=N''PROCESANDO'';
        IF @inicio IS NULL OR @numero_intento <> @intentos + 1
            THROW 56021, ''La salida NAV no corresponde a la reserva activa.'', 1;

        SET @resultado_final=CASE
            WHEN @resultado=N''ERROR_REINTENTABLE'' AND @numero_intento >= 3
                THEN N''ERROR_DEFINITIVO''
            ELSE @resultado END;

        IF @resultado_final=N''RESULTADO_DESCONOCIDO''
           AND @numero_intento < 12
           AND COALESCE(@motivo, N'''') NOT IN
           (
               N''MultipleNewOutputs'', N''ReconciliationTruncated'',
               N''ReconciliationMismatch'', N''ReconciliationRowNotUnique'',
               N''ExternalIdentifierInvalid'', N''BaselineMaximumIdMissing''
           )
           AND
           (
               COALESCE(@identificador_externo, @identificador_existente) IS NOT NULL
               OR
               (
                   JSON_VALUE(@datos_tecnicos, ''$.adapter'')=
                       N''NavisionSoapPalletOutputSender''
                   AND JSON_VALUE(@datos_tecnicos, ''$.outcome'')=N''UnknownResult''
                   AND
                   (
                       JSON_VALUE(@datos_tecnicos, ''$.reconciliationMode'') IS NULL
                       OR JSON_VALUE(@datos_tecnicos, ''$.reconciliationMode'')=
                           N''DISCOVER_AFTER_BASELINE''
                   )
                   AND TRY_CONVERT(int,
                       JSON_VALUE(@datos_tecnicos, ''$.baselineMaximumId'')) >= 0
               )
           )
            SET @continuar_reconciliacion=1;

        INSERT nav.intentos_operacion
        (
            operacion_nav_id, numero_intento, inicio_utc, fin_utc,
            resultado, codigo_http, error_normalizado, respuesta
        )
        VALUES
        (
            @operacion_nav_id, CONVERT(smallint, @numero_intento), @inicio,
            SYSUTCDATETIME(), @resultado_final, @codigo_http,
            @resultado_final, @datos_tecnicos
        );

        UPDATE nav.operaciones
        SET estado=@resultado_final,
            numero_intentos=@numero_intento,
            proximo_intento_utc=CASE
                WHEN @resultado_final=N''ERROR_REINTENTABLE''
                    THEN DATEADD(SECOND, 5 * @numero_intento, SYSUTCDATETIME())
                WHEN @continuar_reconciliacion=1
                    THEN DATEADD(SECOND, 10, SYSUTCDATETIME())
                ELSE NULL END,
            procesada_utc=CASE
                WHEN @resultado_final=N''ERROR_REINTENTABLE''
                  OR @continuar_reconciliacion=1 THEN NULL
                ELSE SYSUTCDATETIME() END,
            identificador_externo=COALESCE(
                @identificador_externo, identificador_externo),
            reservado_utc=NULL,
            reservado_por=NULL
        WHERE operacion_nav_id=@operacion_nav_id;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    GRANT EXECUTE ON OBJECT::nav.reservar_siguiente_salida_palet TO mes_runtime;
    GRANT EXECUTE ON OBJECT::nav.fallar_salida_palet TO mes_runtime;

    DECLARE @reserva nvarchar(max)=
        OBJECT_DEFINITION(OBJECT_ID(N'nav.reservar_siguiente_salida_palet'));
    DECLARE @fallo nvarchar(max)=
        OBJECT_DEFINITION(OBJECT_ID(N'nav.fallar_salida_palet'));
    IF @reserva NOT LIKE N'%solo_reconciliacion%'
     OR @reserva NOT LIKE N'%baseline_maximum_id%'
     OR @reserva NOT LIKE N'%numero_intentos < 12%'
     OR @fallo NOT LIKE N'%@continuar_reconciliacion%'
     OR @fallo NOT LIKE N'%DISCOVER_AFTER_BASELINE%'
        THROW 51073, 'El contrato 041A no quedo publicado completamente.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
