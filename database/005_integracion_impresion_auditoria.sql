SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

BEGIN TRANSACTION;

CREATE TABLE nav.operaciones
(
    operacion_nav_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_nav_operaciones PRIMARY KEY,
    operacion_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_nav_operaciones_uid DEFAULT (NEWSEQUENTIALID()),
    clave_idempotencia nvarchar(150) NOT NULL,
    tipo nvarchar(30) NOT NULL,
    orden_id bigint NOT NULL,
    palet_id bigint NULL,
    scrap_id bigint NULL,
    revision_scrap_id bigint NULL,
    estado nvarchar(30) NOT NULL CONSTRAINT DF_nav_operaciones_estado DEFAULT (N'PENDIENTE'),
    payload nvarchar(max) NOT NULL,
    respuesta nvarchar(max) NULL,
    identificador_externo nvarchar(100) NULL,
    numero_intentos int NOT NULL CONSTRAINT DF_nav_operaciones_intentos DEFAULT (0),
    proximo_intento_utc datetime2(3) NULL,
    creada_utc datetime2(3) NOT NULL CONSTRAINT DF_nav_operaciones_creada DEFAULT (SYSUTCDATETIME()),
    procesada_utc datetime2(3) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_nav_operaciones_orden FOREIGN KEY (orden_id)
        REFERENCES prod.ordenes (orden_id),
    CONSTRAINT FK_nav_operaciones_palet_orden FOREIGN KEY (palet_id, orden_id)
        REFERENCES prod.palets (palet_id, orden_id),
    CONSTRAINT FK_nav_operaciones_scrap_orden FOREIGN KEY (scrap_id, orden_id)
        REFERENCES [log].scrap (scrap_id, orden_id),
    CONSTRAINT FK_nav_operaciones_revision_scrap_orden
        FOREIGN KEY (revision_scrap_id, scrap_id, orden_id)
        REFERENCES [log].revisiones_scrap (revision_scrap_id, scrap_id, orden_id),
    CONSTRAINT UQ_nav_operaciones_uid UNIQUE (operacion_uid),
    CONSTRAINT UQ_nav_operaciones_idempotencia UNIQUE (clave_idempotencia),
    CONSTRAINT CK_nav_operaciones_tipo
        CHECK (tipo IN (N'SALIDA_PALET', N'CONSUMO_SCRAP', N'AJUSTE_CONSUMO_SCRAP',
                        N'ANULACION_CONSUMO', N'CIERRE_FL', N'CONSULTA_ESTADO')),
    CONSTRAINT CK_nav_operaciones_estado
        CHECK (estado IN (N'PENDIENTE', N'PROCESANDO', N'CONFIRMADA', N'ERROR_REINTENTABLE',
                          N'RESULTADO_DESCONOCIDO', N'ERROR_DEFINITIVO', N'REVISION', N'ANULADA')),
    CONSTRAINT CK_nav_operaciones_payload CHECK (ISJSON(payload) = 1),
    CONSTRAINT CK_nav_operaciones_intentos CHECK (numero_intentos >= 0),
    CONSTRAINT CK_nav_operaciones_entidad
        CHECK ((tipo = N'SALIDA_PALET' AND palet_id IS NOT NULL
                    AND scrap_id IS NULL AND revision_scrap_id IS NULL) OR
               (tipo = N'CONSUMO_SCRAP' AND palet_id IS NULL
                    AND scrap_id IS NOT NULL AND revision_scrap_id IS NULL) OR
               (tipo IN (N'AJUSTE_CONSUMO_SCRAP', N'ANULACION_CONSUMO')
                    AND palet_id IS NULL AND scrap_id IS NOT NULL AND revision_scrap_id IS NOT NULL) OR
               (tipo IN (N'CIERRE_FL', N'CONSULTA_ESTADO')
                    AND palet_id IS NULL AND scrap_id IS NULL AND revision_scrap_id IS NULL))
);

