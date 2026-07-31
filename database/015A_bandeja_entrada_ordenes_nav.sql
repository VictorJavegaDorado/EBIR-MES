/*
Paquete 015A - Bandeja de entrada idempotente para órdenes NAV.
Estado: preparado para revisión estática; no ejecutado.
Base exclusiva: EBIR_MES_TEST.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF OBJECT_ID(N'nav.empresas', N'U') IS NULL
 OR OBJECT_ID(N'nav.entornos', N'U') IS NULL
    THROW 51010, 'Faltan los catalogos NAV requeridos.', 1;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
    THROW 51011, 'Falta el rol mes_runtime.', 1;

IF OBJECT_ID(N'nav.ordenes_entrada', N'U') IS NOT NULL
 OR OBJECT_ID(N'nav.lineas_orden_entrada', N'U') IS NOT NULL
 OR OBJECT_ID(N'nav.rutas_orden_entrada', N'U') IS NOT NULL
 OR OBJECT_ID(N'nav.componentes_orden_entrada', N'U') IS NOT NULL
 OR OBJECT_ID(N'nav.sincronizaciones_orden', N'U') IS NOT NULL
 OR OBJECT_ID(N'nav.aplicar_snapshot_orden', N'P') IS NOT NULL
    THROW 51012, 'El paquete 015A ya existe total o parcialmente.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    CREATE TABLE nav.ordenes_entrada
    (
        orden_entrada_id bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_nav_ordenes_entrada PRIMARY KEY,
        empresa_nav_id bigint NOT NULL,
        numero_orden nvarchar(30) NOT NULL,
        estado_nav nvarchar(30) NOT NULL,
        producto_codigo nvarchar(50) NOT NULL,
        descripcion nvarchar(250) NOT NULL,
        ruta_codigo nvarchar(50) NULL,
        cantidad decimal(18,4) NOT NULL,
        ubicacion_codigo nvarchar(30) NULL,
        fecha_inicio date NULL,
        fecha_fin date NULL,
        fecha_vencimiento date NULL,
        snapshot_hash binary(32) NOT NULL,
        snapshot_json nvarchar(max) NOT NULL,
        primera_sincronizacion_utc datetime2(3) NOT NULL
            CONSTRAINT DF_nav_ordenes_entrada_primera DEFAULT (SYSUTCDATETIME()),
        ultima_sincronizacion_utc datetime2(3) NOT NULL
            CONSTRAINT DF_nav_ordenes_entrada_ultima DEFAULT (SYSUTCDATETIME()),
        version rowversion NOT NULL,
        CONSTRAINT FK_nav_ordenes_entrada_empresa FOREIGN KEY (empresa_nav_id)
            REFERENCES nav.empresas (empresa_nav_id),
        CONSTRAINT UQ_nav_ordenes_entrada_empresa_numero
            UNIQUE (empresa_nav_id, numero_orden),
        CONSTRAINT CK_nav_ordenes_entrada_numero
            CHECK (LEN(LTRIM(RTRIM(numero_orden))) > 0),
        CONSTRAINT CK_nav_ordenes_entrada_estado CHECK
            (estado_nav IN (N'Simulated', N'Planned', N'FirmPlanned',
                            N'Released', N'Finished')),
        CONSTRAINT CK_nav_ordenes_entrada_producto
            CHECK (LEN(LTRIM(RTRIM(producto_codigo))) > 0),
        CONSTRAINT CK_nav_ordenes_entrada_cantidad CHECK (cantidad > 0),
        CONSTRAINT CK_nav_ordenes_entrada_hash
            CHECK (DATALENGTH(snapshot_hash) = 32),
        CONSTRAINT CK_nav_ordenes_entrada_json CHECK (ISJSON(snapshot_json) = 1)
    );

    CREATE TABLE nav.lineas_orden_entrada
    (
        orden_entrada_id bigint NOT NULL
            CONSTRAINT PK_nav_lineas_orden_entrada PRIMARY KEY,
        estado_nav nvarchar(30) NOT NULL,
        producto_codigo nvarchar(50) NOT NULL,
        variante_codigo nvarchar(30) NULL,
        descripcion nvarchar(250) NOT NULL,
        ubicacion_codigo nvarchar(30) NULL,
        cantidad decimal(18,4) NOT NULL,
        cantidad_finalizada decimal(18,4) NOT NULL,
        cantidad_pendiente decimal(18,4) NOT NULL,
        porcentaje_scrap decimal(18,4) NOT NULL,
        fecha_vencimiento date NULL,
        fecha_inicio date NULL,
        fecha_fin date NULL,
        bom_produccion_codigo nvarchar(50) NULL,
        CONSTRAINT FK_nav_lineas_entrada_orden FOREIGN KEY (orden_entrada_id)
            REFERENCES nav.ordenes_entrada (orden_entrada_id),
        CONSTRAINT CK_nav_lineas_entrada_estado CHECK
            (estado_nav IN (N'Simulated', N'Planned', N'FirmPlanned',
                            N'Released', N'Finished')),
        CONSTRAINT CK_nav_lineas_entrada_cantidades CHECK
            (cantidad > 0 AND cantidad_finalizada >= 0
             AND cantidad_pendiente >= 0 AND porcentaje_scrap >= 0)
    );

    CREATE TABLE nav.rutas_orden_entrada
    (
        ruta_orden_entrada_id bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_nav_rutas_orden_entrada PRIMARY KEY,
        orden_entrada_id bigint NOT NULL,
        referencia_ruta int NOT NULL,
        ruta_codigo nvarchar(50) NULL,
        operacion_codigo nvarchar(30) NOT NULL,
        operacion_anterior_codigo nvarchar(30) NULL,
        operacion_siguiente_codigo nvarchar(30) NULL,
        tipo nvarchar(30) NOT NULL,
        capacidad_codigo nvarchar(30) NOT NULL,
        descripcion nvarchar(250) NOT NULL,
        inicio datetime2(3) NULL,
        fin datetime2(3) NULL,
        tiempo_preparacion decimal(18,8) NOT NULL,
        tiempo_ejecucion decimal(18,8) NOT NULL,
        tiempo_espera decimal(18,8) NOT NULL,
        tiempo_movimiento decimal(18,8) NOT NULL,
        cantidad_scrap_fija decimal(18,4) NOT NULL,
        codigo_enlace_ruta nvarchar(30) NULL,
        porcentaje_scrap decimal(18,4) NOT NULL,
        estado nvarchar(30) NOT NULL,
        ubicacion_codigo nvarchar(30) NULL,
        requiere_fichaje bit NOT NULL,
        CONSTRAINT FK_nav_rutas_entrada_orden FOREIGN KEY (orden_entrada_id)
            REFERENCES nav.ordenes_entrada (orden_entrada_id),
        CONSTRAINT UQ_nav_rutas_entrada_clave UNIQUE
            (orden_entrada_id, referencia_ruta, ruta_codigo, operacion_codigo),
        CONSTRAINT CK_nav_rutas_entrada_referencia CHECK (referencia_ruta > 0),
        CONSTRAINT CK_nav_rutas_entrada_tipo
            CHECK (tipo IN (N'WorkCenter', N'MachineCenter')),
        CONSTRAINT CK_nav_rutas_entrada_estado
            CHECK (estado IN (N'NotStarted', N'Planned', N'InProgress', N'Finished')),
        CONSTRAINT CK_nav_rutas_entrada_tiempos CHECK
            (tiempo_preparacion >= 0 AND tiempo_ejecucion >= 0
             AND tiempo_espera >= 0 AND tiempo_movimiento >= 0),
        CONSTRAINT CK_nav_rutas_entrada_scrap CHECK
            (cantidad_scrap_fija >= 0 AND porcentaje_scrap >= 0)
    );

    CREATE TABLE nav.componentes_orden_entrada
    (
        componente_orden_entrada_id bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_nav_componentes_orden_entrada PRIMARY KEY,
        orden_entrada_id bigint NOT NULL,
        numero_linea_orden int NOT NULL,
        numero_linea int NOT NULL,
        estado_nav nvarchar(30) NOT NULL,
        articulo_codigo nvarchar(50) NOT NULL,
        variante_codigo nvarchar(30) NULL,
        descripcion nvarchar(250) NOT NULL,
        cantidad_por decimal(18,8) NOT NULL,
        cantidad_prevista decimal(18,4) NOT NULL,
        cantidad_pendiente decimal(18,4) NOT NULL,
        cantidad_consumida decimal(18,4) NOT NULL,
        unidad_medida nvarchar(20) NULL,
        metodo_descarga nvarchar(30) NOT NULL,
        codigo_enlace_ruta nvarchar(30) NULL,
        operacion_codigo nvarchar(30) NULL,
        ubicacion_codigo nvarchar(30) NULL,
        ubicacion_interna_codigo nvarchar(30) NULL,
        cantidad_recogida decimal(18,4) NOT NULL,
        admite_sustitucion bit NOT NULL,
        CONSTRAINT FK_nav_componentes_entrada_orden FOREIGN KEY (orden_entrada_id)
            REFERENCES nav.ordenes_entrada (orden_entrada_id),
        CONSTRAINT UQ_nav_componentes_entrada_clave UNIQUE
            (orden_entrada_id, numero_linea_orden, numero_linea),
        CONSTRAINT CK_nav_componentes_entrada_lineas CHECK
            (numero_linea_orden > 0 AND numero_linea > 0),
        CONSTRAINT CK_nav_componentes_entrada_estado CHECK
            (estado_nav IN (N'Simulated', N'Planned', N'FirmPlanned',
                            N'Released', N'Finished')),
        CONSTRAINT CK_nav_componentes_entrada_articulo
            CHECK (LEN(LTRIM(RTRIM(articulo_codigo))) > 0),
        CONSTRAINT CK_nav_componentes_entrada_cantidades CHECK
            (cantidad_por >= 0 AND cantidad_prevista >= 0
             AND cantidad_pendiente >= 0 AND cantidad_consumida >= 0
             AND cantidad_recogida >= 0),
        CONSTRAINT CK_nav_componentes_entrada_metodo CHECK
            (metodo_descarga IN (N'Manual', N'Forward', N'Backward',
                                 N'PickAndForward', N'PickAndBackward'))
    );

    CREATE TABLE nav.sincronizaciones_orden
    (
        sincronizacion_id uniqueidentifier NOT NULL
            CONSTRAINT PK_nav_sincronizaciones_orden PRIMARY KEY,
        orden_entrada_id bigint NOT NULL,
        snapshot_hash binary(32) NOT NULL,
        resultado nvarchar(20) NOT NULL,
        cuenta_dominio nvarchar(256) NOT NULL
            CONSTRAINT DF_nav_sincronizaciones_cuenta DEFAULT (SUSER_SNAME()),
        completada_utc datetime2(3) NOT NULL
            CONSTRAINT DF_nav_sincronizaciones_completada DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_nav_sincronizaciones_orden FOREIGN KEY (orden_entrada_id)
            REFERENCES nav.ordenes_entrada (orden_entrada_id),
        CONSTRAINT CK_nav_sincronizaciones_hash
            CHECK (DATALENGTH(snapshot_hash) = 32),
        CONSTRAINT CK_nav_sincronizaciones_resultado
            CHECK (resultado IN (N'CREADA', N'ACTUALIZADA', N'SIN_CAMBIOS'))
    );

    CREATE INDEX IX_nav_ordenes_entrada_estado
        ON nav.ordenes_entrada (estado_nav, ultima_sincronizacion_utc);

    CREATE INDEX IX_nav_sincronizaciones_orden_fecha
        ON nav.sincronizaciones_orden (orden_entrada_id, completada_utc DESC);

    DECLARE @definicion nvarchar(max) = N'
CREATE PROCEDURE nav.aplicar_snapshot_orden
    @sincronizacion_id uniqueidentifier,
    @snapshot_json nvarchar(max),
    @snapshot_hash binary(32),
    @orden_entrada_id bigint OUTPUT,
    @resultado nvarchar(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @orden_entrada_id = NULL;
    SET @resultado = NULL;

    IF @sincronizacion_id IS NULL
        THROW 55500, ''La correlacion de sincronizacion es obligatoria.'', 1;

    IF @snapshot_hash IS NULL OR DATALENGTH(@snapshot_hash) <> 32
        THROW 55501, ''El hash del snapshot no es valido.'', 1;

    IF @snapshot_json IS NULL OR ISJSON(@snapshot_json) <> 1
        THROW 55502, ''El snapshot NAV no es JSON valido.'', 1;

    DECLARE
        @entorno_codigo nvarchar(30) = UPPER(NULLIF(LTRIM(RTRIM(JSON_VALUE(@snapshot_json, ''$.environmentCode''))), N'''')),
        @empresa_codigo nvarchar(50) = UPPER(NULLIF(LTRIM(RTRIM(JSON_VALUE(@snapshot_json, ''$.companyCode''))), N'''')),
        @numero_orden nvarchar(30),
        @estado_nav nvarchar(30),
        @producto_codigo nvarchar(50),
        @descripcion nvarchar(250),
        @ruta_codigo nvarchar(50),
        @cantidad decimal(18,4),
        @ubicacion_codigo nvarchar(30),
        @fecha_inicio date,
        @fecha_fin date,
        @fecha_vencimiento date;

    SELECT
        @numero_orden = UPPER(NULLIF(LTRIM(RTRIM(orderNumber)), N'''')),
        @estado_nav = status,
        @producto_codigo = NULLIF(LTRIM(RTRIM(productNumber)), N''''),
        @descripcion = ISNULL(description, N''''),
        @ruta_codigo = NULLIF(LTRIM(RTRIM(routingNumber)), N''''),
        @cantidad = quantity,
        @ubicacion_codigo = NULLIF(LTRIM(RTRIM(locationCode)), N''''),
        @fecha_inicio = startingDate,
        @fecha_fin = endingDate,
        @fecha_vencimiento = dueDate
    FROM OPENJSON(@snapshot_json, ''$.order'')
    WITH
    (
        orderNumber nvarchar(30) ''$.orderNumber'',
        status nvarchar(30) ''$.status'',
        description nvarchar(250) ''$.description'',
        productNumber nvarchar(50) ''$.productNumber'',
        routingNumber nvarchar(50) ''$.routingNumber'',
        quantity decimal(18,4) ''$.quantity'',
        locationCode nvarchar(30) ''$.locationCode'',
        startingDate date ''$.startingDate'',
        endingDate date ''$.endingDate'',
        dueDate date ''$.dueDate''
    );

    IF @entorno_codigo IS NULL OR @empresa_codigo IS NULL
       OR @numero_orden IS NULL OR @estado_nav IS NULL
       OR @producto_codigo IS NULL OR @cantidad IS NULL OR @cantidad <= 0
        THROW 55502, ''El snapshot NAV no contiene una cabecera valida.'', 1;

    DECLARE @linea TABLE
    (
        orderNumber nvarchar(30),
        status nvarchar(30),
        productNumber nvarchar(50),
        variantCode nvarchar(30),
        description nvarchar(250),
        locationCode nvarchar(30),
        quantity decimal(18,4),
        finishedQuantity decimal(18,4),
        remainingQuantity decimal(18,4),
        scrapPercent decimal(18,4),
        dueDate date,
        startingDate date,
        endingDate date,
        productionBomNumber nvarchar(50)
    );

    INSERT @linea
    SELECT *
    FROM OPENJSON(@snapshot_json, ''$.line'')
    WITH
    (
        orderNumber nvarchar(30) ''$.orderNumber'',
        status nvarchar(30) ''$.status'',
        productNumber nvarchar(50) ''$.productNumber'',
        variantCode nvarchar(30) ''$.variantCode'',
        description nvarchar(250) ''$.description'',
        locationCode nvarchar(30) ''$.locationCode'',
        quantity decimal(18,4) ''$.quantity'',
        finishedQuantity decimal(18,4) ''$.finishedQuantity'',
        remainingQuantity decimal(18,4) ''$.remainingQuantity'',
        scrapPercent decimal(18,4) ''$.scrapPercent'',
        dueDate date ''$.dueDate'',
        startingDate date ''$.startingDate'',
        endingDate date ''$.endingDate'',
        productionBomNumber nvarchar(50) ''$.productionBomNumber''
    );

    IF (SELECT COUNT(*) FROM @linea) <> 1
        THROW 55507, ''El piloto requiere una linea por orden NAV.'', 1;

    IF EXISTS
    (
        SELECT 1 FROM @linea
        WHERE UPPER(LTRIM(RTRIM(orderNumber))) <> @numero_orden
           OR status <> @estado_nav
           OR productNumber <> @producto_codigo
           OR quantity IS NULL OR quantity <= 0
           OR finishedQuantity < 0 OR remainingQuantity < 0 OR scrapPercent < 0
    )
        THROW 55506, ''La linea no coincide con la cabecera NAV.'', 1;

    DECLARE @rutas TABLE
    (
        orderNumber nvarchar(30),
        routingReferenceNumber int,
        routingNumber nvarchar(50),
        operationNumber nvarchar(30),
        previousOperationNumber nvarchar(30),
        nextOperationNumber nvarchar(30),
        type nvarchar(30),
        capacityNumber nvarchar(30),
        description nvarchar(250),
        startingAt datetime2(3),
        endingAt datetime2(3),
        setupTime decimal(18,8),
        runTime decimal(18,8),
        waitTime decimal(18,8),
        moveTime decimal(18,8),
        fixedScrapQuantity decimal(18,4),
        routingLinkCode nvarchar(30),
        scrapFactorPercent decimal(18,4),
        status nvarchar(30),
        locationCode nvarchar(30),
        isSigning bit
    );

    INSERT @rutas
    SELECT *
    FROM OPENJSON(@snapshot_json, ''$.routing'')
    WITH
    (
        orderNumber nvarchar(30) ''$.orderNumber'',
        routingReferenceNumber int ''$.routingReferenceNumber'',
        routingNumber nvarchar(50) ''$.routingNumber'',
        operationNumber nvarchar(30) ''$.operationNumber'',
        previousOperationNumber nvarchar(30) ''$.previousOperationNumber'',
        nextOperationNumber nvarchar(30) ''$.nextOperationNumber'',
        type nvarchar(30) ''$.type'',
        capacityNumber nvarchar(30) ''$.capacityNumber'',
        description nvarchar(250) ''$.description'',
        startingAt datetime2(3) ''$.startingAt'',
        endingAt datetime2(3) ''$.endingAt'',
        setupTime decimal(18,8) ''$.setupTime'',
        runTime decimal(18,8) ''$.runTime'',
        waitTime decimal(18,8) ''$.waitTime'',
        moveTime decimal(18,8) ''$.moveTime'',
        fixedScrapQuantity decimal(18,4) ''$.fixedScrapQuantity'',
        routingLinkCode nvarchar(30) ''$.routingLinkCode'',
        scrapFactorPercent decimal(18,4) ''$.scrapFactorPercent'',
        status nvarchar(30) ''$.status'',
        locationCode nvarchar(30) ''$.locationCode'',
        isSigning bit ''$.isSigning''
    );

    IF EXISTS
    (
        SELECT 1 FROM @rutas
        WHERE UPPER(LTRIM(RTRIM(orderNumber))) <> @numero_orden
           OR routingReferenceNumber IS NULL OR routingReferenceNumber <= 0
           OR NULLIF(LTRIM(RTRIM(operationNumber)), N'''') IS NULL
           OR NULLIF(LTRIM(RTRIM(capacityNumber)), N'''') IS NULL
           OR type NOT IN (N''WorkCenter'', N''MachineCenter'')
           OR status NOT IN (N''NotStarted'', N''Planned'', N''InProgress'', N''Finished'')
           OR setupTime < 0 OR runTime < 0 OR waitTime < 0 OR moveTime < 0
           OR fixedScrapQuantity < 0 OR scrapFactorPercent < 0
    )
        THROW 55506, ''La ruta NAV contiene datos incoherentes.'', 1;

    IF EXISTS
    (
        SELECT 1 FROM @rutas
        GROUP BY routingReferenceNumber, routingNumber, operationNumber
        HAVING COUNT(*) > 1
    )
        THROW 55506, ''La ruta NAV contiene operaciones duplicadas.'', 1;

    DECLARE @componentes TABLE
    (
        orderNumber nvarchar(30),
        productionOrderLineNumber int,
        lineNumber int,
        status nvarchar(30),
        itemNumber nvarchar(50),
        variantCode nvarchar(30),
        description nvarchar(250),
        quantityPer decimal(18,8),
        expectedQuantity decimal(18,4),
        remainingQuantity decimal(18,4),
        actualConsumptionQuantity decimal(18,4),
        unitOfMeasureCode nvarchar(20),
        flushingMethod nvarchar(30),
        routingLinkCode nvarchar(30),
        operationCode nvarchar(30),
        locationCode nvarchar(30),
        binCode nvarchar(30),
        quantityPicked decimal(18,4),
        substitutionAvailable bit
    );

    INSERT @componentes
    SELECT *
    FROM OPENJSON(@snapshot_json, ''$.components'')
    WITH
    (
        orderNumber nvarchar(30) ''$.orderNumber'',
        productionOrderLineNumber int ''$.productionOrderLineNumber'',
        lineNumber int ''$.lineNumber'',
        status nvarchar(30) ''$.status'',
        itemNumber nvarchar(50) ''$.itemNumber'',
        variantCode nvarchar(30) ''$.variantCode'',
        description nvarchar(250) ''$.description'',
        quantityPer decimal(18,8) ''$.quantityPer'',
        expectedQuantity decimal(18,4) ''$.expectedQuantity'',
        remainingQuantity decimal(18,4) ''$.remainingQuantity'',
        actualConsumptionQuantity decimal(18,4) ''$.actualConsumptionQuantity'',
        unitOfMeasureCode nvarchar(20) ''$.unitOfMeasureCode'',
        flushingMethod nvarchar(30) ''$.flushingMethod'',
        routingLinkCode nvarchar(30) ''$.routingLinkCode'',
        operationCode nvarchar(30) ''$.operationCode'',
        locationCode nvarchar(30) ''$.locationCode'',
        binCode nvarchar(30) ''$.binCode'',
        quantityPicked decimal(18,4) ''$.quantityPicked'',
        substitutionAvailable bit ''$.substitutionAvailable''
    );

    IF EXISTS
    (
        SELECT 1 FROM @componentes
        WHERE UPPER(LTRIM(RTRIM(orderNumber))) <> @numero_orden
           OR status <> @estado_nav
           OR productionOrderLineNumber IS NULL OR productionOrderLineNumber <= 0
           OR lineNumber IS NULL OR lineNumber <= 0
           OR NULLIF(LTRIM(RTRIM(itemNumber)), N'''') IS NULL
           OR quantityPer < 0 OR expectedQuantity < 0 OR remainingQuantity < 0
           OR actualConsumptionQuantity < 0 OR quantityPicked < 0
           OR flushingMethod NOT IN
              (N''Manual'', N''Forward'', N''Backward'',
               N''PickAndForward'', N''PickAndBackward'')
    )
        THROW 55506, ''Los componentes NAV contienen datos incoherentes.'', 1;

    IF (SELECT COUNT(DISTINCT productionOrderLineNumber) FROM @componentes) > 1
        THROW 55507, ''Los componentes pertenecen a mas de una linea NAV.'', 1;

    IF EXISTS
    (
        SELECT 1 FROM @componentes
        GROUP BY productionOrderLineNumber, lineNumber
        HAVING COUNT(*) > 1
    )
        THROW 55506, ''Los componentes NAV contienen lineas duplicadas.'', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE
            @resultado_bloqueo int,
            @recurso_bloqueo nvarchar(255),
            @empresa_nav_id bigint,
            @hash_existente binary(32),
            @resultado_existente nvarchar(20);

        SET @recurso_bloqueo = CONCAT(
            N''MES:NAVSYNC:CORR:'', CONVERT(nvarchar(36), @sincronizacion_id));
        EXEC @resultado_bloqueo = sys.sp_getapplock
            @Resource = @recurso_bloqueo,
            @LockMode = N''Exclusive'',
            @LockOwner = N''Transaction'',
            @LockTimeout = 10000,
            @DbPrincipal = N''public'';
        IF @resultado_bloqueo < 0
            THROW 55504, ''No se pudo bloquear la correlacion de sincronizacion.'', 1;

        SELECT
            @orden_entrada_id = s.orden_entrada_id,
            @hash_existente = s.snapshot_hash,
            @resultado_existente = s.resultado
        FROM nav.sincronizaciones_orden s WITH (UPDLOCK, HOLDLOCK)
        WHERE s.sincronizacion_id = @sincronizacion_id;

        IF @orden_entrada_id IS NOT NULL
        BEGIN
            IF @hash_existente <> @snapshot_hash
                THROW 55503, ''La correlacion ya se utilizo con otro snapshot.'', 1;

            SET @resultado = @resultado_existente;
            COMMIT TRANSACTION;
            RETURN;
        END;

        SELECT @empresa_nav_id = e.empresa_nav_id
        FROM nav.empresas e WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN nav.entornos n ON n.entorno_nav_id = e.entorno_nav_id
        WHERE n.codigo = @entorno_codigo
          AND e.codigo = @empresa_codigo
          AND n.activo = 1
          AND e.activo = 1;

        IF @empresa_nav_id IS NULL
            THROW 55505, ''El entorno o la empresa NAV no estan activos en MES.'', 1;

        SET @recurso_bloqueo = CONCAT(
            N''MES:NAVSYNC:ORDER:'', @empresa_nav_id, N'':'', @numero_orden);
        EXEC @resultado_bloqueo = sys.sp_getapplock
            @Resource = @recurso_bloqueo,
            @LockMode = N''Exclusive'',
            @LockOwner = N''Transaction'',
            @LockTimeout = 10000,
            @DbPrincipal = N''public'';
        IF @resultado_bloqueo < 0
            THROW 55504, ''No se pudo bloquear la orden de sincronizacion.'', 1;

        SELECT
            @orden_entrada_id = o.orden_entrada_id,
            @hash_existente = o.snapshot_hash
        FROM nav.ordenes_entrada o WITH (UPDLOCK, HOLDLOCK)
        WHERE o.empresa_nav_id = @empresa_nav_id
          AND o.numero_orden = @numero_orden;

        IF @orden_entrada_id IS NOT NULL AND @hash_existente = @snapshot_hash
        BEGIN
            UPDATE nav.ordenes_entrada
            SET ultima_sincronizacion_utc = SYSUTCDATETIME()
            WHERE orden_entrada_id = @orden_entrada_id;

            SET @resultado = N''SIN_CAMBIOS'';
        END
        ELSE
        BEGIN
            IF @orden_entrada_id IS NULL
            BEGIN
                INSERT nav.ordenes_entrada
                (
                    empresa_nav_id, numero_orden, estado_nav, producto_codigo,
                    descripcion, ruta_codigo, cantidad, ubicacion_codigo,
                    fecha_inicio, fecha_fin, fecha_vencimiento,
                    snapshot_hash, snapshot_json
                )
                VALUES
                (
                    @empresa_nav_id, @numero_orden, @estado_nav, @producto_codigo,
                    @descripcion, @ruta_codigo, @cantidad, @ubicacion_codigo,
                    @fecha_inicio, @fecha_fin, @fecha_vencimiento,
                    @snapshot_hash, @snapshot_json
                );
                SET @orden_entrada_id = SCOPE_IDENTITY();
                SET @resultado = N''CREADA'';
            END
            ELSE
            BEGIN
                UPDATE nav.ordenes_entrada
                SET estado_nav = @estado_nav,
                    producto_codigo = @producto_codigo,
                    descripcion = @descripcion,
                    ruta_codigo = @ruta_codigo,
                    cantidad = @cantidad,
                    ubicacion_codigo = @ubicacion_codigo,
                    fecha_inicio = @fecha_inicio,
                    fecha_fin = @fecha_fin,
                    fecha_vencimiento = @fecha_vencimiento,
                    snapshot_hash = @snapshot_hash,
                    snapshot_json = @snapshot_json,
                    ultima_sincronizacion_utc = SYSUTCDATETIME()
                WHERE orden_entrada_id = @orden_entrada_id;

                DELETE nav.componentes_orden_entrada
                WHERE orden_entrada_id = @orden_entrada_id;
                DELETE nav.rutas_orden_entrada
                WHERE orden_entrada_id = @orden_entrada_id;
                DELETE nav.lineas_orden_entrada
                WHERE orden_entrada_id = @orden_entrada_id;
                SET @resultado = N''ACTUALIZADA'';
            END;

            INSERT nav.lineas_orden_entrada
            (
                orden_entrada_id, estado_nav, producto_codigo, variante_codigo,
                descripcion, ubicacion_codigo, cantidad, cantidad_finalizada,
                cantidad_pendiente, porcentaje_scrap, fecha_vencimiento,
                fecha_inicio, fecha_fin, bom_produccion_codigo
            )
            SELECT
                @orden_entrada_id, status, productNumber,
                NULLIF(variantCode, N''''), ISNULL(description, N''''),
                NULLIF(locationCode, N''''), quantity, finishedQuantity,
                remainingQuantity, scrapPercent, dueDate, startingDate,
                endingDate, NULLIF(productionBomNumber, N'''')
            FROM @linea;

            INSERT nav.rutas_orden_entrada
            (
                orden_entrada_id, referencia_ruta, ruta_codigo,
                operacion_codigo, operacion_anterior_codigo,
                operacion_siguiente_codigo, tipo, capacidad_codigo,
                descripcion, inicio, fin, tiempo_preparacion,
                tiempo_ejecucion, tiempo_espera, tiempo_movimiento,
                cantidad_scrap_fija, codigo_enlace_ruta, porcentaje_scrap,
                estado, ubicacion_codigo, requiere_fichaje
            )
            SELECT
                @orden_entrada_id, routingReferenceNumber,
                NULLIF(routingNumber, N''''), operationNumber,
                NULLIF(previousOperationNumber, N''''),
                NULLIF(nextOperationNumber, N''''), type, capacityNumber,
                ISNULL(description, N''''), startingAt, endingAt,
                setupTime, runTime, waitTime, moveTime,
                fixedScrapQuantity, NULLIF(routingLinkCode, N''''),
                scrapFactorPercent, status, NULLIF(locationCode, N''''),
                isSigning
            FROM @rutas;

            INSERT nav.componentes_orden_entrada
            (
                orden_entrada_id, numero_linea_orden, numero_linea,
                estado_nav, articulo_codigo, variante_codigo, descripcion,
                cantidad_por, cantidad_prevista, cantidad_pendiente,
                cantidad_consumida, unidad_medida, metodo_descarga,
                codigo_enlace_ruta, operacion_codigo, ubicacion_codigo,
                ubicacion_interna_codigo, cantidad_recogida, admite_sustitucion
            )
            SELECT
                @orden_entrada_id, productionOrderLineNumber, lineNumber,
                status, itemNumber, NULLIF(variantCode, N''''),
                ISNULL(description, N''''), quantityPer, expectedQuantity,
                remainingQuantity, actualConsumptionQuantity,
                NULLIF(unitOfMeasureCode, N''''), flushingMethod,
                NULLIF(routingLinkCode, N''''), NULLIF(operationCode, N''''),
                NULLIF(locationCode, N''''), NULLIF(binCode, N''''),
                quantityPicked, substitutionAvailable
            FROM @componentes;
        END;

        INSERT nav.sincronizaciones_orden
        (
            sincronizacion_id, orden_entrada_id, snapshot_hash, resultado
        )
        VALUES
        (
            @sincronizacion_id, @orden_entrada_id, @snapshot_hash, @resultado
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        SET @orden_entrada_id = NULL;
        SET @resultado = NULL;
        THROW;
    END CATCH;
END;';

    EXEC sys.sp_executesql @definicion;
    GRANT EXECUTE ON OBJECT::nav.aplicar_snapshot_orden TO mes_runtime;

    IF OBJECT_ID(N'nav.ordenes_entrada', N'U') IS NULL
     OR OBJECT_ID(N'nav.lineas_orden_entrada', N'U') IS NULL
     OR OBJECT_ID(N'nav.rutas_orden_entrada', N'U') IS NULL
     OR OBJECT_ID(N'nav.componentes_orden_entrada', N'U') IS NULL
     OR OBJECT_ID(N'nav.sincronizaciones_orden', N'U') IS NULL
     OR OBJECT_ID(N'nav.aplicar_snapshot_orden', N'P') IS NULL
        THROW 51013, 'No se crearon todos los objetos del paquete 015A.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.database_permissions
        WHERE class = 1
          AND major_id = OBJECT_ID(N'nav.aplicar_snapshot_orden')
          AND minor_id = 0
          AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
          AND permission_name = N'EXECUTE'
          AND state IN (N'G', N'W')
    )
        THROW 51014, 'mes_runtime no recibio el contrato de sincronizacion.', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
