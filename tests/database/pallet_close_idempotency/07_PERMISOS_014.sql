/* Paquete 014: permisos efectivos. No modifica datos. */
SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME() <> N'EBIR_MES_TEST' THROW 57700, 'Pruebas permitidas unicamente en EBIR_MES_TEST.', 1;
IF USER_ID(N'EBIR\MES$') IS NULL OR DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL THROW 57701, 'Runtime ausente.', 1;
EXECUTE AS USER = N'EBIR\MES$';
BEGIN TRY
    IF HAS_PERMS_BY_NAME(N'prod.cerrar_palet_idempotente',N'OBJECT',N'EXECUTE') <> 1 THROW 57702, 'Runtime sin contrato nuevo.', 1;
    IF HAS_PERMS_BY_NAME(N'prod.cerrar_palet',N'OBJECT',N'EXECUTE') <> 0 THROW 57703, 'Runtime conserva contrato anterior.', 1;
    IF HAS_PERMS_BY_NAME(N'prod.palets',N'OBJECT',N'INSERT') <> 0 OR HAS_PERMS_BY_NAME(N'nav.operaciones',N'OBJECT',N'INSERT') <> 0 OR HAS_PERMS_BY_NAME(N'imp.etiquetas',N'OBJECT',N'INSERT') <> 0 THROW 57704, 'Runtime puede escribir directamente.', 1;
END TRY BEGIN CATCH REVERT; THROW; END CATCH;
REVERT;
PRINT N'PERMISOS 014: OK';
