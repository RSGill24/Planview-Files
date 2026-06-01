/*
================================================================================
  Planview2026PlatinumConsolidatedUpdated
================================================================================
  
  INPUTS (loaded by Python Step 1):
      [{@InputSchema}].[{@Stem}_Initiatives]
      [{@InputSchema}].[{@Stem}_Epics]
      [{@InputSchema}].[{@Stem}_Tasks]

  PARAMETERS:
      @RunID           nvarchar(50)    e.g. '20250501_143022'
      @InputSchema     nvarchar(128)   e.g. 'input_20250501_143022'
      @Stem            nvarchar(200)   e.g. 'Planview_Prod_Data_Extract_05_01'
      @NRB_Field       nvarchar(256)   NRB column SQL-safe name
      @NRB_Threshold_M float           NRB cutoff in millions e.g. 10

  RETURNS (6 result sets read by Python in order):
      1 — Mapped Initiatives rows  (all original cols, no extra cols)
      2 — Mapped Epics rows        (all original cols, no extra cols)
      3 — Scalar counts: removed_in, removed_ep, new_id_count (all 0)
      4 — changes_in  (col, cnt)
      5 — changes_ep  (col, cnt)
      6 — Mapped Tasks rows        (all original cols, no extra cols)

  DEPLOYMENT: Run once in SSMS — no parameters needed at deployment time.
================================================================================
*/

