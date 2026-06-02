-- ============================================================
-- Stored Procedure : Consolidated_Transform_Logic
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.Consolidated_Transform_Logic
    @run_ts NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @input_schema  NVARCHAR(50)  = 'input_'  + @run_ts;
    DECLARE @output_schema NVARCHAR(50)  = 'output_' + @run_ts;
    DECLARE @sql           NVARCHAR(MAX);
    DECLARE @tbl           NVARCHAR(100);
    DECLARE @seq           NVARCHAR(200);
    DECLARE @pfx           NVARCHAR(50);
    DECLARE @cols          NVARCHAR(MAX);
    DECLARE @col           NVARCHAR(500);
    DECLARE @seq_done      BIT;

    -- ── Create output schema ─────────────────────────────────────────────────
    SET @sql = N'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'''
               + @output_schema + N''')
               EXEC(''CREATE SCHEMA [' + @output_schema + N']'')';
    EXEC sp_executesql @sql;


    -- ══════════════════════════════════════════════════════════════════════════
    -- INITIATIVES  — Index_ID = Prod-Init-XXXX
    -- ══════════════════════════════════════════════════════════════════════════
    SET @tbl      = 'Initiatives';
    SET @seq      = 'Strategy Seq ID';
    SET @pfx      = 'Prod-Init-';
    SET @cols     = N'';
    SET @seq_done = 0;

    DECLARE cur_init CURSOR LOCAL FAST_FORWARD FOR
        SELECT c.name
        FROM   sys.columns c
        JOIN   sys.objects o ON o.object_id = c.object_id
        JOIN   sys.schemas s ON s.schema_id = o.schema_id
        WHERE  s.name = @input_schema AND o.name = @tbl
        ORDER  BY c.column_id;

    OPEN cur_init;
    FETCH NEXT FROM cur_init INTO @col;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Skip [Stage] — replaced by remapped [Stage] column after SELECT INTO
        IF @col <> N'Stage'
            SET @cols = @cols + N'[' + @col + N'], ';
        IF @col = @seq AND @seq_done = 0
        BEGIN
            -- Order 0.1: inject Index_ID immediately after Strategy Seq ID
            SET @cols = @cols
                + N'CONCAT(N''' + @pfx + N''', RIGHT(N''0000'' + CAST('
                + N'ROW_NUMBER() OVER (ORDER BY TRY_CAST([' + @seq + N'] AS BIGINT), [' + @seq + N'])'
                + N' AS NVARCHAR(10)), 4)) AS [Index_ID], ';
            SET @seq_done = 1;
        END;
        FETCH NEXT FROM cur_init INTO @col;
    END;
    CLOSE cur_init; DEALLOCATE cur_init;

    -- ── Flow Type - Step 1 ──────────────────────────────────────────
    -- Business Only → NULL (spec shows <Null> in Flow Type - Step 1 col)
    -- Business w/ Tech, Local Enhancement, Lifecycle Management → per logic table
    SET @cols = @cols
        + N'CASE '
        + N'WHEN [Demand Type] = N''Business Only'' THEN NULL '
        + N'WHEN [Demand Type] = N''Business w/ Tech'' AND UPPER(ISNULL([Is this request vital to business continuity?],N'''')) = N''YES'' AND [Demand SubType] IN (N''Legal'',N''Protect Purple'',N''Regulatory'') THEN N''Non-Discretionary - Business Continuity'' '
        + N'WHEN [Demand Type] = N''Business w/ Tech'' AND UPPER(ISNULL([Is this request vital to business continuity?],N'''')) = N''YES'' AND ISNULL([Demand SubType],N''None'') IN (N''None'',N'''') THEN N''Non-Discretionary - Business Continuity'' '
        + N'WHEN [Demand Type] = N''Business w/ Tech'' AND UPPER(ISNULL([Is this request vital to business continuity?],N'''')) IN (N''NO'',N'''') AND [Demand SubType] IN (N''Legal'',N''Protect Purple'',N''Regulatory'') THEN N''Non-Discretionary - Run the Business'' '
        + N'WHEN [Demand Type] = N''Business w/ Tech'' AND UPPER(ISNULL([Is this request vital to business continuity?],N'''')) IN (N''NO'',N'''') AND ISNULL([Demand SubType],N''None'') IN (N''None'',N'''') THEN N''TBD - See additional logic'' '
        + N'WHEN [Demand Type] = N''Local Enhancement'' THEN N''Discretionary - Transformational Investment'' '
        + N'WHEN [Demand Type] = N''Lifecycle Management'' THEN N''Non-Discretionary - Run the Business'' '
        + N'ELSE NULL '
        + N'END AS [Flow Type - Step 1], ';

    -- ── Estimated Annualized Value Range_Step 1 ───────────────────
    -- Source: NRB (Exit Rate) 2028 (Latest Estimate). — field alias 1281
    -- Rule 2 (Flow Type Logic sheet, rows 22-25):
    --   <null>        → 1: Unknown
    --   < 1,000,000   → 1: Low = < $1M
    --    are still below $1M so map to 1: Low = < $1M, not Unknown)
    --   < 10,000,000  → 2: Medium = $1M < Value < $10M
    --   >= 10,000,000 → 3: High = > $10M
    SET @cols = @cols
        + N'CASE '
        + N'WHEN TRY_CAST([NRB (Exit Rate) 2028 (Latest Estimate).] AS DECIMAL(18,2)) IS NULL THEN N''1: Unknown'' '
        + N'WHEN TRY_CAST([NRB (Exit Rate) 2028 (Latest Estimate).] AS DECIMAL(18,2)) < 1000000 THEN N''1: Low = < $1M'' '
        + N'WHEN TRY_CAST([NRB (Exit Rate) 2028 (Latest Estimate).] AS DECIMAL(18,2)) < 10000000 THEN N''2: Medium = $1M < Value < $10M'' '
        + N'ELSE N''3: High = > $10M'' '
        + N'END AS [Estimated Annualized Value Range_Step 1], ';

    -- ── Estimated Annualized Value Range_Step 2 ───────────────────
    -- Source: L1 Net Recurring Benefits ($, annualized)-P&L/Hard
    SET @cols = @cols
        + N'CASE '
        + N'WHEN TRY_CAST([L1 Net Recurring Benefits ($, annualized)-P&L/Hard] AS DECIMAL(18,2)) IS NULL THEN N''1: Unknown'' '
        + N'WHEN TRY_CAST([L1 Net Recurring Benefits ($, annualized)-P&L/Hard] AS DECIMAL(18,2)) < 1000000 THEN N''1: Low = < $1M'' '
        + N'WHEN TRY_CAST([L1 Net Recurring Benefits ($, annualized)-P&L/Hard] AS DECIMAL(18,2)) < 10000000 THEN N''2: Medium = $1M < Value < $10M'' '
        + N'ELSE N''3: High = > $10M'' '
        + N'END AS [Estimated Annualized Value Range_Step 2], ';

    -- ── Estimated Annualized Value Range_Step 3 ───────────────────
    -- Source: Estimated Annualized Value Range (WR36) — passthrough or Unknown
    SET @cols = @cols
        + N'CASE '
        + N'WHEN [Estimated Annualized Value Range] IS NULL THEN N''1: Unknown'' '
        + N'ELSE [Estimated Annualized Value Range] '
        + N'END AS [Estimated Annualized Value Range_Step 3]';

    -- DROP + SELECT INTO
    SET @sql = N'IF OBJECT_ID(N''' + @output_schema + N'.Initiatives'', N''U'') IS NOT NULL
                     DROP TABLE [' + @output_schema + N'].[Initiatives]';
    EXEC sp_executesql @sql;

    SET @sql = N'SELECT ' + @cols
             + N' INTO [' + @output_schema + N'].[Initiatives]'
             + N' FROM [' + @input_schema  + N'].[Initiatives]';
    EXEC sp_executesql @sql;


    -- ══════════════════════════════════════════════════════════════════════════
    -- EPICS  — Index_ID = Prod-Epic-XXXX
    -- ══════════════════════════════════════════════════════════════════════════
    SET @tbl      = 'Epics';
    SET @seq      = 'Sequence ID';
    SET @pfx      = 'Prod-Epic-';
    SET @cols     = N'';
    SET @seq_done = 0;

    DECLARE cur_epics CURSOR LOCAL FAST_FORWARD FOR
        SELECT c.name
        FROM   sys.columns c
        JOIN   sys.objects o ON o.object_id = c.object_id
        JOIN   sys.schemas s ON s.schema_id = o.schema_id
        WHERE  s.name = @input_schema AND o.name = @tbl
        ORDER  BY c.column_id;

    OPEN cur_epics;
    FETCH NEXT FROM cur_epics INTO @col;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @cols = @cols + N'[' + @col + N'], ';
        IF @col = @seq AND @seq_done = 0
        BEGIN
            SET @cols = @cols
                + N'CONCAT(N''' + @pfx + N''', RIGHT(N''0000'' + CAST('
                + N'ROW_NUMBER() OVER (ORDER BY TRY_CAST([' + @seq + N'] AS BIGINT), [' + @seq + N'])'
                + N' AS NVARCHAR(10)), 4)) AS [Index_ID], ';
            SET @seq_done = 1;
        END;
        FETCH NEXT FROM cur_epics INTO @col;
    END;
    CLOSE cur_epics; DEALLOCATE cur_epics;

    SET @cols = LEFT(@cols, LEN(@cols) - 1);

    SET @sql = N'IF OBJECT_ID(N''' + @output_schema + N'.Epics'', N''U'') IS NOT NULL
                     DROP TABLE [' + @output_schema + N'].[Epics]';
    EXEC sp_executesql @sql;

    SET @sql = N'SELECT ' + @cols
             + N' INTO [' + @output_schema + N'].[Epics]'
             + N' FROM [' + @input_schema  + N'].[Epics]';
    EXEC sp_executesql @sql;


    -- ══════════════════════════════════════════════════════════════════════════
    -- VALUE BUNDLES  — Index_ID = SBA-VB-XXXX
    -- ══════════════════════════════════════════════════════════════════════════
    SET @tbl      = 'Value_Bundles';
    SET @seq      = 'Sequence ID';
    SET @pfx      = 'SBA-VB-';
    SET @cols     = N'';
    SET @seq_done = 0;

    DECLARE cur_vb CURSOR LOCAL FAST_FORWARD FOR
        SELECT c.name
        FROM   sys.columns c
        JOIN   sys.objects o ON o.object_id = c.object_id
        JOIN   sys.schemas s ON s.schema_id = o.schema_id
        WHERE  s.name = @input_schema AND o.name = @tbl
        ORDER  BY c.column_id;

    OPEN cur_vb;
    FETCH NEXT FROM cur_vb INTO @col;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @cols = @cols + N'[' + @col + N'], ';
        IF @col = @seq AND @seq_done = 0
        BEGIN
            SET @cols = @cols
                + N'CONCAT(N''' + @pfx + N''', RIGHT(N''0000'' + CAST('
                + N'ROW_NUMBER() OVER (ORDER BY TRY_CAST([' + @seq + N'] AS BIGINT), [' + @seq + N'])'
                + N' AS NVARCHAR(10)), 4)) AS [Index_ID], ';
            SET @seq_done = 1;
        END;
        FETCH NEXT FROM cur_vb INTO @col;
    END;
    CLOSE cur_vb; DEALLOCATE cur_vb;

    SET @cols = LEFT(@cols, LEN(@cols) - 1);

    SET @sql = N'IF OBJECT_ID(N''' + @output_schema + N'.Value_Bundles'', N''U'') IS NOT NULL
                     DROP TABLE [' + @output_schema + N'].[Value_Bundles]';
    EXEC sp_executesql @sql;

    SET @sql = N'SELECT ' + @cols
             + N' INTO [' + @output_schema + N'].[Value_Bundles]'
             + N' FROM [' + @input_schema  + N'].[Value_Bundles]';
    EXEC sp_executesql @sql;


    -- ══════════════════════════════════════════════════════════════════════════
    -- POST-SELECT INTO: Rule 5 + Rule 6 for Initiatives
    -- Each ALTER TABLE ADD and its UPDATE are in separate sp_executesql calls
    -- ══════════════════════════════════════════════════════════════════════════
    DECLARE @i NVARCHAR(200) = N'[' + @output_schema + N'].[Initiatives]';

    -- ── Rule 5: Estimated Value Range_Consolidated ────────────────────────────
    -- Priority 5.1: Step1 ≠ '1: Unknown' → use Step1
    -- Priority 5.2: Step1 = '1: Unknown' AND Step2 ≠ '1: Unknown' → use Step2
    -- Priority 5.3: Step1 = '1: Unknown' AND Step2 = '1: Unknown' → use Step3
    SET @sql = N'ALTER TABLE ' + @i + N' ADD [Estimated Value Range_Consolidated] NVARCHAR(200)';
    EXEC sp_executesql @sql;

    SET @sql = N'UPDATE ' + @i + N'
        SET [Estimated Value Range_Consolidated] =
            CASE
                WHEN ISNULL([Estimated Annualized Value Range_Step 1], N''1: Unknown'') <> N''1: Unknown''
                    THEN [Estimated Annualized Value Range_Step 1]
                WHEN ISNULL([Estimated Annualized Value Range_Step 2], N''1: Unknown'') <> N''1: Unknown''
                    THEN [Estimated Annualized Value Range_Step 2]
                ELSE [Estimated Annualized Value Range_Step 3]
            END';
    EXEC sp_executesql @sql;

    -- ── Rule 6: Flow Type (Final) ─────────────────────────────────────────────
    -- Uses: [Flow Type - Step 1], [Demand Type], [T-Shirt Size],
    --        [Estimated Value Range_Consolidated]
    -- Logic confirmed (rows 51-53 + catch-all):
    --   Row 51: TBD + BwT + L/XL + High → Discretionary - Transformational Investment
    --   Row 52: TBD + BwT + XS/S/M/null → Discretionary - Other
    --   Catch-all: TBD + BwT + anything else → Discretionary - Other
    --   Row 53: TBD + NOT Business w/ Tech → ERROR - See additional logic
    --   All other Step 1 values → NULL (no mapping defined in spec)
    SET @sql = N'ALTER TABLE ' + @i + N' ADD [Flow Type] NVARCHAR(200)';
    EXEC sp_executesql @sql;

    SET @sql = N'UPDATE ' + @i + N'
        SET [Flow Type] =
            CASE
                -- Row 51: TBD + Business w/ Tech + L/XL + High Value
                WHEN [Flow Type - Step 1] = N''TBD - See additional logic''
                 AND LTRIM(RTRIM([Demand Type])) = N''Business w/ Tech''
                 AND LTRIM(RTRIM(ISNULL([T-Shirt Size], N''''))) IN (N''4: L'', N''5: XL'')
                 AND LTRIM(RTRIM(ISNULL([Estimated Value Range_Consolidated], N'''')))
                     IN (N''3: High = > $10M'', N''4: High = > $10M'')
                    THEN N''Discretionary - Transformational Investment''

                -- Row 52: TBD + Business w/ Tech + XS/S/M/null T-Shirt
                WHEN [Flow Type - Step 1] = N''TBD - See additional logic''
                 AND LTRIM(RTRIM([Demand Type])) = N''Business w/ Tech''
                 AND LTRIM(RTRIM(ISNULL([T-Shirt Size], N'''')))
                     IN (N''1: XS'', N''2: S'', N''3: M'', N'''')
                    THEN N''Discretionary - Other''

                -- Catch-all confirmed: TBD + Business w/ Tech + anything
                -- else not matched above (e.g. L/XL + non-High) → Discretionary - Other
                WHEN [Flow Type - Step 1] = N''TBD - See additional logic''
                 AND LTRIM(RTRIM([Demand Type])) = N''Business w/ Tech''
                    THEN N''Discretionary - Other''

                -- Row 53: TBD + NOT Business w/ Tech → ERROR
                WHEN [Flow Type - Step 1] = N''TBD - See additional logic''
                 AND LTRIM(RTRIM([Demand Type])) <> N''Business w/ Tech''
                    THEN N''ERROR - See additional logic''

                -- Task 2: BC and RTB passthrough from Step 1 → Flow Type
                -- (confirmed by task assignment; platinum rows 61-62 list as valid values)
                WHEN [Flow Type - Step 1] = N''Non-Discretionary - Business Continuity''
                    THEN N''Non-Discretionary - Business Continuity''

                WHEN [Flow Type - Step 1] = N''Non-Discretionary - Run the Business''
                    THEN N''Non-Discretionary - Run the Business''

                -- All other Step 1 values → NULL
                ELSE NULL
            END';
    EXEC sp_executesql @sql;


    -- ══════════════════════════════════════════════════════════════════════════
    -- ORDER 20: Stage remapping (Initiatives only)
    -- Original [Stage] excluded from cursor SELECT above.
    -- New [Stage] added here with remapped values only.
    -- Uses COALESCE([Flow Type], [Flow Type - Step 1]) as resolved flow type.
    -- A:L0 and B:SL1 → Stage = NULL (rows kept, not deleted).
    -- Business Only mapping updated per Max: C/D/E/F→E:L2, G/H/I/J→G:L3, K→I:L4
    -- ══════════════════════════════════════════════════════════════════════════

    -- Step 1: Detect which BC (vital) column name exists in output table
    DECLARE @bc_col NVARCHAR(500);
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@i)
               AND name = 'Is this request vital to business continuity?')
        SET @bc_col = N'[Is this request vital to business continuity?]';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@i)
               AND name = 'Is this request vital to business continuity')
        SET @bc_col = N'[Is this request vital to business continuity]';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@i)
               AND name = 'Is this non-discretionary demand vital to business continuity?')
        SET @bc_col = N'[Is this non-discretionary demand vital to business continuity?]';
    ELSE IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@i)
               AND name = 'Is this non-discretionary demand vital to business continuity')
        SET @bc_col = N'[Is this non-discretionary demand vital to business continuity]';
    ELSE
        SET @bc_col = N'NULL';

    -- Step 2: ADD [Stage] as the remapped stage column
    -- (original [Stage] was excluded from cursor SELECT above)
    SET @sql = N'ALTER TABLE ' + @i + N' ADD [Stage] NVARCHAR(100)';
    EXEC sp_executesql @sql;

    -- Step 3: UPDATE [Stage] with remapped values
    -- Joins back to input table to get original Stage value since it was
    -- excluded from cursor SELECT and is not available in the output table.
    SET @sql = N'
    UPDATE out
    SET out.[Stage] =
        CASE

            -- A:L0 / B:SL1 → NULL (not in migration scope, rows kept)
            WHEN LTRIM(RTRIM(ISNULL(inp.[Stage],''''))) IN (''A: L0'',''B: SL1'')
                THEN NULL

            -- Business Only — updated mapping per Max
            -- C/D/E/F → E:L2  |  G/H/I/J → G:L3  |  K → I:L4
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Business Only'',''Business Only Initiative'')
                THEN CASE LTRIM(RTRIM(ISNULL(inp.[Stage],'''')))
                    WHEN ''C: L1''  THEN ''E: L2''
                    WHEN ''D: SL2'' THEN ''E: L2''
                    WHEN ''E: L2''  THEN ''E: L2''
                    WHEN ''F: SL3'' THEN ''E: L2''
                    WHEN ''G: L3''  THEN ''G: L3''
                    WHEN ''H: SL4'' THEN ''G: L3''
                    WHEN ''I: L4''  THEN ''G: L3''
                    WHEN ''J: SL5'' THEN ''G: L3''
                    WHEN ''K: L5''  THEN ''I: L4''
                    ELSE inp.[Stage] END

            -- Business w/ Tech + Non-Discretionary - Business Continuity
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
             AND COALESCE(NULLIF(LTRIM(RTRIM(out.[Flow Type])),''''),
                          NULLIF(LTRIM(RTRIM(out.[Flow Type - Step 1])),''''))
                 = ''Non-Discretionary - Business Continuity''
                THEN CASE LTRIM(RTRIM(ISNULL(inp.[Stage],'''')))
                    WHEN ''C: L1''  THEN ''G: L3''
                    WHEN ''D: SL2'' THEN ''G: L3''
                    WHEN ''E: L2''  THEN ''G: L3''
                    WHEN ''F: SL3'' THEN ''G: L3''
                    WHEN ''G: L3''  THEN ''G: L3''
                    WHEN ''H: SL4'' THEN ''G: L3''
                    WHEN ''I: L4''  THEN ''I: L4''
                    WHEN ''J: SL5'' THEN ''I: L4''
                    WHEN ''K: L5''  THEN ''I: L4''
                    ELSE inp.[Stage] END

            -- Business w/ Tech + Non-Discretionary - Run the Business
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
             AND COALESCE(NULLIF(LTRIM(RTRIM(out.[Flow Type])),''''),
                          NULLIF(LTRIM(RTRIM(out.[Flow Type - Step 1])),''''))
                 = ''Non-Discretionary - Run the Business''
                THEN CASE LTRIM(RTRIM(ISNULL(inp.[Stage],'''')))
                    WHEN ''C: L1''  THEN ''C: L1''
                    WHEN ''D: SL2'' THEN ''G: L3''
                    WHEN ''E: L2''  THEN ''G: L3''
                    WHEN ''F: SL3'' THEN ''G: L3''
                    WHEN ''G: L3''  THEN ''G: L3''
                    WHEN ''H: SL4'' THEN ''G: L3''
                    WHEN ''I: L4''  THEN ''I: L4''
                    WHEN ''J: SL5'' THEN ''I: L4''
                    WHEN ''K: L5''  THEN ''I: L4''
                    ELSE inp.[Stage] END

            -- Business w/ Tech + Discretionary - Transformational Investment
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
             AND COALESCE(NULLIF(LTRIM(RTRIM(out.[Flow Type])),''''),
                          NULLIF(LTRIM(RTRIM(out.[Flow Type - Step 1])),''''))
                 = ''Discretionary - Transformational Investment''
                THEN CASE LTRIM(RTRIM(ISNULL(inp.[Stage],'''')))
                    WHEN ''C: L1''  THEN ''E: L2''
                    WHEN ''D: SL2'' THEN ''E: L2''
                    WHEN ''E: L2''  THEN ''E: L2''
                    WHEN ''F: SL3'' THEN ''E: L2''
                    WHEN ''G: L3''  THEN ''G: L3''
                    WHEN ''H: SL4'' THEN ''G: L3''
                    WHEN ''I: L4''  THEN ''I: L4''
                    WHEN ''J: SL5'' THEN ''I: L4''
                    WHEN ''K: L5''  THEN ''I: L4''
                    ELSE inp.[Stage] END

            -- Business w/ Tech + Discretionary - Other
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
             AND COALESCE(NULLIF(LTRIM(RTRIM(out.[Flow Type])),''''),
                          NULLIF(LTRIM(RTRIM(out.[Flow Type - Step 1])),''''))
                 = ''Discretionary - Other''
                THEN CASE LTRIM(RTRIM(ISNULL(inp.[Stage],'''')))
                    WHEN ''C: L1''  THEN ''C: L1''
                    WHEN ''D: SL2'' THEN ''G: L3''
                    WHEN ''E: L2''  THEN ''G: L3''
                    WHEN ''F: SL3'' THEN ''G: L3''
                    WHEN ''G: L3''  THEN ''G: L3''
                    WHEN ''H: SL4'' THEN ''G: L3''
                    WHEN ''I: L4''  THEN ''I: L4''
                    WHEN ''J: SL5'' THEN ''I: L4''
                    WHEN ''K: L5''  THEN ''I: L4''
                    ELSE inp.[Stage] END

            -- Business w/ Tech + ERROR flow type
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Business w/ Tech'',''Business w/ Tech Initiative'')
             AND COALESCE(NULLIF(LTRIM(RTRIM(out.[Flow Type])),''''),
                          NULLIF(LTRIM(RTRIM(out.[Flow Type - Step 1])),'''')) LIKE ''%ERROR%''
                THEN ''ERROR - RESOLVE FLOW TYPE ISSUES''

            -- Local Enhancement + Non-Discretionary - Run the Business
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Local Enhancement'',''Local Enhancement Epic'')
             AND COALESCE(NULLIF(LTRIM(RTRIM(out.[Flow Type])),''''),
                          NULLIF(LTRIM(RTRIM(out.[Flow Type - Step 1])),''''))
                 = ''Non-Discretionary - Run the Business''
                THEN CASE LTRIM(RTRIM(ISNULL(inp.[Stage],'''')))
                    WHEN ''C: L1''  THEN ''G: L3''
                    WHEN ''D: SL2'' THEN ''G: L3''
                    WHEN ''E: L2''  THEN ''G: L3''
                    WHEN ''F: SL3'' THEN ''G: L3''
                    WHEN ''G: L3''  THEN ''G: L3''
                    WHEN ''H: SL4'' THEN ''G: L3''
                    WHEN ''I: L4''  THEN ''I: L4''
                    WHEN ''J: SL5'' THEN ''I: L4''
                    WHEN ''K: L5''  THEN ''I: L4''
                    ELSE inp.[Stage] END

            -- Local Enhancement + Discretionary - Other
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Local Enhancement'',''Local Enhancement Epic'')
             AND COALESCE(NULLIF(LTRIM(RTRIM(out.[Flow Type])),''''),
                          NULLIF(LTRIM(RTRIM(out.[Flow Type - Step 1])),''''))
                 = ''Discretionary - Other''
                THEN CASE LTRIM(RTRIM(ISNULL(inp.[Stage],'''')))
                    WHEN ''C: L1''  THEN ''G: L3''
                    WHEN ''D: SL2'' THEN ''G: L3''
                    WHEN ''E: L2''  THEN ''G: L3''
                    WHEN ''F: SL3'' THEN ''G: L3''
                    WHEN ''G: L3''  THEN ''G: L3''
                    WHEN ''H: SL4'' THEN ''G: L3''
                    WHEN ''I: L4''  THEN ''I: L4''
                    WHEN ''J: SL5'' THEN ''I: L4''
                    WHEN ''K: L5''  THEN ''I: L4''
                    ELSE inp.[Stage] END

            -- Local Enhancement + any other Flow Type → ERROR
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Local Enhancement'',''Local Enhancement Epic'')
                THEN ''ERROR - Missing logic for LE/LM''

            -- Lifecycle Management + Non-Discretionary - Run the Business
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Lifecycle Management'',''Lifecycle Management Epic'')
             AND COALESCE(NULLIF(LTRIM(RTRIM(out.[Flow Type])),''''),
                          NULLIF(LTRIM(RTRIM(out.[Flow Type - Step 1])),''''))
                 = ''Non-Discretionary - Run the Business''
                THEN CASE LTRIM(RTRIM(ISNULL(inp.[Stage],'''')))
                    WHEN ''C: L1''  THEN ''G: L3''
                    WHEN ''D: SL2'' THEN ''G: L3''
                    WHEN ''E: L2''  THEN ''G: L3''
                    WHEN ''F: SL3'' THEN ''G: L3''
                    WHEN ''G: L3''  THEN ''G: L3''
                    WHEN ''H: SL4'' THEN ''G: L3''
                    WHEN ''I: L4''  THEN ''I: L4''
                    WHEN ''J: SL5'' THEN ''I: L4''
                    WHEN ''K: L5''  THEN ''I: L4''
                    ELSE inp.[Stage] END

            -- Lifecycle Management + Discretionary - Other
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Lifecycle Management'',''Lifecycle Management Epic'')
             AND COALESCE(NULLIF(LTRIM(RTRIM(out.[Flow Type])),''''),
                          NULLIF(LTRIM(RTRIM(out.[Flow Type - Step 1])),''''))
                 = ''Discretionary - Other''
                THEN CASE LTRIM(RTRIM(ISNULL(inp.[Stage],'''')))
                    WHEN ''C: L1''  THEN ''G: L3''
                    WHEN ''D: SL2'' THEN ''G: L3''
                    WHEN ''E: L2''  THEN ''G: L3''
                    WHEN ''F: SL3'' THEN ''G: L3''
                    WHEN ''G: L3''  THEN ''G: L3''
                    WHEN ''H: SL4'' THEN ''G: L3''
                    WHEN ''I: L4''  THEN ''I: L4''
                    WHEN ''J: SL5'' THEN ''I: L4''
                    WHEN ''K: L5''  THEN ''I: L4''
                    ELSE inp.[Stage] END

            -- Lifecycle Management + any other Flow Type → ERROR
            WHEN LTRIM(RTRIM(ISNULL(out.[Demand Type],'''')))
                 IN (''Lifecycle Management'',''Lifecycle Management Epic'')
                THEN ''ERROR - Missing logic for LE/LM''

            -- All other Demand Types → NULL
            ELSE NULL
        END
    FROM ' + @i + N' AS out
    JOIN [' + @input_schema + N'].[Initiatives] AS inp
      ON out.[Index_ID] = CONCAT(N''Prod-Init-'', RIGHT(N''0000'' + CAST(
             ROW_NUMBER() OVER (ORDER BY TRY_CAST(inp.[Strategy Seq ID] AS BIGINT),
             inp.[Strategy Seq ID]) AS NVARCHAR(10)), 4))
    WHERE LTRIM(RTRIM(ISNULL(inp.[Stage],''''))) <> ''''';
    EXEC sp_executesql @sql;


    -- ── Return 3 result sets to Python (after all transformations) ────────────
    SET @sql = N'SELECT * FROM [' + @output_schema + N'].[Initiatives] ORDER BY [Index_ID]';
    EXEC sp_executesql @sql;

    SET @sql = N'SELECT * FROM [' + @output_schema + N'].[Epics] ORDER BY [Index_ID]';
    EXEC sp_executesql @sql;

    SET @sql = N'SELECT * FROM [' + @output_schema + N'].[Value_Bundles] ORDER BY [Index_ID]';
    EXEC sp_executesql @sql;

END;
GO
