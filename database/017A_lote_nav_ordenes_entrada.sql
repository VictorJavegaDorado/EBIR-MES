SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'nav.ordenes_entrada', N'U') IS NULL
 OR OBJECT_ID(N'nav.promociones_orden', N'U') IS NULL
 OR OBJECT_ID(N'nav.aplicar_snapshot_orden', N'P') IS NULL
 OR OBJECT_ID(N'nav.promover_orden_entrada', N'P') IS NULL
    THROW 51018, 'El paquete 017 requiere los paquetes 015 y 016.', 1;

IF COL_LENGTH(N'nav.ordenes_entrada', N'lote') IS NOT NULL
 OR OBJECT_ID(N'nav.registrar_lote_snapshot_orden', N'P') IS NOT NULL
 OR OBJECT_ID(N'nav.promover_orden_entrada_con_lote_nav', N'P') IS NOT NULL
    THROW 51019, 'El paquete 017 ya existe total o parcialmente.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    ALTER TABLE nav.ordenes_entrada
        ADD lote nvarchar(50) NULL;

    ALTER TABLE nav.ordenes_entrada ADD CONSTRAINT CK_nav_ordenes_entrada_lote
        CHECK (lote IS NULL OR LEN(LTRIM(RTRIM(lote))) > 0);

    DECLARE @registrar_lote nvarchar(max) = N'
CREATE PROCEDURE nav.registrar_lote_snapshot_orden
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
    IF @lote IS NULL
        THROW 55701, ''El lote de salida NAV es obligatorio.'', 1;

    UPDATE nav.ordenes_entrada WITH (UPDLOCK, HOLDLOCK)
    SET lote = @lote
    WHERE orden_entrada_id = @orden_entrada_id
      AND snapshot_hash = @snapshot_hash;
    IF @@ROWCOUNT <> 1
        THROW 55702, ''El lote no corresponde al snapshot NAV persistido.'', 1;
END;';
    EXEC sys.sp_executesql @registrar_lote;

    DECLARE @promover nvarchar(max) = N'
CREATE PROCEDURE nav.promover_orden_entrada_con_lote_nav
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

    SET @lote = NULLIF(LTRIM(RTRIM(@lote)), N'''');
    IF @lote IS NULL
        THROW 55602, ''La orden de entrada no contiene un lote NAV valido.'', 1;

    EXEC nav.promover_orden_entrada
        @promocion_id = @promocion_id,
        @orden_entrada_id = @orden_entrada_id,
        @lote = @lote,
        @operacion_codigo = @operacion_codigo,
        @lote_proporcionado_por = N''NAV:WS_CPP_OPLanzadas.Cod_Lote_Salida'',
        @orden_id = @orden_id OUTPUT,
        @resultado = @resultado OUTPUT;
END;';
    EXEC sys.sp_executesql @promover;

    GRANT EXECUTE ON OBJECT::nav.registrar_lote_snapshot_orden TO mes_runtime;
    GRANT EXECUTE ON OBJECT::nav.promover_orden_entrada_con_lote_nav TO mes_runtime;
    REVOKE EXECUTE ON OBJECT::nav.promover_orden_entrada FROM mes_runtime;

    IF COL_LENGTH(N'nav.ordenes_entrada', N'lote') IS NULL
     OR OBJECT_ID(N'nav.registrar_lote_snapshot_orden', N'P') IS NULL
     OR OBJECT_ID(N'nav.promover_orden_entrada_con_lote_nav', N'P') IS NULL
        THROW 51020, 'No se crearon todos los objetos del paquete 017.', 1;

    IF NOT EXISTS
    (
        SELECT 1 FROM sys.database_permissions
        WHERE class = 1
          AND major_id IN
          (
              OBJECT_ID(N'nav.registrar_lote_snapshot_orden'),
              OBJECT_ID(N'nav.promover_orden_entrada_con_lote_nav')
          )
          AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
          AND permission_name = N'EXECUTE'
          AND state IN (N'G', N'W')
        GROUP BY grantee_principal_id
        HAVING COUNT(DISTINCT major_id) = 2
    )
        THROW 51021, 'mes_runtime no recibio los contratos del paquete 017.', 1;

    IF EXISTS
    (
        SELECT 1 FROM sys.database_permissions
        WHERE class = 1
          AND major_id = OBJECT_ID(N'nav.promover_orden_entrada')
          AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
          AND permission_name = N'EXECUTE'
          AND state IN (N'G', N'W')
    )
        THROW 51022, 'mes_runtime conserva acceso a la promocion manual 016.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
