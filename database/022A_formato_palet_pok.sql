SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'nav.ordenes_entrada', N'U') IS NULL
 OR OBJECT_ID(N'nav.promover_orden_entrada', N'P') IS NULL
 OR OBJECT_ID(N'nav.promover_orden_entrada_con_lote_nav', N'P') IS NULL
 OR OBJECT_ID(N'prod.ordenes', N'U') IS NULL
 OR OBJECT_ID(N'prod.formatos_palet_orden', N'U') IS NULL
    THROW 51027, 'El paquete 022 requiere los paquetes 003, 015, 016, 017 y 021.', 1;

IF OBJECT_ID(N'nav.formatos_palet_orden_entrada', N'U') IS NOT NULL
 OR OBJECT_ID(N'nav.registrar_formato_palet_snapshot_orden', N'P') IS NOT NULL
    THROW 51028, 'El paquete 022 ya esta instalado o sus objetos existen.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
    THROW 51029, 'El principal mes_runtime no existe.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    CREATE TABLE nav.formatos_palet_orden_entrada
    (
        formato_palet_orden_entrada_id bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_nav_formatos_palet_orden_entrada PRIMARY KEY,
        orden_entrada_id bigint NOT NULL,
        producto_codigo nvarchar(50) NOT NULL,
        codigo_formato nvarchar(50) NOT NULL,
        unidades_por_palet int NOT NULL,
        datos_nav_originales nvarchar(max) NOT NULL,
        consultado_utc datetime2(3) NOT NULL
            CONSTRAINT DF_nav_formatos_palet_consultado DEFAULT (SYSUTCDATETIME()),
        version rowversion NOT NULL,
        CONSTRAINT FK_nav_formatos_palet_entrada_orden FOREIGN KEY (orden_entrada_id)
            REFERENCES nav.ordenes_entrada (orden_entrada_id),
        CONSTRAINT UQ_nav_formatos_palet_entrada_orden_codigo
            UNIQUE (orden_entrada_id, codigo_formato),
        CONSTRAINT CK_nav_formatos_palet_entrada_producto
            CHECK (LEN(LTRIM(RTRIM(producto_codigo))) > 0),
        CONSTRAINT CK_nav_formatos_palet_entrada_codigo
            CHECK (UPPER(LTRIM(RTRIM(codigo_formato))) = N'POK'),
        CONSTRAINT CK_nav_formatos_palet_entrada_unidades
            CHECK (unidades_por_palet > 0),
        CONSTRAINT CK_nav_formatos_palet_entrada_json
            CHECK (ISJSON(datos_nav_originales) = 1)
    );

    DECLARE @registrar_formato nvarchar(max) = N'