CREATE TABLE nav.intentos_operacion
(
    intento_operacion_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_nav_intentos_operacion PRIMARY KEY,
    operacion_nav_id bigint NOT NULL,
    numero_intento smallint NOT NULL,
    inicio_utc datetime2(3) NOT NULL,
    fin_utc datetime2(3) NULL,
    resultado nvarchar(30) NOT NULL,
    codigo_http int NULL,
    error_normalizado nvarchar(1000) NULL,
    respuesta nvarchar(max) NULL,
    CONSTRAINT FK_nav_intentos_operacion FOREIGN KEY (operacion_nav_id)
        REFERENCES nav.operaciones (operacion_nav_id),
    CONSTRAINT UQ_nav_intentos_numero UNIQUE (operacion_nav_id, numero_intento),
    CONSTRAINT CK_nav_intentos_numero CHECK (numero_intento > 0),
    CONSTRAINT CK_nav_intentos_resultado
        CHECK (resultado IN (N'CONFIRMADA', N'ERROR_REINTENTABLE', N'RESULTADO_DESCONOCIDO',
                             N'ERROR_DEFINITIVO', N'ANULADA')),
    CONSTRAINT CK_nav_intentos_http CHECK (codigo_http IS NULL OR codigo_http BETWEEN 100 AND 599),
    CONSTRAINT CK_nav_intentos_fechas CHECK (fin_utc IS NULL OR fin_utc >= inicio_utc)
);

CREATE TABLE imp.etiquetas
(
    etiqueta_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_imp_etiquetas PRIMARY KEY,
    etiqueta_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_imp_etiquetas_uid DEFAULT (NEWSEQUENTIALID()),
    tipo nvarchar(30) NOT NULL,
    orden_id bigint NOT NULL,
    palet_id bigint NULL,
    codigo_visible nvarchar(150) NOT NULL,
    plantilla_codigo nvarchar(50) NOT NULL,
    plantilla_version int NOT NULL,
    datos_etiqueta nvarchar(max) NOT NULL,
    estado nvarchar(20) NOT NULL CONSTRAINT DF_imp_etiquetas_estado DEFAULT (N'PENDIENTE_NAV'),
    numero_copias smallint NOT NULL CONSTRAINT DF_imp_etiquetas_copias DEFAULT (1),
    creada_utc datetime2(3) NOT NULL CONSTRAINT DF_imp_etiquetas_creada DEFAULT (SYSUTCDATETIME()),
    habilitada_utc datetime2(3) NULL,
    impresa_utc datetime2(3) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_imp_etiquetas_orden FOREIGN KEY (orden_id)
        REFERENCES prod.ordenes (orden_id),
    CONSTRAINT FK_imp_etiquetas_palet_orden FOREIGN KEY (palet_id, orden_id)
        REFERENCES prod.palets (palet_id, orden_id),
    CONSTRAINT UQ_imp_etiquetas_uid UNIQUE (etiqueta_uid),
    CONSTRAINT UQ_imp_etiquetas_codigo UNIQUE (codigo_visible),
    CONSTRAINT CK_imp_etiquetas_tipo CHECK (tipo IN (N'PALET', N'SALIDA_FABRICA')),
    CONSTRAINT CK_imp_etiquetas_estado
        CHECK (estado IN (N'PENDIENTE_NAV', N'LISTA', N'IMPRESA', N'ERROR', N'ANULADA')),
    CONSTRAINT CK_imp_etiquetas_copias CHECK (numero_copias > 0),
    CONSTRAINT CK_imp_etiquetas_json CHECK (ISJSON(datos_etiqueta) = 1),
    CONSTRAINT CK_imp_etiquetas_entidad
        CHECK ((tipo = N'PALET' AND palet_id IS NOT NULL) OR
               (tipo = N'SALIDA_FABRICA' AND palet_id IS NULL)),
    CONSTRAINT CK_imp_etiquetas_fechas
        CHECK (
            estado = N'PENDIENTE_NAV'
            OR (estado IN (N'LISTA', N'ERROR', N'ANULADA') AND habilitada_utc IS NOT NULL)
            OR (estado = N'IMPRESA' AND habilitada_utc IS NOT NULL AND impresa_utc IS NOT NULL)
        )
);

