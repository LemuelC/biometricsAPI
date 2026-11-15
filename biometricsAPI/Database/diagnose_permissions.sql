/* =====================================================================
   Diagnose "EXECUTE permission was denied on ... tt_m_employee".
   Run in SSMS as an admin, on the central database, right after a
   failed sync (so the API's pooled connection is still open).
   ===================================================================== */

-- Step 1: which login is the API really using?
--   Look for program_name "Core Microsoft SqlClient Data Provider".
SELECT DISTINCT s.login_name, s.host_name, s.program_name
FROM sys.dm_exec_sessions s
WHERE s.database_id = DB_ID() AND s.is_user_process = 1;
GO

-- Step 2: put that login_name here, then run the rest.
DECLARE @login sysname = N'PUT_LOGIN_NAME_HERE';

-- The database user the login maps to (the name GRANT must use).
SELECT sp.name AS login_name, dp.name AS db_user, sp.type_desc,
       IS_SRVROLEMEMBER('sysadmin', sp.name) AS is_sysadmin
FROM sys.server_principals sp
LEFT JOIN sys.database_principals dp ON dp.sid = sp.sid
WHERE sp.name = @login;

-- What that login can actually do, right now.
EXECUTE AS LOGIN = @login;
SELECT USER_NAME() AS acting_as_db_user,
       HAS_PERMS_BY_NAME('dbo.tt_m_employee', 'TYPE', 'EXECUTE')                AS can_use_type,
       HAS_PERMS_BY_NAME('dbo.usp_m_employee_upsert', 'OBJECT', 'EXECUTE')     AS can_run_proc,
       HAS_PERMS_BY_NAME('dbo.api_client', 'OBJECT', 'SELECT')                  AS can_read_api_client;
REVERT;

-- Every DENY in this database (a DENY beats any GRANT, including via a role).
SELECT pr.name AS denied_to, pr.type_desc, pe.permission_name, pe.class_desc,
       CASE pe.class WHEN 0 THEN '(whole database)'
                     WHEN 1 THEN OBJECT_SCHEMA_NAME(pe.major_id) + '.' + OBJECT_NAME(pe.major_id)
                     WHEN 3 THEN SCHEMA_NAME(pe.major_id)
                     WHEN 6 THEN (SELECT SCHEMA_NAME(t.schema_id) + '.' + t.name FROM sys.types t WHERE t.user_type_id = pe.major_id)
                     ELSE CAST(pe.major_id AS varchar(20)) END AS on_what
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pe.state = 'D';

-- Roles the API's user belongs to (a DENY above on one of these applies to it too).
SELECT r.name AS role_name
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals u ON u.principal_id = rm.member_principal_id
JOIN sys.server_principals sp ON sp.sid = u.sid
WHERE sp.name = @login;
GO