CREATE PROCEDURE nav.registrar_formato_palet_snapshot_orden
    @orden_entrada_id bigint,
    @snapshot_hash binary(32),
    @producto_codigo nvarchar(50),
    @codigo_formato nvarchar(50),
    @unidades_por_palet int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @orden_entrada_id IS NULL OR @orden_entrada_id <= 0
        THROW 55800, ''La orden de entrada no es valida.'', 1;
    SET @producto_codigo = UPPER(NULLIF(LTRIM(RTRIM(@producto_codigo)), N''''));
    SET @codigo_formato = UPPER(NULLIF(LTRIM(RTRIM(@codigo_formato)), N''''));
    IF @producto_codigo IS NULL
        THROW 55801, ''El producto del formato no es valido.'', 1;
    IF @codigo_formato <> N''POK''
        THROW 55802, ''El formato de palet debe ser POK.'', 1;
    IF @unidades_por_palet IS NULL OR @unidades_por_palet <= 0
        THROW 55803, ''Las unidades por palet deben ser un entero positivo.'', 1;

    DECLARE @snapshot_json nvarchar(max), @producto_orden nvarchar(50);
    SELECT @snapshot_json = snapshot_json, @producto_orden = UPPER(producto_codigo)
    FROM nav.ordenes_entrada WITH (UPDLOCK, HOLDLOCK)
    WHERE orden_entrada_id = @orden_entrada_id
      AND snapshot_hash = @snapshot_hash;

    IF @snapshot_json IS NULL
        THROW 55804, ''El formato no corresponde al snapshot NAV persistido.'', 1;
    IF @producto_orden <> @producto_codigo
       OR UPPER(JSON_VALUE(@snapshot_json, ''$.palletFormat.productNumber'')) <> @producto_codigo
       OR UPPER(JSON_VALUE(@snapshot_json, ''$.palletFormat.code'')) <> N''POK''
       OR TRY_CONVERT(decimal(18,8), JSON_VALUE(
              @snapshot_json, ''$.palletFormat.quantityPerUnitMeasure''))
              <> CONVERT(decimal(18,8), @unidades_por_palet)
        THROW 55804, ''El formato no corresponde al snapshot NAV persistido.'', 1;

    DELETE FROM nav.formatos_palet_orden_entrada
    WHERE orden_entrada_id = @orden_entrada_id;

    INSERT nav.formatos_palet_orden_entrada
        (orden_entrada_id, producto_codigo, codigo_formato,
         unidades_por_palet, datos_nav_originales)
    VALUES
        (@orden_entrada_id, @producto_codigo, N''POK'', @unidades_por_palet,
         (SELECT @producto_codigo AS Item_No, N''POK'' AS Code,
                 @unidades_por_palet AS Qty_per_Unit_of_Measure
          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
END;';
    EXEC sys.sp_executesql @registrar_formato;

    DECLARE @promover_formato nvarchar(max) = N'
ALTER PROCEDURE nav.promover_orden_entrada_con_lote_nav
    @promocion_id uniqueidentifier,
    @orden_entrada_id bigint,
    @operacion_codigo nvarchar(30),
    @orden_id bigint OUTPUT,
    @resultado nvarchar(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @orden_id = NULL;
    SET @resultado = NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @lote nvarchar(50), @producto_codigo nvarchar(50),
                @codigo_formato nvarchar(50), @unidades_por_palet int,
                @datos_nav_originales nvarchar(max);
        SELECT @lote = lote, @producto_codigo = UPPER(producto_codigo)
        FROM nav.ordenes_entrada WITH (UPDLOCK, HOLDLOCK)
        WHERE orden_entrada_id = @orden_entrada_id;
        IF @producto_codigo IS NULL
            THROW 55605, ''La orden de entrada no existe.'', 1;

        IF (SELECT COUNT(*) FROM nav.formatos_palet_orden_entrada
            WHERE orden_entrada_id = @orden_entrada_id
              AND codigo_formato = N''POK'') <> 1
            THROW 55614, ''La orden debe contener exactamente un formato POK.'', 1;

        SELECT @codigo_formato = codigo_formato,
               @unidades_por_palet = unidades_por_palet,
               @datos_nav_originales = datos_nav_originales
        FROM nav.formatos_palet_orden_entrada WITH (UPDLOCK, HOLDLOCK)
        WHERE orden_entrada_id = @orden_entrada_id
          AND codigo_formato = N''POK'';
        IF @codigo_formato <> N''POK'' OR @unidades_por_palet <= 0
           OR NOT EXISTS
              (SELECT 1 FROM nav.formatos_palet_orden_entrada
               WHERE orden_entrada_id = @orden_entrada_id
                 AND producto_codigo = @producto_codigo
                 AND codigo_formato = N''POK'')
            THROW 55615, ''El formato POK no corresponde al producto o cantidad.'', 1;

        SET @lote = LTRIM(RTRIM(ISNULL(@lote, N'''')));
        EXEC nav.promover_orden_entrada
            @promocion_id = @promocion_id,
            @orden_entrada_id = @orden_entrada_id,
            @lote = @lote,
            @operacion_codigo = @operacion_codigo,
            @lote_proporcionado_por = N''NAV:WS_CPP_OPLanzadas.Cod_Lote_Salida'',
            @orden_id = @orden_id OUTPUT,
            @resultado = @resultado OUTPUT;

        IF @resultado IN (N''CREADA'', N''SIN_CAMBIOS'')
        BEGIN
            DECLARE @formato_existente_id bigint,
                    @unidades_existentes int,
                    @formato_activo bit,
                    @producto_orden nvarchar(50);
            SELECT @producto_orden = UPPER(producto_codigo)
            FROM prod.ordenes WITH (UPDLOCK, HOLDLOCK)
            WHERE orden_id = @orden_id;
            IF @producto_orden <> @producto_codigo
                THROW 55615, ''El formato POK no corresponde al producto de la orden.'', 1;

            SELECT @formato_existente_id = formato_palet_orden_id,
                   @unidades_existentes = unidades_por_palet,
                   @formato_activo = activo
            FROM prod.formatos_palet_orden WITH (UPDLOCK, HOLDLOCK)
            WHERE orden_id = @orden_id AND codigo_formato = N''POK'';

            IF @formato_existente_id IS NULL
                INSERT prod.formatos_palet_orden
                    (orden_id, codigo_formato, unidades_por_palet, descripcion,
                     es_predeterminado_nav, datos_nav_originales, activo)
                VALUES
                    (@orden_id, N''POK'', @unidades_por_palet,
                     N''Formato de palet NAV POK'', 1, @datos_nav_originales, 1);
            ELSE IF @unidades_existentes <> @unidades_por_palet
                 OR @formato_activo <> 1
                THROW 55616, ''La orden productiva ya contiene otro formato POK.'', 1;
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SET @orden_id = NULL;
        SET @resultado = NULL;
        THROW;
    END CATCH;
END;';
    EXEC sys.sp_executesql @promover_formato;

    GRANT EXECUTE ON OBJECT::nav.registrar_formato_palet_snapshot_orden TO mes_runtime;
    GRANT EXECUTE ON OBJECT::nav.promover_orden_entrada_con_lote_nav TO mes_runtime;

    IF OBJECT_ID(N'nav.formatos_palet_orden_entrada', N'U') IS NULL
     OR OBJECT_ID(N'nav.registrar_formato_palet_snapshot_orden', N'P') IS NULL
        THROW 51030, 'No se crearon todos los objetos del paquete 022.', 1;
    IF OBJECT_DEFINITION(OBJECT_ID(N'nav.promover_orden_entrada_con_lote_nav'))
       NOT LIKE N'%prod.formatos_palet_orden%'
        THROW 51031, 'La promocion no incorpora el formato POK.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
