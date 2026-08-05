/*
Paquete 025A - Grupo contable de producto y reglas del cierre de palet.
Base exclusiva: EBIR_MES_TEST.

El grupo contable se captura en el snapshot NAV, se fija al promocionar la
orden y se incorpora a los datos persistidos de la etiqueta. El cierre exige
que quien lo realiza este produciendo en la mesa y reserva la autorizacion de
supervisor para el ultimo palet de la orden.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'nav.ordenes_entrada', N'U') IS NULL
 OR OBJECT_ID(N'prod.ordenes', N'U') IS NULL
 OR OBJECT_ID(N'prod.cerrar_palet', N'P') IS NULL
 OR OBJECT_ID(N'nav.promover_orden_entrada_con_lote_nav', N'P') IS NULL
 OR OBJECT_ID(N'prod.fichajes', N'U') IS NULL
 OR OBJECT_ID(N'prod.paros_operario', N'U') IS NULL
    THROW 51036, 'Faltan objetos requeridos por el paquete 025A.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH(N'prod.ordenes', N'grupo_contable_producto') IS NULL
        ALTER TABLE prod.ordenes
            ADD grupo_contable_producto nvarchar(50) NULL;

    IF OBJECT_ID(N'nav.grupos_contables_producto_orden_entrada', N'U') IS NULL
    BEGIN
        CREATE TABLE nav.grupos_contables_producto_orden_entrada
        (
            grupo_contable_producto_orden_entrada_id bigint IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_nav_grupos_contables_producto_orden_entrada PRIMARY KEY,
            orden_entrada_id bigint NOT NULL,
            producto_codigo nvarchar(50) NOT NULL,
            grupo_contable_producto nvarchar(50) NOT NULL,
            datos_nav_originales nvarchar(max) NOT NULL,
            consultado_utc datetime2(3) NOT NULL
                CONSTRAINT DF_nav_grupos_contables_producto_consultado
                DEFAULT (SYSUTCDATETIME()),
            version rowversion NOT NULL,
            CONSTRAINT FK_nav_grupos_contables_producto_orden
                FOREIGN KEY (orden_entrada_id)
                REFERENCES nav.ordenes_entrada (orden_entrada_id),
            CONSTRAINT UQ_nav_grupos_contables_producto_orden
                UNIQUE (orden_entrada_id),
            CONSTRAINT CK_nav_grupos_contables_producto_producto
                CHECK (LEN(LTRIM(RTRIM(producto_codigo))) > 0),
            CONSTRAINT CK_nav_grupos_contables_producto_codigo
                CHECK (LEN(LTRIM(RTRIM(grupo_contable_producto))) > 0),
            CONSTRAINT CK_nav_grupos_contables_producto_json
                CHECK (ISJSON(datos_nav_originales) = 1)
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

CREATE OR ALTER PROCEDURE nav.registrar_grupo_contable_producto_snapshot_orden
    @orden_entrada_id bigint,
    @snapshot_hash binary(32),
    @producto_codigo nvarchar(50),
    @grupo_contable_producto nvarchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @orden_entrada_id IS NULL OR @orden_entrada_id <= 0
        THROW 55900, 'La orden de entrada no es valida.', 1;

    SET @producto_codigo = UPPER(NULLIF(LTRIM(RTRIM(@producto_codigo)), N''));
    SET @grupo_contable_producto =
        UPPER(NULLIF(LTRIM(RTRIM(@grupo_contable_producto)), N''));

    IF @producto_codigo IS NULL OR LEN(@producto_codigo) > 50
        THROW 55901, 'El producto del grupo contable no es valido.', 1;
    IF @grupo_contable_producto IS NULL OR LEN(@grupo_contable_producto) > 50
        THROW 55902, 'El grupo contable de producto no es valido.', 1;

    DECLARE @snapshot_json nvarchar(max), @producto_orden nvarchar(50);
    SELECT
        @snapshot_json = snapshot_json,
        @producto_orden = UPPER(producto_codigo)
    FROM nav.ordenes_entrada WITH (UPDLOCK, HOLDLOCK)
    WHERE orden_entrada_id = @orden_entrada_id
      AND snapshot_hash = @snapshot_hash;

    IF @snapshot_json IS NULL
       OR @producto_orden <> @producto_codigo
       OR UPPER(JSON_VALUE(
              @snapshot_json, '$.productPostingGroup.productNumber'))
              <> @producto_codigo
       OR UPPER(JSON_VALUE(
              @snapshot_json, '$.productPostingGroup.code'))
              <> @grupo_contable_producto
        THROW 55903, 'El grupo contable no corresponde al snapshot NAV persistido.', 1;

    DELETE FROM nav.grupos_contables_producto_orden_entrada
    WHERE orden_entrada_id = @orden_entrada_id;

    INSERT nav.grupos_contables_producto_orden_entrada
    (
        orden_entrada_id,
        producto_codigo,
        grupo_contable_producto,
        datos_nav_originales
    )
    VALUES
    (
        @orden_entrada_id,
        @producto_codigo,
        @grupo_contable_producto,
        (SELECT
            @producto_codigo AS No,
            @grupo_contable_producto AS Gen_Prod_Posting_Group
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    );
END;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @promocion nvarchar(max) =
        OBJECT_DEFINITION(OBJECT_ID(N'nav.promover_orden_entrada_con_lote_nav'));
    SET @promocion = REPLACE(@promocion, NCHAR(13) + NCHAR(10), NCHAR(10));
    IF CHARINDEX(N'CREATE PROCEDURE', @promocion) > 0
        SET @promocion = STUFF(
            @promocion,
            CHARINDEX(N'CREATE PROCEDURE', @promocion),
            LEN(N'CREATE PROCEDURE'),
            N'ALTER PROCEDURE');

    IF @promocion NOT LIKE N'%grupos_contables_producto_orden_entrada%'
    BEGIN
        DECLARE @promocion_declaracion nvarchar(max) =
            N'@codigo_formato nvarchar(50), @unidades_por_palet int,' + CHAR(10) +
            N'                @datos_nav_originales nvarchar(max);';
        DECLARE @promocion_declaracion_nueva nvarchar(max) =
            N'@codigo_formato nvarchar(50), @unidades_por_palet int,' + CHAR(10) +
            N'                @datos_nav_originales nvarchar(max),' + CHAR(10) +
            N'                @grupo_contable_producto nvarchar(50);';

        IF CHARINDEX(@promocion_declaracion, @promocion) = 0
            THROW 51037, 'La promocion no coincide con la base esperada.', 1;
        SET @promocion = REPLACE(
            @promocion, @promocion_declaracion, @promocion_declaracion_nueva);

        DECLARE @promocion_antes_lote nvarchar(max) =
            N'        SET @lote = LTRIM(RTRIM(ISNULL(@lote, N'''')));';
        DECLARE @promocion_grupo nvarchar(max) =
            N'        IF (SELECT COUNT(*)' + CHAR(10) +
            N'            FROM nav.grupos_contables_producto_orden_entrada' + CHAR(10) +
            N'            WHERE orden_entrada_id = @orden_entrada_id) <> 1' + CHAR(10) +
            N'            THROW 55617, ''La orden debe contener un unico grupo contable de producto.'' , 1;' + CHAR(10) + CHAR(10) +
            N'        SELECT @grupo_contable_producto = grupo_contable_producto' + CHAR(10) +
            N'        FROM nav.grupos_contables_producto_orden_entrada WITH (UPDLOCK, HOLDLOCK)' + CHAR(10) +
            N'        WHERE orden_entrada_id = @orden_entrada_id' + CHAR(10) +
            N'          AND producto_codigo = @producto_codigo;' + CHAR(10) +
            N'        IF NULLIF(LTRIM(RTRIM(@grupo_contable_producto)), N'''') IS NULL' + CHAR(10) +
            N'            THROW 55618, ''El grupo contable no corresponde al producto de la orden.'', 1;' + CHAR(10) + CHAR(10) +
            @promocion_antes_lote;

        IF CHARINDEX(@promocion_antes_lote, @promocion) = 0
            THROW 51037, 'La promocion no contiene el punto de validacion esperado.', 1;
        SET @promocion = REPLACE(
            @promocion, @promocion_antes_lote, @promocion_grupo);

        DECLARE @promocion_producto nvarchar(max) =
            N'            IF @producto_orden <> @producto_codigo' + CHAR(10) +
            N'                THROW 55615, ''El formato POK no corresponde al producto de la orden.'', 1;';
        DECLARE @promocion_producto_nuevo nvarchar(max) =
            @promocion_producto + CHAR(10) + CHAR(10) +
            N'            IF EXISTS' + CHAR(10) +
            N'            (' + CHAR(10) +
            N'                SELECT 1 FROM prod.ordenes' + CHAR(10) +
            N'                WHERE orden_id = @orden_id' + CHAR(10) +
            N'                  AND grupo_contable_producto IS NOT NULL' + CHAR(10) +
            N'                  AND grupo_contable_producto <> @grupo_contable_producto' + CHAR(10) +
            N'            )' + CHAR(10) +
            N'                THROW 55619, ''La orden productiva ya contiene otro grupo contable.'', 1;' + CHAR(10) + CHAR(10) +
            N'            UPDATE prod.ordenes' + CHAR(10) +
            N'            SET grupo_contable_producto = @grupo_contable_producto' + CHAR(10) +
            N'            WHERE orden_id = @orden_id;';

        IF CHARINDEX(@promocion_producto, @promocion) = 0
            THROW 51037, 'La promocion no contiene la comprobacion de producto esperada.', 1;
        SET @promocion = REPLACE(
            @promocion, @promocion_producto, @promocion_producto_nuevo);

        EXEC sys.sp_executesql @promocion;
    END;

    DECLARE @cierre nvarchar(max) =
        OBJECT_DEFINITION(OBJECT_ID(N'prod.cerrar_palet'));
    SET @cierre = REPLACE(@cierre, NCHAR(13) + NCHAR(10), NCHAR(10));
    IF CHARINDEX(N'CREATE PROCEDURE', @cierre) > 0
        SET @cierre = STUFF(
            @cierre,
            CHARINDEX(N'CREATE PROCEDURE', @cierre),
            LEN(N'CREATE PROCEDURE'),
            N'ALTER PROCEDURE');
    IF CHARINDEX(N'CREATE   PROCEDURE', @cierre) > 0
        SET @cierre = STUFF(
            @cierre,
            CHARINDEX(N'CREATE   PROCEDURE', @cierre),
            LEN(N'CREATE   PROCEDURE'),
            N'ALTER PROCEDURE');

    IF @cierre NOT LIKE N'%grupo_contable_producto%'
    BEGIN
        DECLARE @cierre_producto nvarchar(max) =
            N'        @producto_barcode nvarchar(100),' + CHAR(10) +
            N'        @lote nvarchar(50),';
        DECLARE @cierre_producto_nuevo nvarchar(max) =
            N'        @producto_barcode nvarchar(100),' + CHAR(10) +
            N'        @grupo_contable_producto nvarchar(50),' + CHAR(10) +
            N'        @lote nvarchar(50),';
        IF CHARINDEX(@cierre_producto, @cierre) = 0
            THROW 51038, 'El cierre no coincide con la base esperada.', 1;
        SET @cierre = REPLACE(@cierre, @cierre_producto, @cierre_producto_nuevo);

        DECLARE @cierre_reserva nvarchar(max) =
            N'    IF @orden_id IS NULL' + CHAR(10) +
            N'        THROW 51403, ''Reserva activa no encontrada.'', 1;';
        DECLARE @cierre_fichaje nvarchar(max) =
            @cierre_reserva + CHAR(10) + CHAR(10) +
            N'    IF NOT EXISTS' + CHAR(10) +
            N'    (' + CHAR(10) +
            N'        SELECT 1' + CHAR(10) +
            N'        FROM prod.fichajes f WITH (UPDLOCK, HOLDLOCK)' + CHAR(10) +
            N'        WHERE f.sesion_linea_id = @sesion_linea_id' + CHAR(10) +
            N'          AND f.empleado_id = @cerrado_por_empleado_id' + CHAR(10) +
            N'          AND f.salida_utc IS NULL' + CHAR(10) +
            N'          AND NOT EXISTS' + CHAR(10) +
            N'          (' + CHAR(10) +
            N'              SELECT 1 FROM prod.paros_operario po WITH (UPDLOCK, HOLDLOCK)' + CHAR(10) +
            N'              WHERE po.fichaje_id = f.fichaje_id' + CHAR(10) +
            N'                AND po.fin_utc IS NULL' + CHAR(10) +
            N'          )' + CHAR(10) +
            N'    )' + CHAR(10) +
            N'        THROW 51410, ''El cierre requiere un operario activo y produciendo en esta mesa.'', 1;';
        SET @cierre = REPLACE(@cierre, @cierre_reserva, @cierre_fichaje);

        DECLARE @cierre_orden nvarchar(max) =
            N'        @producto_barcode = producto_barcode,' + CHAR(10) +
            N'        @lote = lote';
        DECLARE @cierre_orden_nuevo nvarchar(max) =
            N'        @producto_barcode = producto_barcode,' + CHAR(10) +
            N'        @grupo_contable_producto = grupo_contable_producto,' + CHAR(10) +
            N'        @lote = lote';
        IF CHARINDEX(@cierre_orden, @cierre) = 0
            THROW 51038, 'El cierre no contiene el snapshot de producto esperado.', 1;
        SET @cierre = REPLACE(@cierre, @cierre_orden, @cierre_orden_nuevo);

        DECLARE @cierre_objetivo nvarchar(max) =
            N'    IF @buenas + @cantidad_buena > @objetivo';
        DECLARE @cierre_grupo nvarchar(max) =
            N'    IF NULLIF(LTRIM(RTRIM(@grupo_contable_producto)), N'''') IS NULL' + CHAR(10) +
            N'        THROW 51411, ''La orden no dispone de grupo contable de producto.'', 1;' + CHAR(10) + CHAR(10) +
            @cierre_objetivo;
        SET @cierre = REPLACE(@cierre, @cierre_objetivo, @cierre_grupo);

        DECLARE @cierre_supervisor nvarchar(max) =
            N'    IF (@es_ultimo = 1 OR @es_parcial = 1)';
        IF CHARINDEX(@cierre_supervisor, @cierre) = 0
            THROW 51038, 'El cierre no contiene la regla de supervisor esperada.', 1;
        SET @cierre = REPLACE(
            @cierre,
            @cierre_supervisor,
            N'    IF @es_ultimo = 1');
        SET @cierre = REPLACE(
            @cierre,
            N'El ultimo palet o un palet parcial requiere supervisor.',
            N'El ultimo palet requiere supervisor.');

        DECLARE @cierre_etiqueta nvarchar(max) =
            N'            @producto_descripcion AS producto_descripcion,' + CHAR(10) +
            N'            @producto_barcode AS producto_barcode,';
        DECLARE @cierre_etiqueta_nueva nvarchar(max) =
            N'            @producto_descripcion AS producto_descripcion,' + CHAR(10) +
            N'            @grupo_contable_producto AS grupo_contable_producto,' + CHAR(10) +
            N'            @producto_barcode AS producto_barcode,';
        IF CHARINDEX(@cierre_etiqueta, @cierre) = 0
            THROW 51038, 'El cierre no contiene el payload de etiqueta esperado.', 1;
        SET @cierre = REPLACE(@cierre, @cierre_etiqueta, @cierre_etiqueta_nueva);

        EXEC sys.sp_executesql @cierre;
    END;

    GRANT EXECUTE ON OBJECT::nav.registrar_grupo_contable_producto_snapshot_orden
        TO mes_runtime;
    GRANT EXECUTE ON OBJECT::nav.promover_orden_entrada_con_lote_nav TO mes_runtime;
    GRANT EXECUTE ON OBJECT::prod.cerrar_palet TO mes_runtime;

    IF COL_LENGTH(N'prod.ordenes', N'grupo_contable_producto') IS NULL
     OR OBJECT_ID(N'nav.grupos_contables_producto_orden_entrada', N'U') IS NULL
     OR OBJECT_ID(N'nav.registrar_grupo_contable_producto_snapshot_orden', N'P') IS NULL
        THROW 51039, 'No se crearon todos los objetos del paquete 025A.', 1;
    IF OBJECT_DEFINITION(OBJECT_ID(N'nav.promover_orden_entrada_con_lote_nav'))
       NOT LIKE N'%grupos_contables_producto_orden_entrada%'
        THROW 51040, 'La promocion no incorpora el grupo contable.', 1;
    IF OBJECT_DEFINITION(OBJECT_ID(N'prod.cerrar_palet'))
       NOT LIKE N'%El cierre requiere un operario activo y produciendo%'
     OR OBJECT_DEFINITION(OBJECT_ID(N'prod.cerrar_palet'))
       NOT LIKE N'%@grupo_contable_producto AS grupo_contable_producto%'
     OR OBJECT_DEFINITION(OBJECT_ID(N'prod.cerrar_palet'))
       LIKE N'%@es_ultimo = 1 OR @es_parcial = 1%'
        THROW 51041, 'El cierre de palet no contiene las reglas del paquete 025A.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
