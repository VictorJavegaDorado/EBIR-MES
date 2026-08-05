/*
Paquete 025B - Adopcion segura del grupo contable en ordenes ya promovidas.
Base exclusiva: EBIR_MES_TEST.

Permite tratar como SIN_CAMBIOS el primer snapshot que solo agrega
productPostingGroup a una orden productiva existente. Cualquier diferencia en
el JSON base, lote, operacion o tiempo conserva el resultado REVISION.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;
GO

IF OBJECT_ID(N'nav.promover_orden_entrada', N'P') IS NULL
 OR OBJECT_ID(N'nav.promover_orden_entrada_con_lote_nav', N'P') IS NULL
 OR OBJECT_ID(N'nav.grupos_contables_producto_orden_entrada', N'U') IS NULL
 OR COL_LENGTH(N'prod.ordenes', N'grupo_contable_producto') IS NULL
    THROW 51043, 'Faltan objetos requeridos por el paquete 025B.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @definicion nvarchar(max) =
        OBJECT_DEFINITION(OBJECT_ID(N'nav.promover_orden_entrada'));
    SET @definicion = REPLACE(@definicion, NCHAR(13) + NCHAR(10), NCHAR(10));

    IF CHARINDEX(N'CREATE PROCEDURE', @definicion) > 0
        SET @definicion = STUFF(
            @definicion,
            CHARINDEX(N'CREATE PROCEDURE', @definicion),
            LEN(N'CREATE PROCEDURE'),
            N'ALTER PROCEDURE');
    IF CHARINDEX(N'CREATE   PROCEDURE', @definicion) > 0
        SET @definicion = STUFF(
            @definicion,
            CHARINDEX(N'CREATE   PROCEDURE', @definicion),
            LEN(N'CREATE   PROCEDURE'),
            N'ALTER PROCEDURE');

    IF @definicion NOT LIKE N'%ADOPCION_GRUPO_CONTABLE_025B%'
    BEGIN
        DECLARE @bloque_actual nvarchar(max) =
            N'            IF @ultimo_hash=@snapshot_hash AND @ultimo_lote=@lote' + NCHAR(10) +
            N'               AND @ultima_operacion=@operacion_codigo AND @ultimo_tiempo=@tiempo' + NCHAR(10) +
            N'                SET @resultado=N''SIN_CAMBIOS'';' + NCHAR(10) +
            N'            ELSE' + NCHAR(10) +
            N'            BEGIN' + NCHAR(10) +
            N'                UPDATE prod.ordenes SET estado=N''REVISION'' WHERE orden_id=@orden_id;' + NCHAR(10) +
            N'                SET @resultado=N''REVISION'';' + NCHAR(10) +
            N'            END;';

        DECLARE @bloque_nuevo nvarchar(max) =
            N'            IF @ultimo_hash=@snapshot_hash AND @ultimo_lote=@lote' + NCHAR(10) +
            N'               AND @ultima_operacion=@operacion_codigo AND @ultimo_tiempo=@tiempo' + NCHAR(10) +
            N'                SET @resultado=N''SIN_CAMBIOS'';' + NCHAR(10) +
            N'            /* ADOPCION_GRUPO_CONTABLE_025B */' + NCHAR(10) +
            N'            ELSE IF @ultimo_lote=@lote' + NCHAR(10) +
            N'                AND @ultima_operacion=@operacion_codigo' + NCHAR(10) +
            N'                AND @ultimo_tiempo=@tiempo' + NCHAR(10) +
            N'                AND EXISTS' + NCHAR(10) +
            N'                (' + NCHAR(10) +
            N'                    SELECT 1' + NCHAR(10) +
            N'                    FROM prod.ordenes p' + NCHAR(10) +
            N'                    JOIN nav.grupos_contables_producto_orden_entrada g' + NCHAR(10) +
            N'                      ON g.orden_entrada_id=@orden_entrada_id' + NCHAR(10) +
            N'                     AND UPPER(g.producto_codigo)=UPPER(@producto_codigo)' + NCHAR(10) +
            N'                    WHERE p.orden_id=@orden_id' + NCHAR(10) +
            N'                      AND p.grupo_contable_producto IS NULL' + NCHAR(10) +
            N'                      AND JSON_MODIFY(@snapshot_json,' + NCHAR(10) +
            N'                          ''$.productPostingGroup'',NULL)=p.datos_nav_originales' + NCHAR(10) +
            N'                      AND UPPER(JSON_VALUE(@snapshot_json,' + NCHAR(10) +
            N'                          ''$.productPostingGroup.productNumber''))=UPPER(@producto_codigo)' + NCHAR(10) +
            N'                      AND UPPER(JSON_VALUE(@snapshot_json,' + NCHAR(10) +
            N'                          ''$.productPostingGroup.code''))=UPPER(g.grupo_contable_producto)' + NCHAR(10) +
            N'                )' + NCHAR(10) +
            N'            BEGIN' + NCHAR(10) +
            N'                UPDATE p' + NCHAR(10) +
            N'                SET grupo_contable_producto=g.grupo_contable_producto,' + NCHAR(10) +
            N'                    datos_nav_originales=@snapshot_json' + NCHAR(10) +
            N'                FROM prod.ordenes p' + NCHAR(10) +
            N'                JOIN nav.grupos_contables_producto_orden_entrada g' + NCHAR(10) +
            N'                  ON g.orden_entrada_id=@orden_entrada_id' + NCHAR(10) +
            N'                 AND UPPER(g.producto_codigo)=UPPER(@producto_codigo)' + NCHAR(10) +
            N'                WHERE p.orden_id=@orden_id' + NCHAR(10) +
            N'                  AND p.grupo_contable_producto IS NULL;' + NCHAR(10) +
            N'                SET @resultado=N''SIN_CAMBIOS'';' + NCHAR(10) +
            N'            END' + NCHAR(10) +
            N'            ELSE' + NCHAR(10) +
            N'            BEGIN' + NCHAR(10) +
            N'                UPDATE prod.ordenes SET estado=N''REVISION'' WHERE orden_id=@orden_id;' + NCHAR(10) +
            N'                SET @resultado=N''REVISION'';' + NCHAR(10) +
            N'            END;';

        IF CHARINDEX(@bloque_actual, @definicion) = 0
            THROW 51044, 'La promocion base no coincide con la version esperada.', 1;
        SET @definicion = REPLACE(@definicion, @bloque_actual, @bloque_nuevo);
        EXEC sys.sp_executesql @definicion;
    END;

    GRANT EXECUTE ON OBJECT::nav.promover_orden_entrada TO mes_runtime;

    IF OBJECT_DEFINITION(OBJECT_ID(N'nav.promover_orden_entrada'))
       NOT LIKE N'%ADOPCION_GRUPO_CONTABLE_025B%'
     OR OBJECT_DEFINITION(OBJECT_ID(N'nav.promover_orden_entrada'))
       NOT LIKE N'%JSON_MODIFY(@snapshot_json%productPostingGroup%'
        THROW 51045, 'La promocion no contiene la adopcion segura 025B.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
