SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'nav.ordenes_entrada', N'U') IS NULL
 OR OBJECT_ID(N'nav.registrar_lote_snapshot_orden', N'P') IS NULL
 OR OBJECT_ID(N'nav.promover_orden_entrada_con_lote_nav', N'P') IS NULL
 OR OBJECT_ID(N'nav.promover_orden_entrada', N'P') IS NULL
 OR OBJECT_ID(N'nav.promociones_orden', N'U') IS NULL
 OR OBJECT_ID(N'prod.ordenes', N'U') IS NULL
    THROW 51023, 'El paquete 021 requiere los paquetes 015, 016 y 017.', 1;

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'nav.promociones_orden')
      AND name = N'CK_nav_promociones_lote'
)
 OR NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'prod.ordenes')
      AND name = N'CK_prod_ordenes_lote'
)
    THROW 51024, 'El paquete 021 requiere las restricciones de lote vigentes.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    ALTER TABLE nav.promociones_orden DROP CONSTRAINT CK_nav_promociones_lote;
    ALTER TABLE nav.promociones_orden ADD CONSTRAINT CK_nav_promociones_lote
        CHECK (LEN(LTRIM(RTRIM(lote))) >= 0);

    ALTER TABLE prod.ordenes DROP CONSTRAINT CK_prod_ordenes_lote;
    ALTER TABLE prod.ordenes ADD CONSTRAINT CK_prod_ordenes_lote
        CHECK (LEN(LTRIM(RTRIM(lote))) >= 0);

    DECLARE @registrar_lote nvarchar(max) = N'
ALTER PROCEDURE nav.registrar_lote_snapshot_orden
    @orden_entrada_id bigint,
    @snapshot_hash binary(32),
    @lote nvarchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @orden_entrada_id IS NULL OR @orden_entrada_id <= 0
        THROW 55700, ''La orden de entrada no es valida.'', 1;
    SET @lote = NULLIF(LTRIM(RTRIM(@lote)), N'''');

    UPDATE nav.ordenes_entrada WITH (UPDLOCK, HOLDLOCK)
    SET lote = @lote
    WHERE orden_entrada_id = @orden_entrada_id
      AND snapshot_hash = @snapshot_hash;
    IF @@ROWCOUNT <> 1
        THROW 55702, ''El lote no corresponde al snapshot NAV persistido.'', 1;
END;';
    EXEC sys.sp_executesql @registrar_lote;

    DECLARE @promover_con_lote_nav nvarchar(max) = N'
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

    DECLARE @lote nvarchar(50);
    SELECT @lote = lote
    FROM nav.ordenes_entrada
    WHERE orden_entrada_id = @orden_entrada_id;

    SET @lote = LTRIM(RTRIM(ISNULL(@lote, N'''')));

    EXEC nav.promover_orden_entrada
        @promocion_id = @promocion_id,
        @orden_entrada_id = @orden_entrada_id,
        @lote = @lote,
        @operacion_codigo = @operacion_codigo,
        @lote_proporcionado_por = N''NAV:WS_CPP_OPLanzadas.Cod_Lote_Salida'',
        @orden_id = @orden_id OUTPUT,
        @resultado = @resultado OUTPUT;
END;';
    EXEC sys.sp_executesql @promover_con_lote_nav;

    DECLARE @promover_base nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID(N'nav.promover_orden_entrada', N'P'));
    IF @promover_base IS NULL
       OR @promover_base NOT LIKE N'%SET @lote = NULLIF(LTRIM(RTRIM(@lote)), N'''');%'
       OR @promover_base NOT LIKE N'%IF @lote IS NULL THROW 55602%'
        THROW 51025, 'La promocion base no coincide con el contrato 016 esperado.', 1;

    SET @promover_base = REPLACE(
        @promover_base,
        N'SET @lote = NULLIF(LTRIM(RTRIM(@lote)), N'''');',
        N'SET @lote = LTRIM(RTRIM(ISNULL(@lote, N'''')));');
    SET @promover_base = REPLACE(
        @promover_base,
        N'    IF @lote IS NULL THROW 55602, ''El lote es obligatorio.'', 1;' + CHAR(13) + CHAR(10),
        N'');
    SET @promover_base = STUFF(
        @promover_base,
        CHARINDEX(N'CREATE PROCEDURE nav.promover_orden_entrada', @promover_base),
        LEN(N'CREATE PROCEDURE nav.promover_orden_entrada'),
        N'ALTER PROCEDURE nav.promover_orden_entrada');
    EXEC sys.sp_executesql @promover_base;

    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'nav.promociones_orden')
          AND name = N'CK_nav_promociones_lote'
          AND definition NOT LIKE N'%>=%0%'
    )
       OR EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'prod.ordenes')
          AND name = N'CK_prod_ordenes_lote'
          AND definition NOT LIKE N'%>=%0%'
    )
        THROW 51026, 'No se actualizaron las restricciones de lote pendiente.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO