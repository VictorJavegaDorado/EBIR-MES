SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 58100, 'Prueba permitida unicamente en EBIR_MES_TEST.', 1;
IF OBJECT_ID(N'nav.registrar_lote_snapshot_orden', N'P') IS NULL
 OR OBJECT_ID(N'nav.promover_orden_entrada_con_lote_nav', N'P') IS NULL
    THROW 58101, 'El paquete 017 no esta instalado.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @empresa_nav_id bigint =
    (
        SELECT TOP (1) empresa_nav_id FROM nav.empresas ORDER BY empresa_nav_id
    );
    IF @empresa_nav_id IS NULL THROW 58102, 'No existe empresa NAV de prueba.', 1;

    DECLARE @snapshot nvarchar(max) =
        N'{"environmentCode":"EBIRTEST","companyCode":"EBIR","lotNumber":"ZZ17LOTE","order":{"orderNumber":"ZZ17-ORDER","status":"Released","description":"ZZ17 PRODUCTO","productNumber":"ZZ17-PROD","routingNumber":"ZZ17-RUTA","quantity":10,"locationCode":"ZZ","startingDate":null,"endingDate":null,"dueDate":null},"line":{"orderNumber":"ZZ17-ORDER","status":"Released","productNumber":"ZZ17-PROD","variantCode":"","description":"ZZ17 PRODUCTO","locationCode":"ZZ","quantity":10,"finishedQuantity":0,"remainingQuantity":10,"scrapPercent":0,"dueDate":null,"startingDate":null,"endingDate":null,"productionBomNumber":"ZZ17-BOM"},"routing":[],"components":[]}';
    DECLARE @hash binary(32) =
        HASHBYTES('SHA2_256', CONVERT(varbinary(max), @snapshot));

    INSERT nav.ordenes_entrada
    (empresa_nav_id,numero_orden,estado_nav,producto_codigo,descripcion,ruta_codigo,
     cantidad,ubicacion_codigo,snapshot_hash,snapshot_json)
    VALUES
    (@empresa_nav_id,N'ZZ17-ORDER',N'Released',N'ZZ17-PROD',N'ZZ17 PRODUCTO',
     N'ZZ17-RUTA',10,N'ZZ',@hash,@snapshot);
    DECLARE @entrada bigint = SCOPE_IDENTITY();

    EXEC nav.registrar_lote_snapshot_orden @entrada,@hash,N'ZZ17LOTE';
    IF (SELECT lote FROM nav.ordenes_entrada WHERE orden_entrada_id=@entrada)<>N'ZZ17LOTE'
        THROW 58103, 'No se persistio el lote NAV.', 1;

    INSERT nav.lineas_orden_entrada
    (orden_entrada_id,estado_nav,producto_codigo,descripcion,cantidad,
     cantidad_finalizada,cantidad_pendiente,porcentaje_scrap)
    VALUES (@entrada,N'Released',N'ZZ17-PROD',N'ZZ17 PRODUCTO',10,0,10,0);
    INSERT nav.rutas_orden_entrada
    (orden_entrada_id,referencia_ruta,ruta_codigo,operacion_codigo,tipo,
     capacidad_codigo,descripcion,tiempo_preparacion,tiempo_ejecucion,
     tiempo_espera,tiempo_movimiento,cantidad_scrap_fija,porcentaje_scrap,
     estado,requiere_fichaje)
    VALUES (@entrada,10000,N'ZZ17-RUTA',N'20',N'WorkCenter',N'ZZ17-CAP',
            N'ZZ17 OPERACION',0,12.5,0,0,0,0,N'NotStarted',0);

    DECLARE @corr uniqueidentifier=NEWID(),@orden bigint,@resultado nvarchar(20);
    EXEC nav.promover_orden_entrada_con_lote_nav
        @corr,@entrada,N'20',@orden OUTPUT,@resultado OUTPUT;
    IF @resultado<>N'CREADA' OR @orden IS NULL
        THROW 58104, 'No se creo la orden con lote NAV.', 1;
    IF NOT EXISTS
    (
        SELECT 1 FROM prod.ordenes
        WHERE orden_id=@orden AND lote=N'ZZ17LOTE'
          AND cantidad_objetivo=10 AND tiempo_ejecucion_nav_min=12.5
    )
        THROW 58105, 'La orden creada no coincide con el contrato 017.', 1;
    IF NOT EXISTS
    (
        SELECT 1 FROM nav.promociones_orden
        WHERE orden_id=@orden AND lote=N'ZZ17LOTE'
          AND lote_proporcionado_por=N'NAV:WS_CPP_OPLanzadas.Cod_Lote_Salida'
    )
        THROW 58106, 'No se audito el origen NAV del lote.', 1;

    DECLARE @orden_repetida bigint,@resultado_repetido nvarchar(20);
    EXEC nav.promover_orden_entrada_con_lote_nav
        @corr,@entrada,N'20',@orden_repetida OUTPUT,@resultado_repetido OUTPUT;
    IF @orden_repetida<>@orden OR @resultado_repetido<>N'CREADA'
        THROW 58107, 'La repeticion idempotente no recupero el resultado.', 1;

    SELECT N'OK' AS resultado,@orden AS orden_sintetica;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
