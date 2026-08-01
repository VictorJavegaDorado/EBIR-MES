SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'nav.ordenes_entrada', N'U') IS NULL
 OR OBJECT_ID(N'nav.rutas_orden_entrada', N'U') IS NULL
 OR OBJECT_ID(N'nav.componentes_orden_entrada', N'U') IS NULL
 OR OBJECT_ID(N'prod.ordenes', N'U') IS NULL
 OR OBJECT_ID(N'nav.componentes_orden', N'U') IS NULL
    THROW 51015, 'El paquete 016 requiere los objetos de produccion y del paquete 015.', 1;

IF OBJECT_ID(N'nav.promociones_orden', N'U') IS NOT NULL
 OR OBJECT_ID(N'nav.promover_orden_entrada', N'P') IS NOT NULL
    THROW 51016, 'El paquete 016 ya existe total o parcialmente.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    CREATE TABLE nav.promociones_orden
    (
        promocion_orden_id bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_nav_promociones_orden PRIMARY KEY,
        promocion_id uniqueidentifier NOT NULL,
        orden_entrada_id bigint NOT NULL,
        orden_id bigint NOT NULL,
        snapshot_hash binary(32) NOT NULL,
        lote nvarchar(50) NOT NULL,
        operacion_codigo nvarchar(30) NOT NULL,
        tiempo_ejecucion_nav_min decimal(12,1) NOT NULL,
        lote_proporcionado_por nvarchar(256) NOT NULL,
        resultado nvarchar(20) NOT NULL,
        creada_utc datetime2(3) NOT NULL
            CONSTRAINT DF_nav_promociones_orden_creada DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_nav_promociones_entrada FOREIGN KEY (orden_entrada_id)
            REFERENCES nav.ordenes_entrada (orden_entrada_id),
        CONSTRAINT FK_nav_promociones_orden FOREIGN KEY (orden_id)
            REFERENCES prod.ordenes (orden_id),
        CONSTRAINT UQ_nav_promociones_id UNIQUE (promocion_id),
        CONSTRAINT CK_nav_promociones_lote CHECK (LEN(LTRIM(RTRIM(lote))) > 0),
        CONSTRAINT CK_nav_promociones_operacion
            CHECK (LEN(LTRIM(RTRIM(operacion_codigo))) > 0),
        CONSTRAINT CK_nav_promociones_tiempo CHECK (tiempo_ejecucion_nav_min > 0),
        CONSTRAINT CK_nav_promociones_autor
            CHECK (LEN(LTRIM(RTRIM(lote_proporcionado_por))) > 0),
        CONSTRAINT CK_nav_promociones_resultado
            CHECK (resultado IN (N'CREADA', N'SIN_CAMBIOS', N'REVISION'))
    );

    CREATE INDEX IX_nav_promociones_entrada_creada
        ON nav.promociones_orden (orden_entrada_id, creada_utc DESC)
        INCLUDE (orden_id, snapshot_hash, lote, operacion_codigo, resultado);

    CREATE INDEX IX_nav_promociones_orden_creada
        ON nav.promociones_orden (orden_id, creada_utc DESC)
        INCLUDE (orden_entrada_id, snapshot_hash, resultado);

    DECLARE @definicion nvarchar(max) = N'
