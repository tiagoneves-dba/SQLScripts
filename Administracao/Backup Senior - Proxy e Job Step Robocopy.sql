/*
================================================================================
 SRVSENIOR - Envio dos backups locais para o share Samba via robocopy


 PRÉ-REQUISITOS (fazer uma vez, fora do T-SQL, direto no SRVSENIOR):
   1) A credential [BKP] já existe (CREATE CREDENTIAL) com IDENTITY/SECRET do
      usuário do Samba.
   2) Criar as pastas locais:
        C:\SQLServer\Backup\Full\
        C:\SQLServer\Backup\Logs\
        C:\SQLServer\Backup\Scripts\
      e copiar o arquivo RobocopyBackup.cmd (deste mesmo diretório do repo)
      para C:\SQLServer\Backup\Scripts\RobocopyBackup.cmd
   3) O job "DBA - Backup bases SENIOR" já existe com o passo T-SQL que executa
      dbo.stp_Backup_Bases_Senior (ver "Backup Senior - stp_Backup_Bases_Senior.sql").

 Este script é idempotente: pode ser executado mais de uma vez sem duplicar
 proxy ou o passo do job.
================================================================================
*/

USE msdb;
GO

--------------------------------------------------------------------------------
-- 1) Proxy vinculado à credential BKP, autorizado no subsistema CmdExec
--------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysproxies WHERE name = N'Proxy_BKP_Robocopy')
BEGIN
    EXEC msdb.dbo.sp_add_proxy
        @proxy_name      = N'Proxy_BKP_Robocopy',
        @credential_name = N'BKP',
        @enabled         = 1,
        @description     = N'Copia os backups locais do SRVSENIOR para o share Samba via robocopy';
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM msdb.dbo.sysproxysubsystem ps
    JOIN msdb.dbo.sysproxies p ON p.proxy_id = ps.proxy_id
    JOIN msdb.dbo.syssubsystems s ON s.subsystem_id = ps.subsystem_id
    WHERE p.name = N'Proxy_BKP_Robocopy' AND s.subsystem = N'CmdExec'
)
BEGIN
    EXEC msdb.dbo.sp_grant_proxy_to_subsystem
        @proxy_name     = N'Proxy_BKP_Robocopy',
        @subsystem_name = N'CmdExec';
END
GO

-- Só é necessário se o job NÃO rodar sob um login sysadmin (membros do
-- sysadmin usam qualquer proxy automaticamente, sem precisar de grant).
-- Ajuste o login abaixo se o "Run as" do job não for sysadmin:
-- EXEC msdb.dbo.sp_grant_login_to_proxy
--     @proxy_name = N'Proxy_BKP_Robocopy',
--     @login_name = N'dominio\usuario_do_job';
-- GO

--------------------------------------------------------------------------------
-- 2) Adiciona o passo de robocopy ao job existente, executado após o passo
--    de T-SQL que gera os backups locais
--------------------------------------------------------------------------------
DECLARE @job_id       UNIQUEIDENTIFIER;
DECLARE @proxy_id     INT;
DECLARE @last_step_id INT;
DECLARE @new_step_id  INT;

SELECT @job_id = job_id
FROM msdb.dbo.sysjobs
WHERE name = N'DBA - Backup bases SENIOR';

IF @job_id IS NULL
BEGIN
    RAISERROR('Job "DBA - Backup bases SENIOR" não encontrado em msdb.dbo.sysjobs. Ajuste o nome ou crie o job antes de rodar este script.', 16, 1);
    RETURN;
END

SELECT @proxy_id = proxy_id
FROM msdb.dbo.sysproxies
WHERE name = N'Proxy_BKP_Robocopy';

IF NOT EXISTS (
    SELECT 1 FROM msdb.dbo.sysjobsteps
    WHERE job_id = @job_id AND step_name = N'Copiar backups para share Samba (robocopy)'
)
BEGIN

    SELECT TOP 1 @last_step_id = step_id
    FROM msdb.dbo.sysjobsteps
    WHERE job_id = @job_id
    ORDER BY step_id DESC;

    SET @new_step_id = @last_step_id + 1;

    -- O último passo atual (backup local), em caso de sucesso, passa a seguir
    -- para o novo passo de robocopy em vez de encerrar o job
    EXEC msdb.dbo.sp_update_jobstep
        @job_id             = @job_id,
        @step_id            = @last_step_id,
        @on_success_action  = 3, -- Go to next step
        @on_success_step_id = @new_step_id;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id               = @job_id,
        @step_id              = @new_step_id,
        @step_name            = N'Copiar backups para share Samba (robocopy)',
        @subsystem            = N'CMDEXEC',
        @command              = N'"C:\SQLServer\Backup\Scripts\RobocopyBackup.cmd"',
        @proxy_id             = @proxy_id,
        @cmdexec_success_code = 0,
        @on_success_action    = 1, -- Quit with success
        @on_fail_action       = 2, -- Quit with failure
        @retry_attempts       = 2,
        @retry_interval       = 2,
        @os_run_priority      = 0,
        @flags                = 0;

    PRINT 'Passo de robocopy adicionado ao job "DBA - Backup bases SENIOR" (step_id ' + CAST(@new_step_id AS VARCHAR(10)) + ').';
END
ELSE
BEGIN
    PRINT 'Passo de robocopy já existe no job - nada a fazer.';
END
GO
