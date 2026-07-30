SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

BEGIN TRANSACTION;

CREATE UNIQUE INDEX UX_seg_credenciales_rfid_empleado_activa
    ON seg.credenciales_rfid (empleado_id)
    WHERE activa = 1;

CREATE UNIQUE INDEX UX_seg_credenciales_rfid_huella_activa
    ON seg.credenciales_rfid (rfid_busqueda)
    WHERE activa = 1;

CREATE UNIQUE INDEX UX_seg_empleados_roles_activo
    ON seg.empleados_roles (empleado_id, rol_id)
    WHERE hasta_utc IS NULL;

CREATE UNIQUE INDEX UX_cfg_lineas_dispositivos_linea_activa
    ON cfg.lineas_dispositivos (linea_id)
    WHERE asignado_hasta_utc IS NULL;

CREATE UNIQUE INDEX UX_cfg_lineas_dispositivos_dispositivo_activo
    ON cfg.lineas_dispositivos (dispositivo_id)
    WHERE asignado_hasta_utc IS NULL;

CREATE UNIQUE INDEX UX_cfg_lineas_impresoras_principal
    ON cfg.lineas_impresoras (linea_id)
    WHERE asignado_hasta_utc IS NULL AND es_principal = 1;

CREATE UNIQUE INDEX UX_prod_sesiones_linea_activa
    ON prod.sesiones_linea (linea_id)
    WHERE finalizada_utc IS NULL;

CREATE UNIQUE INDEX UX_prod_formatos_predeterminado
    ON prod.formatos_palet_orden (orden_id)
    WHERE es_predeterminado_nav = 1 AND activo = 1;

CREATE INDEX IX_prod_formatos_orden_activos
    ON prod.formatos_palet_orden (orden_id, activo)
    INCLUDE (codigo_formato, unidades_por_palet, es_predeterminado_nav);

CREATE UNIQUE INDEX UX_prod_estados_linea_sesion
    ON prod.estados_linea (sesion_linea_id)
    WHERE sesion_linea_id IS NOT NULL;

CREATE UNIQUE INDEX UX_prod_fichajes_empleado_abierto
    ON prod.fichajes (empleado_id)
    WHERE salida_utc IS NULL;

CREATE UNIQUE INDEX UX_prod_paros_fichaje_abierto
    ON prod.paros_operario (fichaje_id)
    WHERE fin_utc IS NULL;

CREATE UNIQUE INDEX UX_prod_paradas_sesion_abierta
    ON prod.paradas_linea (sesion_linea_id)
    WHERE fin_utc IS NULL;

CREATE UNIQUE INDEX UX_prod_sustituciones_operario_activa
    ON prod.sustituciones_capacidad (operario_sustituido_id)
    WHERE fin_utc IS NULL;

CREATE UNIQUE INDEX UX_prod_sustituciones_supervisor_activa
    ON prod.sustituciones_capacidad (supervisor_sustituto_id)
    WHERE fin_utc IS NULL;

CREATE UNIQUE INDEX UX_prod_tramos_sesion_abierto
    ON prod.tramos_capacidad (sesion_linea_id)
    WHERE fin_utc IS NULL;

CREATE UNIQUE INDEX UX_prod_reservas_sesion_activa
    ON prod.reservas_palet (sesion_linea_id)
    WHERE estado = N'ACTIVA';

CREATE INDEX IX_prod_ordenes_estado
    ON prod.ordenes (estado, importada_utc)
    INCLUDE (numero_orden, producto_codigo, cantidad_objetivo,
             cantidad_buena_acumulada, cantidad_reservada_activa);

CREATE INDEX IX_prod_sesiones_orden_estado
    ON prod.sesiones_linea (orden_id, estado, finalizada_utc)
    INCLUDE (linea_id, turno_id, fecha_operativa);

CREATE INDEX IX_prod_fichajes_sesion_abiertos
    ON prod.fichajes (sesion_linea_id, salida_utc)
    INCLUDE (empleado_id, entrada_utc, estado, linea_id);

CREATE INDEX IX_prod_reservas_orden_estado
    ON prod.reservas_palet (orden_id, estado, creada_utc)
    INCLUDE (sesion_linea_id, cantidad_reservada);

CREATE INDEX IX_prod_palets_orden_fecha
    ON prod.palets (orden_id, cerrado_utc)
    INCLUDE (numero_palet, cantidad_buena, sesion_linea_id, estado);

CREATE INDEX IX_prod_tramos_sesion_fecha
    ON prod.tramos_capacidad (sesion_linea_id, inicio_utc)
    INCLUDE (fin_utc, recursos_activos, capacidad_teorica_hora, segundos_productivos);

CREATE INDEX IX_log_scrap_orden_fecha
    ON [log].scrap (orden_id, registrado_utc)
    INCLUDE (cantidad, componente_orden_id, motivo_scrap_id);

CREATE INDEX IX_log_revisiones_scrap_numero
    ON [log].revisiones_scrap (scrap_id, numero_revision DESC)
    INCLUDE (cantidad, componente_orden_id, motivo_scrap_id, es_anulacion, ajustado_utc);

CREATE INDEX IX_log_solicitudes_panel
    ON [log].solicitudes_reaprovisionamiento (estado, solicitada_utc)
    INCLUDE (linea_id, orden_id, componente_orden_id, cantidad_solicitada, asignada_a_empleado_id);

CREATE INDEX IX_log_historial_solicitud_fecha
    ON [log].historial_solicitudes (solicitud_id, fecha_utc)
    INCLUDE (estado_anterior, estado_nuevo, empleado_id);

CREATE INDEX IX_nav_operaciones_cola
    ON nav.operaciones (estado, proximo_intento_utc, creada_utc)
    INCLUDE (tipo, orden_id, palet_id, scrap_id, revision_scrap_id, numero_intentos);

CREATE UNIQUE INDEX UX_imp_etiquetas_palet
    ON imp.etiquetas (palet_id)
    WHERE tipo = N'PALET' AND palet_id IS NOT NULL;

CREATE UNIQUE INDEX UX_imp_etiquetas_salida_orden
    ON imp.etiquetas (orden_id)
    WHERE tipo = N'SALIDA_FABRICA';

CREATE UNIQUE INDEX UX_imp_trabajos_original
    ON imp.trabajos_impresion (etiqueta_id)
    WHERE es_reimpresion = 0;

CREATE INDEX IX_imp_etiquetas_estado
    ON imp.etiquetas (estado, habilitada_utc, creada_utc)
    INCLUDE (tipo, orden_id, palet_id, codigo_visible);

CREATE INDEX IX_imp_trabajos_cola
    ON imp.trabajos_impresion (estado, creado_utc)
    INCLUDE (etiqueta_id, impresora_solicitada_id, impresora_utilizada_id, es_reimpresion);

CREATE INDEX IX_aud_eventos_orden_fecha
    ON aud.eventos (orden_id, fecha_utc)
    INCLUDE (tipo_evento, empleado_id, linea_id, entidad, entidad_id);

CREATE INDEX IX_aud_eventos_linea_fecha
    ON aud.eventos (linea_id, fecha_utc)
    INCLUDE (tipo_evento, empleado_id, orden_id, entidad, entidad_id);

CREATE INDEX IX_aud_eventos_empleado_fecha
    ON aud.eventos (empleado_id, fecha_utc)
    INCLUDE (tipo_evento, linea_id, orden_id, entidad, entidad_id);

COMMIT;