CREATE OR ALTER PROCEDURE dbo.Planview2026PlatinumConsolidatedUpdated
    @RunID           nvarchar(50),
    @InputSchema     nvarchar(128),
    @Stem            nvarchar(200),
    @NRB_Field       nvarchar(256),
    @NRB_Threshold_M float = 10
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @tbl_init   nvarchar(500),
        @tbl_epic   nvarchar(500),
        @tbl_task   nvarchar(500),
        @tbl_iwork  nvarchar(500),
        @tbl_ework  nvarchar(500),
        @tbl_twork  nvarchar(500),
        @sql        nvarchar(MAX);

    SET @tbl_init  = QUOTENAME(@InputSchema) + '.' + QUOTENAME(@Stem + '_Initiatives');
    SET @tbl_epic  = QUOTENAME(@InputSchema) + '.' + QUOTENAME(@Stem + '_Epics');
    SET @tbl_task  = QUOTENAME(@InputSchema) + '.' + QUOTENAME(@Stem + '_Tasks');
    SET @tbl_iwork = QUOTENAME(@InputSchema) + '.' + QUOTENAME(@Stem + '_Initiatives_Work');
    SET @tbl_ework = QUOTENAME(@InputSchema) + '.' + QUOTENAME(@Stem + '_Epics_Work');
    SET @tbl_twork = QUOTENAME(@InputSchema) + '.' + QUOTENAME(@Stem + '_Tasks_Work');

    -- Change count tracking
    IF OBJECT_ID('tempdb..#changes') IS NOT NULL DROP TABLE #changes;
    CREATE TABLE #changes (
        source  nvarchar(10),
        col     nvarchar(256),
        cnt     int
    );

    -- Clone raw input into working copies — originals are never mutated
    SET @sql = N'IF OBJECT_ID(''' + REPLACE(@tbl_iwork,'''','''''') + N''') IS NOT NULL DROP TABLE ' + @tbl_iwork;
    EXEC sp_executesql @sql;
    SET @sql = N'IF OBJECT_ID(''' + REPLACE(@tbl_ework,'''','''''') + N''') IS NOT NULL DROP TABLE ' + @tbl_ework;
    EXEC sp_executesql @sql;
    SET @sql = N'IF OBJECT_ID(''' + REPLACE(@tbl_twork,'''','''''') + N''') IS NOT NULL DROP TABLE ' + @tbl_twork;
    EXEC sp_executesql @sql;

    SET @sql = N'SELECT * INTO ' + @tbl_iwork + N' FROM ' + @tbl_init;
    EXEC sp_executesql @sql;
    SET @sql = N'SELECT * INTO ' + @tbl_ework + N' FROM ' + @tbl_epic;
    EXEC sp_executesql @sql;
    SET @sql = N'SELECT * INTO ' + @tbl_twork + N' FROM ' + @tbl_task;
    EXEC sp_executesql @sql;

    -- ── Step 2a: Value Transformations ───────────────────────────────────────

    -- ── Mapping 2: Work Status — Epics only ─────────────────────────────────
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = 'Work Status')
    BEGIN
        SET @sql = N'
            DECLARE @cnt_ws int;
            SELECT @cnt_ws = COUNT(*) FROM ' + @tbl_ework + N'
            WHERE LTRIM(RTRIM(ISNULL([Work Status], ''''))) <> ''''
              AND [Work Status] <> CASE LTRIM(RTRIM([Work Status]))
                    WHEN ''Not Started''       THEN ''New''
                    WHEN ''Approved''          THEN ''Active''
                    WHEN ''In Progress''       THEN ''Active''
                    WHEN ''On Hold''           THEN ''On Hold''
                    WHEN ''Closed''            THEN ''Completed/Closed''
                    WHEN ''Completed''         THEN ''Completed/Closed''
                    WHEN ''Assumed Completed'' THEN ''Completed/Closed''
                    WHEN ''Cancelled''         THEN ''Cancelled''
                    WHEN ''Rejected''          THEN ''Rejected''
                    ELSE [Work Status]
                END;
            UPDATE ' + @tbl_ework + N'
            SET [Work Status] = CASE LTRIM(RTRIM([Work Status]))
                WHEN ''Not Started''       THEN ''New''
                WHEN ''Approved''          THEN ''Active''
                WHEN ''In Progress''       THEN ''Active''
                WHEN ''On Hold''           THEN ''On Hold''
                WHEN ''Closed''            THEN ''Completed/Closed''
                WHEN ''Completed''         THEN ''Completed/Closed''
                WHEN ''Assumed Completed'' THEN ''Completed/Closed''
                WHEN ''Cancelled''         THEN ''Cancelled''
                WHEN ''Rejected''          THEN ''Rejected''
                ELSE [Work Status]
            END
            WHERE LTRIM(RTRIM(ISNULL([Work Status], ''''))) <> '''';
            INSERT INTO #changes VALUES (''epic'', ''Work Status (old→new)'', @cnt_ws);
        ';
        EXEC sp_executesql @sql;
    END

    -- ── Mapping 3: Estimated Annualized Value Range — both sheets ────────────
    DECLARE @evr_case nvarchar(MAX) = N'
        CASE LTRIM(RTRIM([Estimated Annualized Value Range]))
            WHEN ''1: Unknown''                     THEN ''''
            WHEN ''2: Low = < $1M''                 THEN ''1: Low = < $1M''
            WHEN ''3: Medium = $1M < Value < $10M'' THEN ''2: Medium = $1M < Value < $10M''
            WHEN ''4: High = > $10M''               THEN ''3: High = > $10M''
            WHEN ''zz Medium: $5M-$10M''            THEN ''2: Medium = $1M < Value < $10M''
            WHEN ''zz Maximum: >$35M''              THEN ''3: High = > $10M''
            ELSE [Estimated Annualized Value Range]
        END';

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Estimated Annualized Value Range')
    BEGIN
        SET @sql = N'
            DECLARE @cnt_evr_i int;
            SELECT @cnt_evr_i = COUNT(*) FROM ' + @tbl_iwork + N'
            WHERE LTRIM(RTRIM(ISNULL([Estimated Annualized Value Range], ''''))) <> ''''
              AND [Estimated Annualized Value Range] <> ' + @evr_case + N';
            UPDATE ' + @tbl_iwork + N'
            SET [Estimated Annualized Value Range] = ' + @evr_case + N'
            WHERE LTRIM(RTRIM(ISNULL([Estimated Annualized Value Range], ''''))) <> '''';
            INSERT INTO #changes VALUES (''init'', ''Estimated Value Range (renumbered)'', @cnt_evr_i);
        ';
        EXEC sp_executesql @sql;
    END

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = 'Estimated Annualized Value Range')
    BEGIN
        SET @sql = N'
            DECLARE @cnt_evr_e int;
            SELECT @cnt_evr_e = COUNT(*) FROM ' + @tbl_ework + N'
            WHERE LTRIM(RTRIM(ISNULL([Estimated Annualized Value Range], ''''))) <> ''''
              AND [Estimated Annualized Value Range] <> ' + @evr_case + N';
            UPDATE ' + @tbl_ework + N'
            SET [Estimated Annualized Value Range] = ' + @evr_case + N'
            WHERE LTRIM(RTRIM(ISNULL([Estimated Annualized Value Range], ''''))) <> '''';
            INSERT INTO #changes VALUES (''epic'', ''Estimated Value Range (renumbered)'', @cnt_evr_e);
        ';
        EXEC sp_executesql @sql;
    END

    -- ── Mapping 4: Home Portfolio — both sheets ──────────────────────────────
    DECLARE @hp_col nvarchar(256), @hp_case nvarchar(MAX);

    DECLARE @hp_init TABLE (col nvarchar(256));
    INSERT INTO @hp_init VALUES
        ('Demand Domain or Portfolio'), ('Portfolio'), ('Domain'), ('Home Portfolio');

    DECLARE hp_i CURSOR LOCAL FAST_FORWARD FOR SELECT col FROM @hp_init;
    OPEN hp_i; FETCH NEXT FROM hp_i INTO @hp_col;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = @hp_col)
        BEGIN
            SET @hp_case = N'CASE LTRIM(RTRIM(' + QUOTENAME(@hp_col) + N'))
                WHEN ''Data & AI'' THEN ''Platforms'' ELSE ' + QUOTENAME(@hp_col) + N' END';
            SET @sql = N'
                DECLARE @cnt_hp_i int;
                SELECT @cnt_hp_i = COUNT(*) FROM ' + @tbl_iwork + N'
                WHERE LTRIM(RTRIM(' + QUOTENAME(@hp_col) + N')) = ''Data & AI'';
                UPDATE ' + @tbl_iwork + N'
                SET ' + QUOTENAME(@hp_col) + N' = ' + @hp_case + N'
                WHERE LTRIM(RTRIM(ISNULL(' + QUOTENAME(@hp_col) + N', ''''))) <> '''';
                INSERT INTO #changes VALUES (''init'', ''Home Portfolio [' + @hp_col + N']'', @cnt_hp_i);
            ';
            EXEC sp_executesql @sql;
        END
        FETCH NEXT FROM hp_i INTO @hp_col;
    END
    CLOSE hp_i; DEALLOCATE hp_i;

    DECLARE @hp_epic TABLE (col nvarchar(256));
    INSERT INTO @hp_epic VALUES
        ('Home Domain/Portfolio'), ('Portfolio'), ('Domain'), ('Home Portfolio');

    DECLARE hp_e CURSOR LOCAL FAST_FORWARD FOR SELECT col FROM @hp_epic;
    OPEN hp_e; FETCH NEXT FROM hp_e INTO @hp_col;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = @hp_col)
        BEGIN
            SET @hp_case = N'CASE LTRIM(RTRIM(' + QUOTENAME(@hp_col) + N'))
                WHEN ''Data & AI'' THEN ''Platforms'' ELSE ' + QUOTENAME(@hp_col) + N' END';
            SET @sql = N'
                DECLARE @cnt_hp_e int;
                SELECT @cnt_hp_e = COUNT(*) FROM ' + @tbl_ework + N'
                WHERE LTRIM(RTRIM(' + QUOTENAME(@hp_col) + N')) = ''Data & AI'';
                UPDATE ' + @tbl_ework + N'
                SET ' + QUOTENAME(@hp_col) + N' = ' + @hp_case + N'
                WHERE LTRIM(RTRIM(ISNULL(' + QUOTENAME(@hp_col) + N', ''''))) <> '''';
                INSERT INTO #changes VALUES (''epic'', ''Home Portfolio [' + @hp_col + N']'', @cnt_hp_e);
            ';
            EXEC sp_executesql @sql;
        END
        FETCH NEXT FROM hp_e INTO @hp_col;
    END
    CLOSE hp_e; DEALLOCATE hp_e;

    -- ── Mapping 5: Demand SubType — Initiatives only ─────────────────────────
    -- Two updates:
    --   1. Protect Purple → Infosec (Protect Purple)
    --   2. null / blank   → 'None' (string, per mapping table)
    DECLARE @dst_col nvarchar(256);
    DECLARE @dst_cols TABLE (col nvarchar(256));
    INSERT INTO @dst_cols VALUES ('Demand SubType'), ('Demand_SubType');

    DECLARE dst CURSOR LOCAL FAST_FORWARD FOR SELECT col FROM @dst_cols;
    OPEN dst; FETCH NEXT FROM dst INTO @dst_col;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = @dst_col)
        BEGIN
            -- Update 1: Protect Purple → Infosec (Protect Purple)
            SET @sql = N'
                DECLARE @cnt_dst int;
                SELECT @cnt_dst = COUNT(*) FROM ' + @tbl_iwork + N'
                WHERE LTRIM(RTRIM(' + QUOTENAME(@dst_col) + N')) = ''Protect Purple'';
                UPDATE ' + @tbl_iwork + N'
                SET ' + QUOTENAME(@dst_col) + N' =
                    CASE LTRIM(RTRIM(' + QUOTENAME(@dst_col) + N'))
                        WHEN ''Protect Purple'' THEN ''Infosec (Protect Purple)''
                        ELSE ' + QUOTENAME(@dst_col) + N'
                    END
                WHERE LTRIM(RTRIM(ISNULL(' + QUOTENAME(@dst_col) + N', ''''))) <> '''';
                INSERT INTO #changes VALUES (''init'', ''Demand SubType (Protect Purple→Infosec)'', @cnt_dst);
            ';
            EXEC sp_executesql @sql;

            -- Update 2: null / blank → string ''None''
            SET @sql = N'
                DECLARE @cnt_dst_null int;
                SELECT @cnt_dst_null = COUNT(*) FROM ' + @tbl_iwork + N'
                WHERE LTRIM(RTRIM(ISNULL(' + QUOTENAME(@dst_col) + N', ''''))) = '''';
                UPDATE ' + @tbl_iwork + N'
                SET ' + QUOTENAME(@dst_col) + N' = ''None''
                WHERE LTRIM(RTRIM(ISNULL(' + QUOTENAME(@dst_col) + N', ''''))) = '''';
                INSERT INTO #changes VALUES (''init'', ''Demand SubType (null/blank→None)'', @cnt_dst_null);
            ';
            EXEC sp_executesql @sql;
        END
        FETCH NEXT FROM dst INTO @dst_col;
    END
    CLOSE dst; DEALLOCATE dst;

    -- ── Mapping 6: Milestone Type — Epics only ───────────────────────────────
    DECLARE @mt_col nvarchar(256);
    DECLARE @mt_cols TABLE (col nvarchar(256));
    INSERT INTO @mt_cols VALUES
        ('Task or Milestone Type'), ('Milestone Type'), ('Milestone Type (Old)');

    DECLARE mt CURSOR LOCAL FAST_FORWARD FOR SELECT col FROM @mt_cols;
    OPEN mt; FETCH NEXT FROM mt INTO @mt_col;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = @mt_col)
        BEGIN
            SET @sql = N'
                DECLARE @cnt_mt int;
                SELECT @cnt_mt = COUNT(*) FROM ' + @tbl_ework + N'
                WHERE LTRIM(RTRIM(' + QUOTENAME(@mt_col) + N'))
                      IN (''Technology / Systems'',''Finance'',''Legal'',''Other dependency'');
                UPDATE ' + @tbl_ework + N'
                SET ' + QUOTENAME(@mt_col) + N' =
                    CASE LTRIM(RTRIM(' + QUOTENAME(@mt_col) + N'))
                        WHEN ''Technology / Systems'' THEN ''Technology''
                        WHEN ''Finance''              THEN ''Other''
                        WHEN ''Legal''                THEN ''Legal / Regulatory''
                        WHEN ''Other dependency''     THEN ''Other''
                        ELSE ' + QUOTENAME(@mt_col) + N'
                    END
                WHERE LTRIM(RTRIM(ISNULL(' + QUOTENAME(@mt_col) + N', ''''))) <> '''';
                INSERT INTO #changes VALUES (''epic'', ''Milestone Type [' + @mt_col + N']'', @cnt_mt);
            ';
            EXEC sp_executesql @sql;
        END
        FETCH NEXT FROM mt INTO @mt_col;
    END
    CLOSE mt; DEALLOCATE mt;

    -- ── Mapping 7: Work Type — both sheets ──────────────────────────────────
    -- Maps existing Work Type column based on old Demand Type value (WR2 table).
    -- Demand Type is NOT remapped — it stays as-is from the input file.
    -- SBA rows have no Demand Type so they passthrough unchanged.
    DECLARE @wt_case nvarchar(MAX) = N'
        CASE LTRIM(RTRIM([Demand Type]))
            WHEN ''Business w/ Tech''            THEN ''Tech-Enabled Request''
            WHEN ''Business w/ Tech Initiative''  THEN ''Tech-Enabled Request''
            WHEN ''Local Enhancement''            THEN ''Tech-Enabled Request''
            WHEN ''Local Enhancement Epic''       THEN ''Tech-Enabled Request''
            WHEN ''Lifecycle Management''         THEN ''Tech-Enabled Request''
            WHEN ''Lifecycle Management Epic''    THEN ''Tech-Enabled Request''
            WHEN ''Business Only''               THEN ''Business Demand''
            WHEN ''Business Only Initiative''    THEN ''Business Demand''
            ELSE [Work Type]
        END';

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Work Type')
     AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Demand Type')
    BEGIN
        SET @sql = N'
            DECLARE @cnt_wt_i int;
            SELECT @cnt_wt_i = COUNT(*) FROM ' + @tbl_iwork + N'
            WHERE LTRIM(RTRIM(ISNULL([Demand Type], ''''))) <> ''''
              AND ISNULL([Work Type],'''') <> ' + @wt_case + N';
            UPDATE ' + @tbl_iwork + N'
            SET [Work Type] = ' + @wt_case + N'
            WHERE LTRIM(RTRIM(ISNULL([Demand Type], ''''))) <> '''';
            INSERT INTO #changes VALUES (''init'', ''Work Type (Demand Type→Tech-Enabled/Business Demand)'', @cnt_wt_i);
        ';
        EXEC sp_executesql @sql;
    END

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = 'Work Type')
     AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = 'Demand Type')
    BEGIN
        SET @sql = N'
            DECLARE @cnt_wt_e int;
            SELECT @cnt_wt_e = COUNT(*) FROM ' + @tbl_ework + N'
            WHERE LTRIM(RTRIM(ISNULL([Demand Type], ''''))) <> ''''
              AND ISNULL([Work Type],'''') <> ' + @wt_case + N';
            UPDATE ' + @tbl_ework + N'
            SET [Work Type] = ' + @wt_case + N'
            WHERE LTRIM(RTRIM(ISNULL([Demand Type], ''''))) <> '''';
            INSERT INTO #changes VALUES (''epic'', ''Work Type (Demand Type→Tech-Enabled/Business Demand)'', @cnt_wt_e);
        ';
        EXEC sp_executesql @sql;
    END

    -- ── Mapping 8: Impacted Portfolios — both sheets ─────────────────────────
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Impacted Portfolios')
    BEGIN
        SET @sql = N'
            DECLARE @cnt_ip_i int;
            SELECT @cnt_ip_i = COUNT(*) FROM ' + @tbl_iwork + N'
            WHERE [Impacted Portfolios] LIKE ''%Data & AI%'';
            UPDATE ' + @tbl_iwork + N'
            SET [Impacted Portfolios] = REPLACE([Impacted Portfolios], ''Data & AI'', ''Platforms'')
            WHERE [Impacted Portfolios] LIKE ''%Data & AI%'';
            INSERT INTO #changes VALUES (''init'', ''Impacted Portfolios (Data & AI→Platforms)'', @cnt_ip_i);
        ';
        EXEC sp_executesql @sql;
    END

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = 'Impacted Portfolios')
    BEGIN
        SET @sql = N'
            DECLARE @cnt_ip_e int;
            SELECT @cnt_ip_e = COUNT(*) FROM ' + @tbl_ework + N'
            WHERE [Impacted Portfolios] LIKE ''%Data & AI%'';
            UPDATE ' + @tbl_ework + N'
            SET [Impacted Portfolios] = REPLACE([Impacted Portfolios], ''Data & AI'', ''Platforms'')
            WHERE [Impacted Portfolios] LIKE ''%Data & AI%'';
            INSERT INTO #changes VALUES (''epic'', ''Impacted Portfolios (Data & AI→Platforms)'', @cnt_ip_e);
        ';
        EXEC sp_executesql @sql;
    END

    -- ── Mapping 9: Demand Domain or Portfolio — both sheets ──────────────────
    DECLARE @ddp_case nvarchar(MAX) = N'
        CASE LTRIM(RTRIM([Demand Domain or Portfolio]))
            WHEN ''APAC Domain''                              THEN ''APAC''
            WHEN ''Airline Domain''                           THEN ''Airline''
            WHEN ''Americas International''                   THEN ''Americas International''
            WHEN ''Commercial Domain''                        THEN ''Commercial''
            WHEN ''Commercial Portfolio''                     THEN ''''
            WHEN ''Data and Tech Domain''                     THEN ''Data and Tech''
            WHEN ''Data & AI Portfolio''                      THEN ''''
            WHEN ''Dock Domain''                              THEN ''Dock''
            WHEN ''Enterprise Services Portfolio''            THEN ''''
            WHEN ''Europe Domain''                            THEN ''Europe''
            WHEN ''Freight Domain''                           THEN ''Freight''
            WHEN ''Global Air Hubs & Ramps Domain''           THEN ''Global Air Hubs & Ramps''
            WHEN ''Global Capabilities Strategy Domain''      THEN ''Global Capabilities Strategy''
            WHEN ''Global Clearance Domain''                  THEN ''Global Clearance''
            WHEN ''Linehaul Domain''                          THEN ''Linehaul''
            WHEN ''MEISA Domain''                             THEN ''MEISA''
            WHEN ''Network 2.0 Domain''                       THEN ''Network 2.0''
            WHEN ''P&D Domain''                               THEN ''P&D''
            WHEN ''Platform Portfolio''                       THEN ''''
            WHEN ''Platforms Portfolio''                      THEN ''''
            WHEN ''Procurement Domain''                       THEN ''Procurement''
            WHEN ''Safety Domain''                            THEN ''Safety''
            WHEN ''Service Domain''                           THEN ''Service''
            WHEN ''SG&A Domain''                              THEN ''SG&A''
            WHEN ''Supply Chain Operations Portfolio''        THEN ''''
            WHEN ''Surface Fleet and Support Equipment Domain'' THEN ''Surface Fleet and Support Equipment''
            WHEN ''Surface Operations Domain''                THEN ''Surface Operations''
            WHEN ''Tricolor Domain''                          THEN ''Tricolor''
            ELSE [Demand Domain or Portfolio]
        END';

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Demand Domain or Portfolio')
    BEGIN
        SET @sql = N'
            DECLARE @cnt_ddp_i int;
            SELECT @cnt_ddp_i = COUNT(*) FROM ' + @tbl_iwork + N'
            WHERE LTRIM(RTRIM(ISNULL([Demand Domain or Portfolio], ''''))) <> ''''
              AND [Demand Domain or Portfolio] <> ' + @ddp_case + N';
            UPDATE ' + @tbl_iwork + N'
            SET [Demand Domain or Portfolio] = ' + @ddp_case + N'
            WHERE LTRIM(RTRIM(ISNULL([Demand Domain or Portfolio], ''''))) <> '''';
            INSERT INTO #changes VALUES (''init'', ''Demand Domain or Portfolio (old→new)'', @cnt_ddp_i);
        ';
        EXEC sp_executesql @sql;
    END

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = 'Demand Domain or Portfolio')
    BEGIN
        SET @sql = N'
            DECLARE @cnt_ddp_e int;
            SELECT @cnt_ddp_e = COUNT(*) FROM ' + @tbl_ework + N'
            WHERE LTRIM(RTRIM(ISNULL([Demand Domain or Portfolio], ''''))) <> ''''
              AND [Demand Domain or Portfolio] <> ' + @ddp_case + N';
            UPDATE ' + @tbl_ework + N'
            SET [Demand Domain or Portfolio] = ' + @ddp_case + N'
            WHERE LTRIM(RTRIM(ISNULL([Demand Domain or Portfolio], ''''))) <> '''';
            INSERT INTO #changes VALUES (''epic'', ''Demand Domain or Portfolio (old→new)'', @cnt_ddp_e);
        ';
        EXEC sp_executesql @sql;
    END

    -- ── Mapping 10: Is this confidential — Initiatives only ──────────────────
    -- Target name: Does this require Limited Visibility? (Wbs154)
    -- Column may be 'Is this confidential?' (with ?) if _sql_col() no longer strips ?
    -- or 'Is this confidential' (without ?) for backward compatibility.
    DECLARE @conf_col nvarchar(256);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Is this confidential?')
        SET @conf_col = N'Is this confidential?';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Is this confidential')
        SET @conf_col = N'Is this confidential';
    ELSE
        SET @conf_col = NULL;

    IF @conf_col IS NOT NULL
    BEGIN
        SET @sql = N'
            DECLARE @cnt_conf int;
            SELECT @cnt_conf = COUNT(*) FROM ' + @tbl_iwork + N'
            WHERE LTRIM(RTRIM(ISNULL(' + QUOTENAME(@conf_col) + N', ''''))) = ''Confidential'';
            UPDATE ' + @tbl_iwork + N'
            SET ' + QUOTENAME(@conf_col) + N' = CASE LTRIM(RTRIM(' + QUOTENAME(@conf_col) + N'))
                WHEN ''Confidential'' THEN ''Yes - Privileged & Confidential''
                ELSE ' + QUOTENAME(@conf_col) + N'
            END
            WHERE LTRIM(RTRIM(ISNULL(' + QUOTENAME(@conf_col) + N', ''''))) <> '''';
            INSERT INTO #changes VALUES (''init'', ''Is this confidential (Confidential→Yes - Privileged & Confidential)'', @cnt_conf);
        ';
        EXEC sp_executesql @sql;
    END

    -- ── Mapping 11: Lifecycle Status — Initiatives only ──────────────────────
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Lifecycle Status')
    BEGIN
        SET @sql = N'
            DECLARE @cnt_ls int;
            SELECT @cnt_ls = COUNT(*) FROM ' + @tbl_iwork + N'
            WHERE LTRIM(RTRIM(ISNULL([Lifecycle Status], ''''))) <> ''''
              AND [Lifecycle Status] <> CASE LTRIM(RTRIM([Lifecycle Status]))
                    WHEN ''Cancellation Request'' THEN ''Cancelled''
                    WHEN ''Completed''            THEN ''Completed/Closed''
                    ELSE [Lifecycle Status]
                END;
            UPDATE ' + @tbl_iwork + N'
            SET [Lifecycle Status] = CASE LTRIM(RTRIM([Lifecycle Status]))
                WHEN ''Cancellation Request'' THEN ''Cancelled''
                WHEN ''Completed''            THEN ''Completed/Closed''
                ELSE [Lifecycle Status]
            END
            WHERE LTRIM(RTRIM(ISNULL([Lifecycle Status], ''''))) <> '''';
            INSERT INTO #changes VALUES (''init'', ''Lifecycle Status (Cancellation Request→Cancelled, Completed→Completed/Closed)'', @cnt_ls);
        ';
        EXEC sp_executesql @sql;
    END

    -- ── Mapping 12: Governance Level — Epics only ────────────────────────────
    -- Field ID: Wbs86. Exists in Extract_Work_05.01.
    -- PEL → Portfolio Execution Leadership; Solution → blank (no value).
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = 'Governance Level')
    BEGIN
        SET @sql = N'
            DECLARE @cnt_gl int;
            SELECT @cnt_gl = COUNT(*) FROM ' + @tbl_ework + N'
            WHERE LTRIM(RTRIM(ISNULL([Governance Level], '''')))
                  IN (''PEL'', ''Solution'');
            UPDATE ' + @tbl_ework + N'
            SET [Governance Level] =
                CASE LTRIM(RTRIM([Governance Level]))
                    WHEN ''PEL''      THEN ''Portfolio Execution Leadership''
                    WHEN ''Solution'' THEN ''''
                    ELSE [Governance Level]
                END
            WHERE LTRIM(RTRIM(ISNULL([Governance Level], ''''))) <> '''';
            INSERT INTO #changes VALUES (''epic'', ''Governance Level (PEL→Portfolio Execution Leadership, Solution→blank)'', @cnt_gl);
        ';
        EXEC sp_executesql @sql;
    END

    -- ── Mapping 13: Task or Milestone Type — Tasks only ─────────────────────
    -- Field ID: Wbs712. Source sheet: Extract_Tasks. Order 99 in Transform_Logic_Prod.
    -- Maps old Milestone Type values to new Task or Milestone Type values.
    -- Column in extract is 'TASK OR MILESTONE TYPE' (all caps) — loaded via _sql_col()
    -- as 'TASK OR MILESTONE TYPE' (spaces preserved, no special chars to strip).
    DECLARE @tmt_col nvarchar(256);
    DECLARE @tmt_cols TABLE (col nvarchar(256));
    INSERT INTO @tmt_cols VALUES
        ('TASK OR MILESTONE TYPE'),
        ('Task or Milestone Type'),
        ('Milestone Type');

    DECLARE tmt CURSOR LOCAL FAST_FORWARD FOR SELECT col FROM @tmt_cols;
    OPEN tmt; FETCH NEXT FROM tmt INTO @tmt_col;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_twork) AND name = @tmt_col)
        BEGIN
            SET @sql = N'
                DECLARE @cnt_tmt int;
                SELECT @cnt_tmt = COUNT(*) FROM ' + @tbl_twork + N'
                WHERE LTRIM(RTRIM(ISNULL(' + QUOTENAME(@tmt_col) + N', ''''))) <> ''''
                  AND ' + QUOTENAME(@tmt_col) + N' <>
                    CASE LTRIM(RTRIM(' + QUOTENAME(@tmt_col) + N'))
                        WHEN ''Technology / Systems'' THEN ''Technology''
                        WHEN ''Finance''              THEN ''Other''
                        WHEN ''Legal''                THEN ''Legal / Regulatory''
                        WHEN ''Other dependency''     THEN ''Other''
                        ELSE ' + QUOTENAME(@tmt_col) + N'
                    END;
                UPDATE ' + @tbl_twork + N'
                SET ' + QUOTENAME(@tmt_col) + N' =
                    CASE LTRIM(RTRIM(' + QUOTENAME(@tmt_col) + N'))
                        WHEN ''Technology / Systems'' THEN ''Technology''
                        WHEN ''Finance''              THEN ''Other''
                        WHEN ''Legal''                THEN ''Legal / Regulatory''
                        WHEN ''Other dependency''     THEN ''Other''
                        ELSE ' + QUOTENAME(@tmt_col) + N'
                    END
                WHERE LTRIM(RTRIM(ISNULL(' + QUOTENAME(@tmt_col) + N', ''''))) <> '''';
                INSERT INTO #changes VALUES (''task'', ''Task or Milestone Type (old→new)'', @cnt_tmt);
            ';
            EXEC sp_executesql @sql;
        END
        FETCH NEXT FROM tmt INTO @tmt_col;
    END
    CLOSE tmt; DEALLOCATE tmt;

    -- ── Rename columns to target attribute names ─────────────────────────────
    -- Per Transform_Logic_Prod source → target attribute name mapping.
    -- Renaming done here so all result sets and output tables have target names.

    -- Initiatives renames
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Ability To Statements')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[Ability To Statements]'', ''Business Ability To Statements'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Baseline Fiscal Year of Initiative')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[Baseline Fiscal Year of Initiative]'', ''Baseline Fiscal Year of Work Bundle'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Brief Demand Description')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[Brief Demand Description]'', ''Description'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Impacts Data & AI Portfolio?')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[Impacts Data & AI Portfolio?]'', ''zz?Impacts Data & AI Portfolio?'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Impacts Value Prop or Risk to Customer Service?')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[Impacts Value Prop or Risk to Customer Service?]'', ''Impacts Value Prop or Risk to Customer?'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'L1 Net Recurring Benefits ($, annualized)-Soft')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[L1 Net Recurring Benefits ($, annualized)-Soft]'', ''Net Recurring Benefits -Soft'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Lifecycle Status')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[Lifecycle Status]'', ''Status'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Is this confidential?')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[Is this confidential?]'', ''Does this require Limited Visibility?'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Is this confidential')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[Is this confidential]'', ''Does this require Limited Visibility?'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Demand SubType')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[Demand SubType]'', ''*Risk Subtype (Does this request address a risk or requirement to one of the following?)'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Demand Domain or Portfolio')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[Demand Domain or Portfolio]'', ''What Business Unit does this request support?'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_iwork) AND name = 'Impacted Portfolios')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_iwork,'''','''''') + N'.[Impacted Portfolios]'', ''Other Impacted Portfolios'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END

    -- Epics renames
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = 'Governance Level')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_ework,'''','''''') + N'.[Governance Level]'', ''Level of Governance'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = 'Demand Domain or Portfolio')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_ework,'''','''''') + N'.[Demand Domain or Portfolio]'', ''What Business Unit does this request support?'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_ework) AND name = 'Impacted Portfolios')
    BEGIN
        SET @sql = N'EXEC sp_rename ''' + REPLACE(@tbl_ework,'''','''''') + N'.[Impacted Portfolios]'', ''Other Impacted Portfolios'', ''COLUMN''';
        EXEC sp_executesql @sql;
    END

    -- ── Return result sets to Python ─────────────────────────────────────────

    -- RS1: Mapped Initiatives (all cols — with target attribute names)
    SET @sql = N'SELECT * FROM ' + @tbl_iwork;
    EXEC sp_executesql @sql;

    -- RS2: Mapped Epics (all cols — with target attribute names)
    SET @sql = N'SELECT * FROM ' + @tbl_ework;
    EXEC sp_executesql @sql;

    -- RS3: Scalar counts (all 0 — no rows deleted or classified)
    SELECT 0 AS removed_in, 0 AS removed_ep, 0 AS new_id_count;

    -- RS4: Value mapping counts — Initiatives
    SELECT col, cnt FROM #changes WHERE source = 'init' AND cnt > 0 ORDER BY col;

    -- RS5: Value mapping counts — Epics
    SELECT col, cnt FROM #changes WHERE source = 'epic' AND cnt > 0 ORDER BY col;

    -- RS6: Mapped Tasks (all original cols)
    SET @sql = N'SELECT * FROM ' + @tbl_twork;
    EXEC sp_executesql @sql;

    -- ── Cleanup working copies ───────────────────────────────────────────────
    SET @sql = N'IF OBJECT_ID(''' + REPLACE(@tbl_iwork,'''','''''') + N''') IS NOT NULL DROP TABLE ' + @tbl_iwork;
    EXEC sp_executesql @sql;
    SET @sql = N'IF OBJECT_ID(''' + REPLACE(@tbl_ework,'''','''''') + N''') IS NOT NULL DROP TABLE ' + @tbl_ework;
    EXEC sp_executesql @sql;
    SET @sql = N'IF OBJECT_ID(''' + REPLACE(@tbl_twork,'''','''''') + N''') IS NOT NULL DROP TABLE ' + @tbl_twork;
    EXEC sp_executesql @sql;

END
GO
