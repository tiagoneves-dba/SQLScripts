USE [DBA]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------------------------
-- PROCEDURE DE BACKUP - SRVSENIOR
--
-- Grava o .bak em disco LOCAL (C:\SQLServer\Backup\Full\<Base>\...).
-- O envio para o share Samba (\\192.168.8.150\backups\bkpstandalone\BackupsBD_ERPS\SRVSENIOR\Full)
-- é feito por um passo separado do SQL Agent Job "DBA - Backup bases SENIOR",
-- via robocopy, rodando sob o Proxy vinculado à credential [BKP].
-- Ver: "Backup Senior - Proxy e Job Step Robocopy.sql" e "RobocopyBackup.cmd"
--
-- Motivo: BACKUP DATABASE ... TO DISK não consome CREDENTIAL do SQL Server
-- (isso só se aplica a BACKUP ... TO URL). Como o serviço do SQL Server não
-- autentica no share Samba, o backup é feito local e copiado depois.
------------------------------------------------------------------------------

ALTER PROCEDURE [dbo].[stp_Backup_Bases_Senior]
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE
        @DatabaseName SYSNAME,
        @LocalFolder  NVARCHAR(4000),
        @BackupFile   NVARCHAR(4000),
        @DataAtual    VARCHAR(8),
        @Comando      NVARCHAR(MAX);

    -- DATA NO FORMATO YYYYMMDD
    SET @DataAtual = CONVERT(VARCHAR(8), GETDATE(), 112);

    --------------------------------------------------------------------------
    -- TABELA COM AS BASES
    --------------------------------------------------------------------------

    DECLARE @Bases TABLE
    (
        NomeBase SYSNAME
    );

    INSERT INTO @Bases
    VALUES
        ('sapiens'),
        ('edocs'),
        ('Senior_middle');

    --------------------------------------------------------------------------
    -- CURSOR PARA EXECUTAR OS BACKUPS
    --------------------------------------------------------------------------

    DECLARE cBases CURSOR FOR
    SELECT NomeBase
    FROM @Bases;

    OPEN cBases;

    FETCH NEXT FROM cBases INTO @DatabaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN

        ----------------------------------------------------------------------
        -- MONTA O CAMINHO LOCAL E GARANTE QUE A PASTA EXISTA
        ----------------------------------------------------------------------

        SET @LocalFolder = N'C:\SQLServer\Backup\Full\' + @DatabaseName;

        -- evita falha caso um novo banco seja adicionado à lista sem a pasta existir
        EXEC master.dbo.xp_create_subdir @LocalFolder;

        SET @BackupFile =
            @LocalFolder + '\'
            + @DatabaseName + '_'
            + @DataAtual
            + '.bak';

        ----------------------------------------------------------------------
        -- COMANDO DE BACKUP
        ----------------------------------------------------------------------

        SET @Comando = '
        BACKUP DATABASE [' + @DatabaseName + ']
        TO DISK = ''' + @BackupFile + '''
        WITH
            COMPRESSION,
            CHECKSUM,
            STATS = 5,
            INIT';

        PRINT @Comando;

        EXEC(@Comando);

        FETCH NEXT FROM cBases INTO @DatabaseName;

    END

    CLOSE cBases;
    DEALLOCATE cBases;

END
GO