CREATE PROCEDURE nav.promover_orden_entrada
    @promocion_id uniqueidentifier,
    @orden_entrada_id bigint,
    @lote nvarchar(50),
    @operacion_codigo nvarchar(30),
    @lote_proporcionado_por nvarchar(256),
    @orden_id bigint OUTPUT,
    @resultado nvarchar(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @orden_id = NULL;
    SET @resultado = NULL;

    IF @promocion_id IS NULL OR @promocion_id = CAST(0x0 AS uniqueidentifier)
        THROW 55600, ''La correlacion de promocion es obligatoria.'', 1;
    IF @orden_entrada_id IS NULL OR @orden_entrada_id <= 0
        THROW 55601, ''La orden de entrada no es valida.'', 1;

    SET @lote = NULLIF(LTRIM(RTRIM(@lote)), N'''');
    SET @operacion_codigo = UPPER(NULLIF(LTRIM(RTRIM(@operacion_codigo)), N''''));
    SET @lote_proporcionado_por = NULLIF(LTRIM(RTRIM(@lote_proporcionado_por)), N'''');
    IF @lote IS NULL THROW 55602, ''El lote es obligatorio.'', 1;
    IF @operacion_codigo IS NULL THROW 55603, ''La operacion productiva es obligatoria.'', 1;
    IF @lote_proporcionado_por IS NULL
        THROW 55604, ''Debe identificarse quien proporciono el lote.'', 1;

    DECLARE
        @empresa_nav_id bigint,
        @numero_orden nvarchar(30),
        @estado_nav nvarchar(30),
        @producto_codigo nvarchar(50),
        @descripcion nvarchar(250),
        @cantidad decimal(18,4),
        @cantidad_objetivo int,
        @snapshot_hash binary(32),
        @snapshot_json nvarchar(max),
        @tiempo_raw decimal(18,8),
        @tiempo decimal(12,1),
        @resultado_bloqueo int,
        @recurso_bloqueo nvarchar(255);

    SELECT @empresa_nav_id = empresa_nav_id, @numero_orden = numero_orden,
           @estado_nav = estado_nav, @producto_codigo = producto_codigo,
           @descripcion = descripcion, @cantidad = cantidad,
           @snapshot_hash = snapshot_hash, @snapshot_json = snapshot_json
    FROM nav.ordenes_entrada
    WHERE orden_entrada_id = @orden_entrada_id;

    IF @empresa_nav_id IS NULL THROW 55605, ''La orden de entrada no existe.'', 1;
    IF @estado_nav <> N''Released'' THROW 55606, ''La orden NAV no esta lanzada.'', 1;
    IF (SELECT COUNT(*) FROM nav.lineas_orden_entrada WHERE orden_entrada_id = @orden_entrada_id) <> 1
        THROW 55607, ''El piloto requiere exactamente una linea NAV.'', 1;
    IF @cantidad IS NULL OR @cantidad <= 0 OR @cantidad > 2147483647
       OR @cantidad <> FLOOR(@cantidad)
        THROW 55608, ''La cantidad NAV no es un entero productivo valido.'', 1;
    SET @cantidad_objetivo = CONVERT(int, @cantidad);

    IF (SELECT COUNT(*) FROM nav.rutas_orden_entrada
        WHERE orden_entrada_id = @orden_entrada_id
          AND UPPER(operacion_codigo) = @operacion_codigo) <> 1
        THROW 55609, ''La operacion productiva no existe de forma unica.'', 1;
    SELECT @tiempo_raw = tiempo_ejecucion
    FROM nav.rutas_orden_entrada
    WHERE orden_entrada_id = @orden_entrada_id
      AND UPPER(operacion_codigo) = @operacion_codigo;
    SET @tiempo = TRY_CONVERT(decimal(12,1), @tiempo_raw);
    IF @tiempo IS NULL OR @tiempo <= 0 OR CONVERT(decimal(18,8), @tiempo) <> @tiempo_raw
        THROW 55610, ''El tiempo NAV no es un valor exacto de minutos por unidad.'', 1;
    IF EXISTS
    (
        SELECT 1 FROM nav.componentes_orden_entrada
        WHERE orden_entrada_id = @orden_entrada_id
        GROUP BY articulo_codigo
        HAVING COUNT(*) > 1
    )
        THROW 55613, ''La orden contiene componentes repetidos no promocionables.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        SET @recurso_bloqueo = CONCAT(N''MES:NAVPROMO:CORR:'', CONVERT(nvarchar(36), @promocion_id));
        EXEC @resultado_bloqueo = sys.sp_getapplock @Resource=@recurso_bloqueo,
            @LockMode=N''Exclusive'', @LockOwner=N''Transaction'', @LockTimeout=10000,
            @DbPrincipal=N''public'';
        IF @resultado_bloqueo < 0 THROW 55611, ''No se pudo bloquear la promocion.'', 1;

        DECLARE @hash_existente binary(32), @entrada_existente bigint,
                @lote_existente nvarchar(50), @operacion_existente nvarchar(30),
                @autor_existente nvarchar(256), @resultado_existente nvarchar(20);
        SELECT @orden_id=orden_id, @hash_existente=snapshot_hash,
               @entrada_existente=orden_entrada_id, @lote_existente=lote,
               @operacion_existente=operacion_codigo,
               @autor_existente=lote_proporcionado_por,
               @resultado_existente=resultado
        FROM nav.promociones_orden WITH (UPDLOCK,HOLDLOCK)
        WHERE promocion_id=@promocion_id;
        IF @orden_id IS NOT NULL
        BEGIN
            IF @hash_existente<>@snapshot_hash OR @entrada_existente<>@orden_entrada_id
               OR @lote_existente<>@lote OR @operacion_existente<>@operacion_codigo
               OR @autor_existente<>@lote_proporcionado_por
                THROW 55612, ''La correlacion ya se utilizo con otros parametros.'', 1;
            SET @resultado=@resultado_existente;
            COMMIT TRANSACTION;
            RETURN;
        END;

        SET @recurso_bloqueo=CONCAT(N''MES:NAVPROMO:ORDER:'',@empresa_nav_id,N'':'',@numero_orden);
        EXEC @resultado_bloqueo = sys.sp_getapplock @Resource=@recurso_bloqueo,
            @LockMode=N''Exclusive'', @LockOwner=N''Transaction'', @LockTimeout=10000,
            @DbPrincipal=N''public'';
        IF @resultado_bloqueo < 0 THROW 55611, ''No se pudo bloquear la orden productiva.'', 1;

        SELECT @orden_id=orden_id FROM prod.ordenes WITH (UPDLOCK,HOLDLOCK)
        WHERE empresa_nav_id=@empresa_nav_id AND numero_orden=@numero_orden;
        IF @orden_id IS NULL
        BEGIN
            INSERT prod.ordenes
            (empresa_nav_id,numero_orden,producto_codigo,producto_descripcion,lote,
             cantidad_objetivo,tiempo_ejecucion_nav_min,datos_nav_originales)
            VALUES
            (@empresa_nav_id,@numero_orden,@producto_codigo,ISNULL(@descripcion,N''''),@lote,
             @cantidad_objetivo,@tiempo,@snapshot_json);
            SET @orden_id=SCOPE_IDENTITY();

            INSERT nav.componentes_orden
            (orden_id,codigo_componente,descripcion,unidad_medida,cantidad_teorica,
             datos_nav_originales)
            SELECT @orden_id,c.articulo_codigo,c.descripcion,c.unidad_medida,
                   c.cantidad_prevista,
                   (SELECT c.numero_linea_orden,c.numero_linea,c.articulo_codigo,
                           c.variante_codigo,c.descripcion,c.cantidad_por,
                           c.cantidad_prevista,c.unidad_medida,c.operacion_codigo
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
            FROM nav.componentes_orden_entrada c
            WHERE c.orden_entrada_id=@orden_entrada_id;
            SET @resultado=N''CREADA'';
        END
        ELSE
        BEGIN
            DECLARE @ultimo_hash binary(32), @ultimo_lote nvarchar(50),
                    @ultima_operacion nvarchar(30), @ultimo_tiempo decimal(12,1);
            SELECT TOP (1) @ultimo_hash=snapshot_hash,@ultimo_lote=lote,
                   @ultima_operacion=operacion_codigo,@ultimo_tiempo=tiempo_ejecucion_nav_min
            FROM nav.promociones_orden WITH (UPDLOCK,HOLDLOCK)
            WHERE orden_id=@orden_id AND resultado IN (N''CREADA'',N''SIN_CAMBIOS'')
            ORDER BY promocion_orden_id DESC;
            IF @ultimo_hash=@snapshot_hash AND @ultimo_lote=@lote
               AND @ultima_operacion=@operacion_codigo AND @ultimo_tiempo=@tiempo
                SET @resultado=N''SIN_CAMBIOS'';
            ELSE
            BEGIN
                UPDATE prod.ordenes SET estado=N''REVISION'' WHERE orden_id=@orden_id;
                SET @resultado=N''REVISION'';
            END;
        END;

        INSERT nav.promociones_orden
        (promocion_id,orden_entrada_id,orden_id,snapshot_hash,lote,
         operacion_codigo,tiempo_ejecucion_nav_min,lote_proporcionado_por,resultado)
        VALUES
        (@promocion_id,@orden_entrada_id,@orden_id,@snapshot_hash,@lote,
         @operacion_codigo,@tiempo,@lote_proporcionado_por,@resultado);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        SET @orden_id=NULL; SET @resultado=NULL; THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql @definicion;
    GRANT EXECUTE ON OBJECT::nav.promover_orden_entrada TO mes_runtime;

    IF OBJECT_ID(N'nav.promociones_orden', N'U') IS NULL
     OR OBJECT_ID(N'nav.promover_orden_entrada', N'P') IS NULL
        THROW 51017, 'No se crearon todos los objetos del paquete 016.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
