/*
================================================================================
  Planview2026PlatinumStageVerification
================================================================================

  PURPOSE:
      Standalone verification of Flow_Type_Step1/Step2 derivation and Stage
      remapping logic (MAP_wbs28_stage table). Reads Initiatives raw input
      directly from the input Excel via Python.

  INPUTS (loaded by Python before calling this SP):
      [{@InputSchema}].[{@Stem}_Initiatives]   — raw Initiatives loaded from Excel

  PARAMETERS:
      @InputSchema   nvarchar(128)   schema where Python loaded the raw input
      @Stem          nvarchar(200)   table name stem

  RETURNS (1 result set):
      All original columns plus:
          Flow_Type_Step1   — Step 1 flow type (BC + SubType based)
          Flow_Type_Step2   — Step 2 flow type (resolves TBD via T-Shirt + EVR)
          Flow_Type_Final   — Final resolved flow type used for Stage remapping
          Stage_Remapped    — Remapped stage per MAP_wbs28_stage table

  DEPLOYMENT: Run once in SSMS — no parameters needed at deployment time.
================================================================================
*/

CREATE OR ALTER PROCEDURE dbo.Planview2026PlatinumStageVerification
    @InputSchema   nvarchar(128),
    @Stem          nvarchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @tbl_init  nvarchar(500),
        @tbl_work  nvarchar(500),
        @sql       nvarchar(MAX);

    SET @tbl_init = QUOTENAME(@InputSchema) + '.' + QUOTENAME(@Stem + '_Initiatives');
    SET @tbl_work = QUOTENAME(@InputSchema) + '.' + QUOTENAME(@Stem + '_Initiatives_StageVerify');

    -- ── Clone raw input into a working copy ──────────────────────────────────
    SET @sql = N'IF OBJECT_ID(''' + REPLACE(@tbl_work,'''','''''') + N''') IS NOT NULL DROP TABLE ' + @tbl_work;
    EXEC sp_executesql @sql;

    SET @sql = N'SELECT * INTO ' + @tbl_work + N' FROM ' + @tbl_init;
    EXEC sp_executesql @sql;

    -- ── Remove L0 and SL1 rows (not in migration scope) ─────────────────────
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work) AND name = 'Stage')
    BEGIN
        SET @sql = N'DELETE FROM ' + @tbl_work + N'
                     WHERE LTRIM(RTRIM(ISNULL([Stage], ''''))) IN (''A: L0'', ''B: SL1'');';
        EXEC sp_executesql @sql;
    END

    -- ── Resolve BC field expression ──────────────────────────────────────────
    -- _sql_col() strips '?' on load so check without '?' first.
    DECLARE @bc_expr nvarchar(500);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
               AND name = 'Is this request vital to business continuity')
        SET @bc_expr = N'LTRIM(RTRIM(ISNULL([Is this request vital to business continuity], '''')))';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
               AND name = 'Is this request vital to business continuity?')
        SET @bc_expr = N'LTRIM(RTRIM(ISNULL([Is this request vital to business continuity?], '''')))';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
                    AND name = 'Is this non-discretionary demand vital to business continuity')
        SET @bc_expr = N'LTRIM(RTRIM(ISNULL([Is this non-discretionary demand vital to business continuity], '''')))';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
                    AND name = 'Is this non-discretionary demand vital to business continuity?')
        SET @bc_expr = N'LTRIM(RTRIM(ISNULL([Is this non-discretionary demand vital to business continuity?], '''')))';
    ELSE
        SET @bc_expr = N'''''';

    -- ── Resolve Demand SubType expression ────────────────────────────────────
    -- Treat the string value 'None' as blank (same as null) in comparisons.
    DECLARE @dst_expr nvarchar(500);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
               AND name = 'Demand SubType')
        SET @dst_expr = N'CASE LTRIM(RTRIM(ISNULL([Demand SubType],''''))) WHEN ''None'' THEN '''' ELSE LTRIM(RTRIM(ISNULL([Demand SubType],''''))) END';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
                    AND name = 'Demand_SubType')
        SET @dst_expr = N'CASE LTRIM(RTRIM(ISNULL([Demand_SubType],''''))) WHEN ''None'' THEN '''' ELSE LTRIM(RTRIM(ISNULL([Demand_SubType],''''))) END';
    ELSE
        SET @dst_expr = N'''''';

    -- ── Resolve T-Shirt Size expression (str62) ──────────────────────────────
    DECLARE @tshirt_expr nvarchar(500);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
               AND name = 'T-Shirt Size')
        SET @tshirt_expr = N'LTRIM(RTRIM(ISNULL([T-Shirt Size], '''')))';
    ELSE
        SET @tshirt_expr = N'''''';

    -- ── Resolve NRB Exit Rate 2028 expression (C1281_strat) ─────────────────
    -- Column name after _sql_col() stripping: 'NRB Exit Rate 2028 Latest Estimate.'
    DECLARE @nrb_exit_expr nvarchar(500);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
               AND name = 'NRB Exit Rate 2028 Latest Estimate.')
        SET @nrb_exit_expr = N'TRY_CAST(NULLIF(LTRIM(RTRIM([NRB Exit Rate 2028 Latest Estimate.])),'''') AS float)';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
               AND name = 'NRB Exit Rate 2028 Latest Estimate')
        SET @nrb_exit_expr = N'TRY_CAST(NULLIF(LTRIM(RTRIM([NRB Exit Rate 2028 Latest Estimate])),'''') AS float)';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
               AND name = 'NRB (Exit Rate) 2028 (Latest Estimate).')
        SET @nrb_exit_expr = N'TRY_CAST(NULLIF(LTRIM(RTRIM([NRB (Exit Rate) 2028 (Latest Estimate).])),'''') AS float)';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
               AND name = 'NRB (Exit Rate) 2028 (Latest Estimate)')
        SET @nrb_exit_expr = N'TRY_CAST(NULLIF(LTRIM(RTRIM([NRB (Exit Rate) 2028 (Latest Estimate)])),'''') AS float)';
    ELSE
        SET @nrb_exit_expr = N'NULL';

    -- ── Resolve L1 NRB Hard expression (fdx_l1_nrb_hard) ────────────────────
    -- Column name after _sql_col() stripping: 'L1 Net Recurring Benefits $_ annualized-P&L_Hard'
    DECLARE @nrb_l1_expr nvarchar(500);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
               AND name = 'L1 Net Recurring Benefits $_ annualized-P&L_Hard')
        SET @nrb_l1_expr = N'TRY_CAST(NULLIF(LTRIM(RTRIM([L1 Net Recurring Benefits $_ annualized-P&L_Hard])),'''') AS float)';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
               AND name = 'L1 Net Recurring Benefits ($, annualized)-P&L/Hard')
        SET @nrb_l1_expr = N'TRY_CAST(NULLIF(LTRIM(RTRIM([L1 Net Recurring Benefits ($, annualized)-P&L/Hard])),'''') AS float)';
    ELSE
        SET @nrb_l1_expr = N'NULL';

    -- ── Resolve Estimated Annualized Value Range expression (WR36) ──────────
    DECLARE @evr_expr nvarchar(500);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work)
               AND name = 'Estimated Annualized Value Range')
        SET @evr_expr = N'LTRIM(RTRIM(ISNULL([Estimated Annualized Value Range], '''')))';
    ELSE
        SET @evr_expr = N'''''';

    -- ── Resolve Strategy Seq ID column ───────────────────────────────────────
    DECLARE @seq_col nvarchar(256);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work) AND name = 'Strategy Seq ID')
        SET @seq_col = N'[Strategy Seq ID]';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work) AND name = 'Seq ID')
        SET @seq_col = N'[Seq ID]';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@tbl_work) AND name = 'Work ID')
        SET @seq_col = N'[Work ID]';
    ELSE
        SET @seq_col = N'CAST([Run_ID] AS nvarchar(50))';


    -- ── Add Flow_Type_Step1, Step2, Final and Stage_Remapped columns ─────────
    SET @sql = N'ALTER TABLE ' + @tbl_work + N'
                 ADD [Flow_Type_Step1]  nvarchar(200) NULL,
                     [EVR_Step1]        nvarchar(50)  NULL,
                     [EVR_Step2]        nvarchar(50)  NULL,
                     [EVR_Step3]        nvarchar(50)  NULL,
                     [EVR_Consolidated] nvarchar(50)  NULL,
                     [Flow_Type_Step2]  nvarchar(200) NULL,
                     [Flow_Type_Final]  nvarchar(200) NULL,
                     [Stage_Remapped]   nvarchar(50)  NULL;';
    EXEC sp_executesql @sql;

    -- ── Compute Flow_Type_Step1 (Rule 1) ─────────────────────────────────────
    SET @sql = N'
    UPDATE ' + @tbl_work + N'
    SET [Flow_Type_Step1] = CASE
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business Only'',''Business Only Initiative'')
            THEN NULL
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
         AND UPPER(' + @bc_expr + N') = ''YES''
            THEN ''Non-Discretionary - Business Continuity''
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
         AND UPPER(' + @bc_expr + N') <> ''YES''
         AND ' + @dst_expr + N' IN (''Legal'',''Protect Purple'',''Infosec (Protect Purple)'',''Regulatory'')
            THEN ''Non-Discretionary - Run the Business''
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
         AND UPPER(' + @bc_expr + N') <> ''YES''
            THEN ''TBD - See additional logic''
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Local Enhancement'',''Local Enhancement Epic'')
            THEN ''Discretionary - Transformational Investment''
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Lifecycle Management'',''Lifecycle Management Epic'')
            THEN ''Non-Discretionary - Run the Business''
        ELSE NULL
    END;';
    EXEC sp_executesql @sql;

    -- ── Compute EVR Step 1 (Rule 2) — NRB Exit Rate 2028 ─────────────────────
    SET @sql = N'
    UPDATE ' + @tbl_work + N'
    SET [EVR_Step1] = CASE
        WHEN ' + @nrb_exit_expr + N' IS NULL        THEN ''1: Unknown''
        WHEN ' + @nrb_exit_expr + N' < 1000000      THEN ''1: Low = < $1M''
        WHEN ' + @nrb_exit_expr + N' < 10000000     THEN ''2: Medium = $1M < Value < $10M''
        ELSE                                              ''3: High = > $10M''
    END;';
    EXEC sp_executesql @sql;

    -- ── Compute EVR Step 2 (Rule 3) — L1 NRB Hard ────────────────────────────
    SET @sql = N'
    UPDATE ' + @tbl_work + N'
    SET [EVR_Step2] = CASE
        WHEN ' + @nrb_l1_expr + N' IS NULL          THEN ''1: Unknown''
        WHEN ' + @nrb_l1_expr + N' < 1000000        THEN ''1: Low = < $1M''
        WHEN ' + @nrb_l1_expr + N' < 10000000       THEN ''2: Medium = $1M < Value < $10M''
        ELSE                                              ''3: High = > $10M''
    END;';
    EXEC sp_executesql @sql;

    -- ── Compute EVR Step 3 (Rule 4) — Estimated Annualized Value Range ────────
    SET @sql = N'
    UPDATE ' + @tbl_work + N'
    SET [EVR_Step3] = CASE
        WHEN ' + @evr_expr + N' = ''''              THEN ''1: Unknown''
        ELSE ' + @evr_expr + N'
    END;';
    EXEC sp_executesql @sql;

    -- ── Compute EVR Consolidated (Rule 5) ─────────────────────────────────────
    SET @sql = N'
    UPDATE ' + @tbl_work + N'
    SET [EVR_Consolidated] = CASE
        WHEN [EVR_Step1] <> ''1: Unknown''                          THEN [EVR_Step1]
        WHEN [EVR_Step1] = ''1: Unknown'' AND [EVR_Step2] <> ''1: Unknown'' THEN [EVR_Step2]
        ELSE [EVR_Step3]
    END;';
    EXEC sp_executesql @sql;

    -- ── Compute Flow_Type_Step2 (Rule 6) — resolves TBD rows ─────────────────
    SET @sql = N'
    UPDATE ' + @tbl_work + N'
    SET [Flow_Type_Step2] = CASE
        WHEN [Flow_Type_Step1] = ''TBD - See additional logic''
         AND LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
         AND ' + @tshirt_expr + N' IN (''4: L'',''5: XL'')
         AND [EVR_Consolidated] = ''3: High = > $10M''
            THEN ''Discretionary - Transformational Investment''
        WHEN [Flow_Type_Step1] = ''TBD - See additional logic''
         AND LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
            THEN ''Discretionary - Other''
        WHEN [Flow_Type_Step1] = ''TBD - See additional logic''
            THEN ''ERROR - See additional logic''
        ELSE NULL
    END;';
    EXEC sp_executesql @sql;

    -- ── Compute Flow_Type_Final ───────────────────────────────────────────────
    SET @sql = N'
    UPDATE ' + @tbl_work + N'
    SET [Flow_Type_Final] = CASE
        WHEN [Flow_Type_Step1] = ''TBD - See additional logic''
            THEN ISNULL([Flow_Type_Step2], ''TBD - See additional logic'')
        ELSE [Flow_Type_Step1]
    END;';
    EXEC sp_executesql @sql;

    -- ── Compute Stage_Remapped using Flow_Type_Final ──────────────────────────
    -- All BwT branches now use Flow_Type_Final (fully resolved).
    SET @sql = N'
    UPDATE ' + @tbl_work + N'
    SET [Stage_Remapped] = CASE

        -- Business w/ Tech + Non-Disc BC
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
         AND [Flow_Type_Final] = ''Non-Discretionary - Business Continuity''
            THEN CASE LTRIM(RTRIM(ISNULL([Stage],'''')))
                WHEN ''C: L1'' THEN ''G: L3'' WHEN ''D: SL2'' THEN ''G: L3''
                WHEN ''E: L2'' THEN ''G: L3'' WHEN ''F: SL3'' THEN ''G: L3''
                WHEN ''G: L3'' THEN ''G: L3'' WHEN ''H: SL4'' THEN ''G: L3''
                WHEN ''I: L4'' THEN ''I: L4'' WHEN ''J: SL5'' THEN ''I: L4''
                WHEN ''K: L5'' THEN ''I: L4'' ELSE [Stage] END

        -- Business w/ Tech + Non-Disc Run Business
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
         AND [Flow_Type_Final] = ''Non-Discretionary - Run the Business''
            THEN CASE LTRIM(RTRIM(ISNULL([Stage],'''')))
                WHEN ''C: L1'' THEN ''C: L1'' WHEN ''D: SL2'' THEN ''G: L3''
                WHEN ''E: L2'' THEN ''G: L3'' WHEN ''F: SL3'' THEN ''G: L3''
                WHEN ''G: L3'' THEN ''G: L3'' WHEN ''H: SL4'' THEN ''G: L3''
                WHEN ''I: L4'' THEN ''I: L4'' WHEN ''J: SL5'' THEN ''I: L4''
                WHEN ''K: L5'' THEN ''I: L4'' ELSE [Stage] END

        -- Business w/ Tech + Disc Trans Inv
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
         AND [Flow_Type_Final] = ''Discretionary - Transformational Investment''
            THEN CASE LTRIM(RTRIM(ISNULL([Stage],'''')))
                WHEN ''C: L1'' THEN ''E: L2'' WHEN ''D: SL2'' THEN ''E: L2''
                WHEN ''E: L2'' THEN ''E: L2'' WHEN ''F: SL3'' THEN ''E: L2''
                WHEN ''G: L3'' THEN ''G: L3'' WHEN ''H: SL4'' THEN ''G: L3''
                WHEN ''I: L4'' THEN ''I: L4'' WHEN ''J: SL5'' THEN ''I: L4''
                WHEN ''K: L5'' THEN ''I: L4'' ELSE [Stage] END

        -- Business w/ Tech + Disc Other
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
         AND [Flow_Type_Final] = ''Discretionary - Other''
            THEN CASE LTRIM(RTRIM(ISNULL([Stage],'''')))
                WHEN ''C: L1'' THEN ''C: L1'' WHEN ''D: SL2'' THEN ''G: L3''
                WHEN ''E: L2'' THEN ''G: L3'' WHEN ''F: SL3'' THEN ''G: L3''
                WHEN ''G: L3'' THEN ''G: L3'' WHEN ''H: SL4'' THEN ''G: L3''
                WHEN ''I: L4'' THEN ''I: L4'' WHEN ''J: SL5'' THEN ''I: L4''
                WHEN ''K: L5'' THEN ''I: L4'' ELSE [Stage] END

        -- Business w/ Tech + ERROR flow type
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
         AND ISNULL([Flow_Type_Final],'''') LIKE ''%ERROR%''
            THEN ''ERROR - RESOLVE FLOW TYPE ISSUES''

        -- Local Enhancement + Non-Disc Run Business
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Local Enhancement'',''Local Enhancement Epic'')
         AND [Flow_Type_Final] = ''Non-Discretionary - Run the Business''
            THEN CASE LTRIM(RTRIM(ISNULL([Stage],'''')))
                WHEN ''C: L1'' THEN ''G: L3'' WHEN ''D: SL2'' THEN ''G: L3''
                WHEN ''E: L2'' THEN ''G: L3'' WHEN ''F: SL3'' THEN ''G: L3''
                WHEN ''G: L3'' THEN ''G: L3'' WHEN ''H: SL4'' THEN ''G: L3''
                WHEN ''I: L4'' THEN ''I: L4'' WHEN ''J: SL5'' THEN ''I: L4''
                WHEN ''K: L5'' THEN ''I: L4'' ELSE [Stage] END

        -- Local Enhancement + Disc Other
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Local Enhancement'',''Local Enhancement Epic'')
         AND [Flow_Type_Final] = ''Discretionary - Other''
            THEN CASE LTRIM(RTRIM(ISNULL([Stage],'''')))
                WHEN ''C: L1'' THEN ''G: L3'' WHEN ''D: SL2'' THEN ''G: L3''
                WHEN ''E: L2'' THEN ''G: L3'' WHEN ''F: SL3'' THEN ''G: L3''
                WHEN ''G: L3'' THEN ''G: L3'' WHEN ''H: SL4'' THEN ''G: L3''
                WHEN ''I: L4'' THEN ''I: L4'' WHEN ''J: SL5'' THEN ''I: L4''
                WHEN ''K: L5'' THEN ''I: L4'' ELSE [Stage] END

        -- Local Enhancement + Disc Trans Inv or other → ERROR
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Local Enhancement'',''Local Enhancement Epic'')
            THEN ''ERROR - Missing logic for LE/LM''

        -- Lifecycle Management + Non-Disc Run Business
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Lifecycle Management'',''Lifecycle Management Epic'')
         AND [Flow_Type_Final] = ''Non-Discretionary - Run the Business''
            THEN CASE LTRIM(RTRIM(ISNULL([Stage],'''')))
                WHEN ''C: L1'' THEN ''G: L3'' WHEN ''D: SL2'' THEN ''G: L3''
                WHEN ''E: L2'' THEN ''G: L3'' WHEN ''F: SL3'' THEN ''G: L3''
                WHEN ''G: L3'' THEN ''G: L3'' WHEN ''H: SL4'' THEN ''G: L3''
                WHEN ''I: L4'' THEN ''I: L4'' WHEN ''J: SL5'' THEN ''I: L4''
                WHEN ''K: L5'' THEN ''I: L4'' ELSE [Stage] END

        -- Lifecycle Management + Disc Other
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Lifecycle Management'',''Lifecycle Management Epic'')
         AND [Flow_Type_Final] = ''Discretionary - Other''
            THEN CASE LTRIM(RTRIM(ISNULL([Stage],'''')))
                WHEN ''C: L1'' THEN ''G: L3'' WHEN ''D: SL2'' THEN ''G: L3''
                WHEN ''E: L2'' THEN ''G: L3'' WHEN ''F: SL3'' THEN ''G: L3''
                WHEN ''G: L3'' THEN ''G: L3'' WHEN ''H: SL4'' THEN ''G: L3''
                WHEN ''I: L4'' THEN ''I: L4'' WHEN ''J: SL5'' THEN ''I: L4''
                WHEN ''K: L5'' THEN ''I: L4'' ELSE [Stage] END

        -- Lifecycle Management + other → ERROR
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Lifecycle Management'',''Lifecycle Management Epic'')
            THEN ''ERROR - Missing logic for LE/LM''

        -- Business Only + <ANY> — per Max updated mapping table
        -- C/D/E/F → E:L2 | G/H/I/J → G:L3 | K → I:L4
        WHEN LTRIM(RTRIM(ISNULL([Demand Type],''''))) IN (''Business Only'',''Business Only Initiative'')
            THEN CASE LTRIM(RTRIM(ISNULL([Stage],'''')))
                WHEN ''C: L1'' THEN ''E: L2'' WHEN ''D: SL2'' THEN ''E: L2''
                WHEN ''E: L2'' THEN ''E: L2'' WHEN ''F: SL3'' THEN ''E: L2''
                WHEN ''G: L3'' THEN ''G: L3'' WHEN ''H: SL4'' THEN ''G: L3''
                WHEN ''I: L4'' THEN ''G: L3'' WHEN ''J: SL5'' THEN ''G: L3''
                WHEN ''K: L5'' THEN ''I: L4'' ELSE [Stage] END

        ELSE ''ERROR - RESOLVE FLOW TYPE ISSUES''
    END
    WHERE LTRIM(RTRIM(ISNULL([Stage], ''''))) <> '''';';
    EXEC sp_executesql @sql;

    -- ── Return verification result set ───────────────────────────────────────
    SET @sql = N'
    SELECT *
    FROM ' + @tbl_work + N'
    ORDER BY
        ISNULL(LTRIM(RTRIM([Demand Type])), ''''),
        ISNULL([Flow_Type_Final], ''''),
        ISNULL(LTRIM(RTRIM([Stage])), '''');';
    EXEC sp_executesql @sql;

    -- ── Cleanup ──────────────────────────────────────────────────────────────
    SET @sql = N'IF OBJECT_ID(''' + REPLACE(@tbl_work,'''','''''') + N''') IS NOT NULL DROP TABLE ' + @tbl_work;
    EXEC sp_executesql @sql;

END
GO
