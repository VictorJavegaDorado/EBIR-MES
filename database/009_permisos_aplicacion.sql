SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_NAME() <> N'EBIR_MES_TEST'
    THROW 51000, 'Script permitido unicamente en EBIR_MES_TEST.', 1;

IF USER_ID(N'EBIR\MES$') IS NULL
    THROW 51900, 'No existe el usuario EBIR\MES$ en EBIR_MES_TEST.', 1;

BEGIN TRANSACTION;

IF DATABASE_PRINCIPAL_ID(N'mes_runtime') IS NULL
    CREATE ROLE mes_runtime AUTHORIZATION dbo;

GRANT CONNECT TO mes_runtime;

GRANT SELECT ON SCHEMA::cfg TO mes_runtime;
GRANT SELECT ON SCHEMA::seg TO mes_runtime;
GRANT SELECT ON SCHEMA::prod TO mes_runtime;
GRANT SELECT ON SCHEMA::[log] TO mes_runtime;
GRANT SELECT ON SCHEMA::nav TO mes_runtime;
GRANT SELECT ON SCHEMA::imp TO mes_runtime;

GRANT EXECUTE ON OBJECT::prod.reservar_palet TO mes_runtime;
GRANT EXECUTE ON OBJECT::prod.cancelar_reserva_palet TO mes_runtime;
GRANT EXECUTE ON OBJECT::prod.cerrar_palet TO mes_runtime;
GRANT EXECUTE ON OBJECT::nav.confirmar_salida_palet TO mes_runtime;
GRANT EXECUTE ON OBJECT::imp.confirmar_trabajo_impresion TO mes_runtime;

DENY ALTER TO mes_runtime;
DENY CREATE TABLE TO mes_runtime;
DENY CREATE PROCEDURE TO mes_runtime;
REVOKE CONTROL FROM mes_runtime;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_role_members drm
    WHERE drm.role_principal_id = DATABASE_PRINCIPAL_ID(N'mes_runtime')
      AND drm.member_principal_id = USER_ID(N'EBIR\MES$')
)
    ALTER ROLE mes_runtime ADD MEMBER [EBIR\MES$];

COMMIT;