CREATE TABLE imp.trabajos_impresion
(
    trabajo_impresion_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_imp_trabajos_impresion PRIMARY KEY,
    trabajo_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_imp_trabajos_uid DEFAULT (NEWSEQUENTIALID()),
    etiqueta_id bigint NOT NULL,
    impresora_solicitada_id bigint NOT NULL,
    impresora_utilizada_id bigint NULL,
    clave_idempotencia nvarchar(150) NOT NULL,
    es_reimpresion bit NOT NULL CONSTRAINT DF_imp_trabajos_reimpresion DEFAULT (0),
    solicitado_por_empleado_id bigint NULL,
    motivo nvarchar(500) NULL,
    estado nvarchar(30) NOT NULL CONSTRAINT DF_imp_trabajos_estado DEFAULT (N'PENDIENTE'),
    creado_utc datetime2(3) NOT NULL CONSTRAINT DF_imp_trabajos_creado DEFAULT (SYSUTCDATETIME()),
    procesado_utc datetime2(3) NULL,
    version rowversion NOT NULL,
    CONSTRAINT FK_imp_trabajos_etiqueta FOREIGN KEY (etiqueta_id)
        REFERENCES imp.etiquetas (etiqueta_id),
    CONSTRAINT FK_imp_trabajos_impresora_solicitada FOREIGN KEY (impresora_solicitada_id)
        REFERENCES cfg.impresoras (impresora_id),
    CONSTRAINT FK_imp_trabajos_impresora_utilizada FOREIGN KEY (impresora_utilizada_id)
        REFERENCES cfg.impresoras (impresora_id),
    CONSTRAINT FK_imp_trabajos_solicitante FOREIGN KEY (solicitado_por_empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT UQ_imp_trabajos_uid UNIQUE (trabajo_uid),
    CONSTRAINT UQ_imp_trabajos_idempotencia UNIQUE (clave_idempotencia),
    CONSTRAINT CK_imp_trabajos_estado
        CHECK (estado IN (N'PENDIENTE', N'PROCESANDO', N'COMPLETADO', N'ERROR',
                          N'RESULTADO_DESCONOCIDO', N'CANCELADO')),
    CONSTRAINT CK_imp_trabajos_reimpresion
        CHECK (es_reimpresion = 0 OR (solicitado_por_empleado_id IS NOT NULL AND motivo IS NOT NULL)),
    CONSTRAINT CK_imp_trabajos_fechas
        CHECK ((estado IN (N'PENDIENTE', N'PROCESANDO') AND procesado_utc IS NULL) OR
               (estado IN (N'COMPLETADO', N'ERROR', N'RESULTADO_DESCONOCIDO', N'CANCELADO')
                    AND procesado_utc IS NOT NULL))
);

CREATE TABLE imp.intentos_impresion
(
    intento_impresion_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_imp_intentos_impresion PRIMARY KEY,
    trabajo_impresion_id bigint NOT NULL,
    numero_intento smallint NOT NULL,
    inicio_utc datetime2(3) NOT NULL,
    fin_utc datetime2(3) NULL,
    resultado nvarchar(30) NOT NULL,
    mensaje_error nvarchar(1000) NULL,
    datos_tecnicos nvarchar(max) NULL,
    CONSTRAINT FK_imp_intentos_trabajo FOREIGN KEY (trabajo_impresion_id)
        REFERENCES imp.trabajos_impresion (trabajo_impresion_id),
    CONSTRAINT UQ_imp_intentos_numero UNIQUE (trabajo_impresion_id, numero_intento),
    CONSTRAINT CK_imp_intentos_numero CHECK (numero_intento > 0),
    CONSTRAINT CK_imp_intentos_resultado
        CHECK (resultado IN (N'COMPLETADO', N'ERROR', N'RESULTADO_DESCONOCIDO', N'CANCELADO')),
    CONSTRAINT CK_imp_intentos_fechas CHECK (fin_utc IS NULL OR fin_utc >= inicio_utc)
);

CREATE TABLE aud.eventos
(
    evento_auditoria_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_aud_eventos PRIMARY KEY,
    evento_uid uniqueidentifier NOT NULL
        CONSTRAINT DF_aud_eventos_uid DEFAULT (NEWSEQUENTIALID()),
    tipo_evento nvarchar(80) NOT NULL,
    empleado_id bigint NULL,
    cuenta_dominio nvarchar(256) NULL,
    rol_usado nvarchar(30) NULL,
    linea_id bigint NULL,
    orden_id bigint NULL,
    sesion_linea_id bigint NULL,
    entidad nvarchar(80) NOT NULL,
    entidad_id bigint NULL,
    valor_anterior nvarchar(max) NULL,
    valor_nuevo nvarchar(max) NULL,
    motivo nvarchar(1000) NULL,
    fecha_utc datetime2(3) NOT NULL CONSTRAINT DF_aud_eventos_fecha DEFAULT (SYSUTCDATETIME()),
    correlacion_id uniqueidentifier NOT NULL,
    CONSTRAINT FK_aud_eventos_empleado FOREIGN KEY (empleado_id)
        REFERENCES seg.empleados (empleado_id),
    CONSTRAINT FK_aud_eventos_linea FOREIGN KEY (linea_id)
        REFERENCES cfg.lineas (linea_id),
    CONSTRAINT FK_aud_eventos_orden FOREIGN KEY (orden_id)
        REFERENCES prod.ordenes (orden_id),
    CONSTRAINT FK_aud_eventos_sesion FOREIGN KEY (sesion_linea_id)
        REFERENCES prod.sesiones_linea (sesion_linea_id),
    CONSTRAINT UQ_aud_eventos_uid UNIQUE (evento_uid),
    CONSTRAINT CK_aud_eventos_autor CHECK (empleado_id IS NOT NULL OR cuenta_dominio IS NOT NULL),
    CONSTRAINT CK_aud_eventos_anterior
        CHECK (valor_anterior IS NULL OR ISJSON(valor_anterior) = 1),
    CONSTRAINT CK_aud_eventos_nuevo
        CHECK (valor_nuevo IS NULL OR ISJSON(valor_nuevo) = 1)
);

CREATE TABLE aud.exportaciones_historicas
(
    exportacion_historica_id bigint IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_aud_exportaciones PRIMARY KEY,
    periodo_desde date NOT NULL,
    periodo_hasta date NOT NULL,
    ubicacion nvarchar(1000) NOT NULL,
    hash_sha256 char(64) NOT NULL,
    manifiesto nvarchar(max) NOT NULL,
    numero_registros bigint NOT NULL,
    estado nvarchar(20) NOT NULL,
    generado_por_cuenta nvarchar(256) NOT NULL,
    generado_utc datetime2(3) NOT NULL,
    verificado_por_cuenta nvarchar(256) NULL,
    verificado_utc datetime2(3) NULL,
    purgado_por_cuenta nvarchar(256) NULL,
    purgado_utc datetime2(3) NULL,
    CONSTRAINT CK_aud_exportaciones_periodo CHECK (periodo_hasta >= periodo_desde),
    CONSTRAINT CK_aud_exportaciones_registros CHECK (numero_registros >= 0),
    CONSTRAINT CK_aud_exportaciones_estado
        CHECK (estado IN (N'GENERADA', N'VERIFICADA', N'PURGADA', N'ERROR')),
    CONSTRAINT CK_aud_exportaciones_json CHECK (ISJSON(manifiesto) = 1),
    CONSTRAINT CK_aud_exportaciones_hash
        CHECK (LEN(hash_sha256) = 64 AND hash_sha256 NOT LIKE '%[^0-9A-Fa-f]%'),
    CONSTRAINT CK_aud_exportaciones_fechas
        CHECK (
            estado IN (N'GENERADA', N'ERROR')
            OR (estado = N'VERIFICADA' AND verificado_por_cuenta IS NOT NULL AND verificado_utc IS NOT NULL)
            OR (estado = N'PURGADA' AND verificado_por_cuenta IS NOT NULL AND verificado_utc IS NOT NULL
                AND purgado_por_cuenta IS NOT NULL AND purgado_utc IS NOT NULL)
        )
);

COMMIT;
