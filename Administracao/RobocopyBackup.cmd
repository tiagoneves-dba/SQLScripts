@echo off
REM ==============================================================================
REM  SRVSENIOR - Copia os .bak locais para o share Samba e libera espaco local.
REM  Chamado pelo passo CmdExec do job "DBA - Backup bases SENIOR", rodando sob
REM  o Proxy vinculado a credential [BKP].
REM
REM  /MOV  move os arquivos (apaga da origem so apos copiar com sucesso),
REM        mantendo as pastas por base para o proximo backup.
REM  /E    copia subpastas, inclusive vazias.
REM  /R:3 /W:10  no maximo 3 tentativas, 10s de espera (evita ficar preso no
REM        default do robocopy em caso de falha de rede).
REM
REM  Codigos de saida do robocopy: 0-7 = sucesso (com variacoes), >=8 = falha.
REM  O CmdExec do SQL Agent trata qualquer saida != 0 como falha, entao o
REM  errorlevel e traduzido abaixo.
REM ==============================================================================

robocopy "C:\SQLServer\Backup\Full" "\\192.168.8.150\backups\bkpstandalone\BackupsBD_ERPS\SRVSENIOR\Full" /MOV /E /R:3 /W:10 /NP /LOG:C:\SQLServer\Backup\Logs\robocopy_backup.log

IF %ERRORLEVEL% GEQ 8 (
    EXIT /B 1
) ELSE (
    EXIT /B 0
)
