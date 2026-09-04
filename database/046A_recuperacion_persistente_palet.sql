/*
Paquete 046A - Recuperacion persistente del ultimo palet.
Base exclusiva: EBIR_MES_TEST.

Permite que un supervisor abra una segunda ventana limitada de observacion
para una SALIDA_PALET agotada. La operacion conserva RESULTADO_DESCONOCIDO y
su identificador externo, por lo que el Worker recibe solo_reconciliacion=1:
este paquete nunca vuelve a publicar la salida de fabricacion.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'nav.reservar_siguiente_salida_palet',N'P') IS NULL
 OR OBJECT_ID(N'nav.fallar_salida_palet',N'P') IS NULL
 OR OBJECT_ID(N'aud.eventos',N'U') IS NULL
 OR OBJECT_ID(N'aud.registrar_evento',N'P') IS NULL
    THROW 51140, 'El paquete 046A requiere 041A y la auditoria MES.', 1;
GO

IF EXISTS
(
    SELECT 1 FROM nav.operaciones
    WHERE tipo=N'SALIDA_PALET' AND estado=N'PROCESANDO'
)
    THROW 51141, 'Existen salidas de palet en proceso; no se puede instalar 046A.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @reserva nvarchar(max)=
        OBJECT_DEFINITION(OBJECT_ID(N'nav.reservar_siguiente_salida_palet'));
    IF @reserva NOT LIKE N'%n.numero_intentos BETWEEN 12 AND 23%'
    BEGIN
        SET @reserva=REPLACE(
            @reserva,N'CREATE PROCEDURE',N'CREATE OR ALTER PROCEDURE');
        SET @reserva=REPLACE(
            @reserva,
            N'n.numero_intentos < 12',
            N'(n.numero_intentos < 12 OR (n.numero_intentos BETWEEN 12 AND 23 AND n.proximo_intento_utc IS NOT NULL))');
        IF @reserva NOT LIKE N'%n.numero_intentos BETWEEN 12 AND 23%'
            THROW 51142, 'No se pudo ampliar de forma controlada la reserva NAV.', 1;
        EXEC sys.sp_executesql @reserva;
    END;

    DECLARE @fallo nvarchar(max)=
        OBJECT_DEFINITION(OBJECT_ID(N'nav.fallar_salida_palet'));
    IF @fallo NOT LIKE N'%@numero_intento < 24%'
    BEGIN
        SET @fallo=REPLACE(
            @fallo,N'CREATE PROCEDURE',N'CREATE OR ALTER PROCEDURE');
        SET @fallo=REPLACE(
            @fallo,
            N'@numero_intento < 12',
            N'@numero_intento < 24');
        IF @fallo NOT LIKE N'%@numero_intento < 24%'
            THROW 51143, 'No se pudo limitar la segunda ventana de conciliacion.', 1;
        EXEC sys.sp_executesql @fallo;
    END;

    EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE nav.solicitar_reconciliacion_salida_palet
    @operacion_nav_id bigint,
    @solicitado_por_supervisor_id bigint,
    @motivo nvarchar(500),
    @correlacion_id uniqueidentifier,
    @proximo_numero_intento int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @motivo=NULLIF(LTRIM(RTRIM(@motivo)),N'''');
    IF @operacion_nav_id IS NULL OR @operacion_nav_id<=0
        THROW 56600, ''La operacion NAV no es valida.'', 1;
    IF @solicitado_por_supervisor_id IS NULL OR @solicitado_por_supervisor_id<=0
        THROW 56601, ''La conciliacion requiere un supervisor.'', 1;
    IF @motivo IS NULL OR LEN(@motivo)>500
        THROW 56602, ''El motivo no es valido.'', 1;
    IF @correlacion_id IS NULL
        THROW 56603, ''La correlacion es obligatoria.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @lock_result int;
        EXEC @lock_result=sys.sp_getapplock
            @Resource=CONCAT(N''nav:reconciliacion:'',CONVERT(nvarchar(36),@correlacion_id)),
            @LockMode=N''Exclusive'',@LockOwner=N''Transaction'',@LockTimeout=5000;
        IF @lock_result<0
            THROW 56604, ''No se pudo asegurar la idempotencia.'', 1;

        DECLARE @evento_tipo nvarchar(80),@evento_entidad nvarchar(80),
                @evento_operacion bigint,@evento_valor nvarchar(max),
                @evento_motivo nvarchar(1000);
        SELECT TOP (1) @evento_tipo=tipo_evento,@evento_entidad=entidad,
            @evento_operacion=entidad_id,@evento_valor=valor_nuevo,
            @evento_motivo=motivo
        FROM aud.eventos WITH (UPDLOCK,HOLDLOCK)
        WHERE correlacion_id=@correlacion_id
        ORDER BY evento_auditoria_id;
        IF @evento_tipo IS NOT NULL
        BEGIN
            IF @evento_tipo<>N''RECONCILIACION_NAV_SOLICITADA''
               OR @evento_entidad<>N''nav.operaciones''
                THROW 56605, ''La correlacion ya pertenece a otra operacion.'', 1;
            IF @evento_operacion<>@operacion_nav_id
               OR ISNULL(TRY_CONVERT(bigint,JSON_VALUE(@evento_valor,N''$.requestedBySupervisorId'')),-1)
                    <>@solicitado_por_supervisor_id
               OR @evento_motivo<>@motivo
                THROW 56606, ''La correlacion ya se uso con otros datos.'', 1;
            SET @proximo_numero_intento=13;
            COMMIT TRANSACTION;
            RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1 FROM seg.empleados e WITH (UPDLOCK,HOLDLOCK)
            JOIN seg.empleados_roles er ON er.empleado_id=e.empleado_id
            JOIN seg.roles r ON r.rol_id=er.rol_id
            WHERE e.empleado_id=@solicitado_por_supervisor_id
              AND e.activo_mes=1 AND e.anonimizado_utc IS NULL
              AND r.codigo=N''SUPERVISOR'' AND r.activo=1
              AND er.desde_utc<=SYSUTCDATETIME()
              AND (er.hasta_utc IS NULL OR er.hasta_utc>=SYSUTCDATETIME())
        )
            THROW 56607, ''Se requiere un supervisor activo.'', 1;

        DECLARE @orden_id bigint,@palet_id bigint,@sesion_linea_id bigint,
                @linea_id bigint,@estado nvarchar(30),@intentos int,
                @proximo datetime2(3),@reservado datetime2(3),
                @identificador nvarchar(100),@ultimo_motivo nvarchar(100);
        SELECT @orden_id=n.orden_id,@palet_id=n.palet_id,
               @sesion_linea_id=p.sesion_linea_id,@linea_id=s.linea_id,
               @estado=n.estado,@intentos=n.numero_intentos,
               @proximo=n.proximo_intento_utc,@reservado=n.reservado_utc,
               @identificador=NULLIF(LTRIM(RTRIM(n.identificador_externo)),N''''),
               @ultimo_motivo=JSON_VALUE(ultimo.respuesta,N''$.reason'')
        FROM nav.operaciones n WITH (UPDLOCK,HOLDLOCK)
        JOIN prod.palets p ON p.palet_id=n.palet_id AND p.orden_id=n.orden_id
        JOIN prod.sesiones_linea s ON s.sesion_linea_id=p.sesion_linea_id
        OUTER APPLY
        (
            SELECT TOP (1) i.respuesta
            FROM nav.intentos_operacion i
            WHERE i.operacion_nav_id=n.operacion_nav_id
            ORDER BY i.numero_intento DESC,i.intento_operacion_id DESC
        ) ultimo
        WHERE n.operacion_nav_id=@operacion_nav_id AND n.tipo=N''SALIDA_PALET'';

        IF @estado<>N''RESULTADO_DESCONOCIDO'' OR @intentos<>12
           OR @identificador IS NULL
           OR COALESCE(@ultimo_motivo,N'''') IN
              (N''MultipleNewOutputs'',N''ReconciliationTruncated'',N''ReconciliationMismatch'',
               N''ReconciliationRowNotUnique'',N''ExternalIdentifierInvalid'',N''BaselineMaximumIdMissing'')
            THROW 56608, ''La salida no admite conciliacion manual segura.'', 1;
        IF @proximo IS NOT NULL OR @reservado IS NOT NULL
            THROW 56609, ''La conciliacion ya esta en curso.'', 1;

        UPDATE nav.operaciones
        SET proximo_intento_utc=SYSUTCDATETIME(),procesada_utc=NULL
        WHERE operacion_nav_id=@operacion_nav_id;
        SET @proximo_numero_intento=13;

        DECLARE @anterior nvarchar(max)=(SELECT @estado AS state,@intentos AS attempts
            FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        DECLARE @nuevo nvarchar(max)=(SELECT @estado AS state,
            @proximo_numero_intento AS nextAttempt,
            @solicitado_por_supervisor_id AS requestedBySupervisorId,
            N''RECONCILIATION_ONLY'' AS mode
            FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
        EXEC aud.registrar_evento
            @tipo_evento=N''RECONCILIACION_NAV_SOLICITADA'',
            @empleado_id=@solicitado_por_supervisor_id,
            @cuenta_dominio=N''EBIR\MES$'',@rol_usado=N''SUPERVISOR'',
            @linea_id=@linea_id,@orden_id=@orden_id,
            @sesion_linea_id=@sesion_linea_id,
            @entidad=N''nav.operaciones'',@entidad_id=@operacion_nav_id,
            @valor_anterior=@anterior,@valor_nuevo=@nuevo,
            @motivo=@motivo,@correlacion_id=@correlacion_id;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

    GRANT EXECUTE ON OBJECT::nav.solicitar_reconciliacion_salida_palet TO mes_runtime;

    IF OBJECT_DEFINITION(OBJECT_ID(N'nav.reservar_siguiente_salida_palet'))
            NOT LIKE N'%n.numero_intentos BETWEEN 12 AND 23%'
     OR OBJECT_DEFINITION(OBJECT_ID(N'nav.fallar_salida_palet'))
            NOT LIKE N'%@numero_intento < 24%'
     OR OBJECT_ID(N'nav.solicitar_reconciliacion_salida_palet',N'P') IS NULL
        THROW 51144, 'El contrato 046A no quedo publicado completamente.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
