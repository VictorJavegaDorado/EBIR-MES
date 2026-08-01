SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 58000, 'Prueba permitida unicamente en EBIR_MES_TEST.', 1;
IF OBJECT_ID(N'nav.promover_orden_entrada', N'P') IS NULL
    THROW 58001, 'El paquete 016 no esta instalado.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @empresa_nav_id bigint =
    (
        SELECT TOP (1) empresa_nav_id FROM nav.empresas ORDER BY empresa_nav_id
    );
    IF @empresa_nav_id IS NULL THROW 58002, 'No existe empresa NAV de prueba.', 1;

    DECLARE @snapshot nvarchar(max) = N'{"environmentCode":"EBIRTEST","companyCode":"EBIR","order":{"orderNumber":"ZZ16-ORDER","status":"Released","description":"ZZ16 PRODUCTO","productNumber":"ZZ16-PROD","routingNumber":"ZZ16-RUTA","quantity":10,"locationCode":"ZZ","startingDate":null,"endingDate":null,"dueDate":null},"line":{"orderNumber":"ZZ16-ORDER","status":"Released","productNumber":"ZZ16-PROD","variantCode":"","description":"ZZ16 PRODUCTO","locationCode":"ZZ","quantity":10,"finishedQuantity":0,"remainingQuantity":10,"scrapPercent":0,"dueDate":null,"startingDate":null,"endingDate":null,"productionBomNumber":"ZZ16-BOM"},"routing":[],"components":[]}';
    INSERT nav.ordenes_entrada
    (empresa_nav_id,numero_orden,estado_nav,producto_codigo,descripcion,ruta_codigo,
     cantidad,ubicacion_codigo,snapshot_hash,snapshot_json)
    VALUES
    (@empresa_nav_id,N'ZZ16-ORDER',N'Released',N'ZZ16-PROD',N'ZZ16 PRODUCTO',
     N'ZZ16-RUTA',10,N'ZZ',HASHBYTES('SHA2_256',CONVERT(varbinary(max),@snapshot)),@snapshot);
    DECLARE @entrada bigint=SCOPE_IDENTITY();

    INSERT nav.lineas_orden_entrada
    (orden_entrada_id,estado_nav,producto_codigo,descripcion,cantidad,
     cantidad_finalizada,cantidad_pendiente,porcentaje_scrap)
    VALUES (@entrada,N'Released',N'ZZ16-PROD',N'ZZ16 PRODUCTO',10,0,10,0);
    INSERT nav.rutas_orden_entrada
    (orden_entrada_id,referencia_ruta,ruta_codigo,operacion_codigo,tipo,
     capacidad_codigo,descripcion,tiempo_preparacion,tiempo_ejecucion,
     tiempo_espera,tiempo_movimiento,cantidad_scrap_fija,porcentaje_scrap,
     estado,requiere_fichaje)
    VALUES (@entrada,10000,N'ZZ16-RUTA',N'20',N'WorkCenter',N'ZZ16-CAP',
            N'ZZ16 OPERACION',0,12.5,0,0,0,0,N'NotStarted',0);
    INSERT nav.componentes_orden_entrada
    (orden_entrada_id,numero_linea_orden,numero_linea,estado_nav,articulo_codigo,
     descripcion,cantidad_por,cantidad_prevista,cantidad_pendiente,
     cantidad_consumida,metodo_descarga,cantidad_recogida,admite_sustitucion)
    VALUES (@entrada,10000,10000,N'Released',N'ZZ16-COMP',N'ZZ16 COMPONENTE',
            2,20,20,0,N'Manual',0,0);

    DECLARE @corr uniqueidentifier=NEWID(),@orden bigint,@resultado nvarchar(20);
    EXEC nav.promover_orden_entrada @corr,@entrada,N'ZZ16-LOTE',N'20',
         N'EBIR\ZZ16-SUPERVISOR',@orden OUTPUT,@resultado OUTPUT;
    IF @resultado<>N'CREADA' OR @orden IS NULL THROW 58003, 'No se creo la orden.', 1;
    IF NOT EXISTS(SELECT 1 FROM prod.ordenes WHERE orden_id=@orden AND lote=N'ZZ16-LOTE'
       AND cantidad_objetivo=10 AND tiempo_ejecucion_nav_min=12.5)
        THROW 58004, 'La orden creada no coincide con el contrato.', 1;
    IF (SELECT COUNT(*) FROM nav.componentes_orden WHERE orden_id=@orden)<>1
        THROW 58005, 'No se promovieron los componentes.', 1;

    DECLARE @orden_repetida bigint,@resultado_repetido nvarchar(20);
    EXEC nav.promover_orden_entrada @corr,@entrada,N'ZZ16-LOTE',N'20',
         N'EBIR\ZZ16-SUPERVISOR',@orden_repetida OUTPUT,@resultado_repetido OUTPUT;
    IF @orden_repetida<>@orden OR @resultado_repetido<>N'CREADA'
        THROW 58006, 'La repeticion idempotente no recupero el resultado.', 1;

    DECLARE @corr2 uniqueidentifier=NEWID();
    EXEC nav.promover_orden_entrada @corr2,@entrada,N'ZZ16-LOTE',N'20',
         N'EBIR\ZZ16-SUPERVISOR',@orden_repetida OUTPUT,@resultado_repetido OUTPUT;
    IF @resultado_repetido<>N'SIN_CAMBIOS' THROW 58007, 'No devolvio SIN_CAMBIOS.', 1;

    DECLARE @corr3 uniqueidentifier=NEWID();
    EXEC nav.promover_orden_entrada @corr3,@entrada,N'ZZ16-OTRO',N'20',
         N'EBIR\ZZ16-SUPERVISOR',@orden_repetida OUTPUT,@resultado_repetido OUTPUT;
    IF @resultado_repetido<>N'REVISION'
       OR (SELECT estado FROM prod.ordenes WHERE orden_id=@orden)<>N'REVISION'
        THROW 58008, 'El cambio no forzo REVISION.', 1;

    SELECT N'OK' AS resultado,@orden AS orden_sintetica;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
