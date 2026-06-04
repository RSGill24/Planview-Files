CREATE OR ALTER PROCEDURE dbo.usp_Planview_PQ_Transformation
    @run_ts             NVARCHAR(20),
    @WorkHierarchyTable NVARCHAR(256) = N'dbo.ref_WorkHierarchy',
    @DevPPL1Table       NVARCHAR(256) = N'dbo.ref_DevPPL1'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @output_schema NVARCHAR(50)  = N'output_' + @run_ts;
    DECLARE @i             NVARCHAR(200) = N'[' + @output_schema + N'].[Initiatives]';
    DECLARE @e             NVARCHAR(200) = N'[' + @output_schema + N'].[Epics]';
    DECLARE @sql           NVARCHAR(MAX);

    -- =========================================================================
    -- SECTION 1 — DISPOSITION + SBA SUPPRESSION  (Initiatives)
    -- Reads: [Exclude from Migration], [Stage]
    -- [Stage] in output_{ts} = SP2 remapped Stage (was Stage_Remapped in older SP)
    -- =========================================================================

    SET @sql = N'ALTER TABLE ' + @i + N' ADD [Disposition] NVARCHAR(100)';
    EXEC sp_executesql @sql;

    -- Detect [Exclude from Migration] column — name may vary by view
    DECLARE @excl_col NVARCHAR(500) = NULL;
    SET @sql = N'
        SELECT TOP 1 @excl_col = N''['' + c.name + N'']''
        FROM sys.columns c
        JOIN sys.objects o ON o.object_id = c.object_id
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE s.name = N''' + @output_schema + N'''
          AND o.name = N''Initiatives''
          AND (c.name LIKE N''%Exclude%Migration%'' OR c.name LIKE N''%Migration%Exclude%'')';
    EXEC sp_executesql @sql, N'@excl_col NVARCHAR(500) OUTPUT', @excl_col OUTPUT;
    IF @excl_col IS NULL SET @excl_col = N'NULL';

    SET @sql = N'
    UPDATE ' + @i + N'
    SET [Disposition] =
        CASE
            WHEN ' + @excl_col + N' = N''Exclude''
                THEN N''Suppressed - Replaced by SBA''
            WHEN [Stage] IN (N''A: L0'', N''B: SL1'')
                THEN N''Remove''
            ELSE NULL
        END';
    EXEC sp_executesql @sql;

    SET @sql = N'
    DELETE FROM ' + @i + N'
    WHERE [Disposition] = N''Remove''';
    EXEC sp_executesql @sql;

    -- =========================================================================
    -- SECTION 2 — 16 APPROVAL FIELDS  (Initiatives)
    -- Reads: [Stage]  (SP2 remapped Stage — column is named [Stage] in output)
    -- =========================================================================

    SET @sql = N'
    ALTER TABLE ' + @i + N'
        ADD [SL3 EPG Approval]                            NVARCHAR(100),
            [SL3 Business Finance Approval]               NVARCHAR(100),
            [Ready for L3 EPM Quality Check?]             NVARCHAR(10),
            [L3 EPM Review 1]                             NVARCHAR(100),
            [Ready for L3 Epic Approval?]                 NVARCHAR(10),
            [L3 Epic Approval]                            NVARCHAR(100),
            [SL3 Program Owner Approval]                  NVARCHAR(100),
            [SL3 D&T Captain Approval]                    NVARCHAR(100),
            [SL3 ESPM Review]                             NVARCHAR(100),
            [SL3 TO Approval]                             NVARCHAR(100),
            [SL3 D&T Finance Approval]                    NVARCHAR(100),
            [SL3 DTU Approval]                            NVARCHAR(100),
            [SL3 D&T SMO Review]                          NVARCHAR(100),
            [L3 ESPM Review]                              NVARCHAR(100),
            [L3 D&T SMO Review]                           NVARCHAR(100),
            [SL4 Close Work Bundle -D&T Finance Approval] NVARCHAR(100)';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE ' + @i + N'
    SET
        [SL3 EPG Approval]                            = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 Business Finance Approval]               = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [Ready for L3 EPM Quality Check?]             = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Yes''                  ELSE NULL END,
        [L3 EPM Review 1]                             = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Passed Quality Check'' ELSE NULL END,
        [Ready for L3 Epic Approval?]                 = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Yes''                  ELSE NULL END,
        [L3 Epic Approval]                            = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 Program Owner Approval]                  = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 D&T Captain Approval]                    = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 ESPM Review]                             = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 TO Approval]                             = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 D&T Finance Approval]                    = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 DTU Approval]                            = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 D&T SMO Review]                          = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [L3 ESPM Review]                              = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Passed Quality Check'' ELSE NULL END,
        [L3 D&T SMO Review]                           = CASE WHEN [Stage] IN (N''G: L3'', N''I: L4'') THEN N''Passed Quality Check'' ELSE NULL END,
        [SL4 Close Work Bundle -D&T Finance Approval] = CASE WHEN [Stage] =  N''I: L4''               THEN N''Approved''             ELSE NULL END';
    EXEC sp_executesql @sql;

    -- =========================================================================
    -- SECTION 3 — STATUS + WORK STATUS + LIMITED VISIBILITY  (Initiatives)
    -- Reads: [Lifecycle Status], [Is this confidential?]
    --
    -- SP1 renames [Lifecycle Status] → [Status] and
    --             [Is this confidential?] → [Does this require Limited Visibility?]
    -- on its work tables then merges into output_{ts} via Python merge step.
    -- Guard every ALTER TABLE ADD with IF NOT EXISTS so we do not fail
    -- if SP1 merge already wrote these columns.
    -- The UPDATE always runs regardless — it overwrites with the correct
    -- New SP logic which is more complete than SP1's partial mapping.
    -- =========================================================================

    SET @sql = N'
    IF NOT EXISTS (SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID(''' + @i + N''') AND name = N''Status'')
        ALTER TABLE ' + @i + N' ADD [Status] NVARCHAR(100);
    IF NOT EXISTS (SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID(''' + @i + N''') AND name = N''Work Status'')
        ALTER TABLE ' + @i + N' ADD [Work Status] NVARCHAR(100);
    IF NOT EXISTS (SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID(''' + @i + N''') AND name = N''Does this require Limited Visibility?'')
        ALTER TABLE ' + @i + N' ADD [Does this require Limited Visibility?] NVARCHAR(100);';
    EXEC sp_executesql @sql;

    -- Read from [Lifecycle Status] if it still exists (SP1 not yet merged),
    -- else fall back to [Status] which SP1 may have already renamed it to.
    SET @sql = N'
    UPDATE ' + @i + N'
    SET
        [Status] =
            CASE
                WHEN COALESCE([Lifecycle Status], [Status]) = N''Active''               THEN N''Active''
                WHEN COALESCE([Lifecycle Status], [Status]) = N''Completed''            THEN N''Completed''
                WHEN COALESCE([Lifecycle Status], [Status]) = N''Cancellation Request'' THEN N''Cancelled''
                WHEN COALESCE([Lifecycle Status], [Status]) = N''Cancelled''            THEN N''Cancelled''
                WHEN COALESCE([Lifecycle Status], [Status]) = N''Rejected''             THEN N''Rejected''
                WHEN COALESCE([Lifecycle Status], [Status]) = N''On Hold''              THEN N''On Hold''
                ELSE N''ERROR''
            END,
        [Work Status] =
            CASE
                WHEN COALESCE([Lifecycle Status], [Status]) = N''Active''               THEN N''Active''
                WHEN COALESCE([Lifecycle Status], [Status]) = N''Completed''            THEN N''Completed/Closed''
                WHEN COALESCE([Lifecycle Status], [Status]) = N''Cancellation Request'' THEN N''Cancelled''
                WHEN COALESCE([Lifecycle Status], [Status]) = N''Cancelled''            THEN N''Cancelled''
                WHEN COALESCE([Lifecycle Status], [Status]) = N''Rejected''             THEN N''Rejected''
                WHEN COALESCE([Lifecycle Status], [Status]) = N''On Hold''              THEN N''On Hold''
                ELSE N''ERROR''
            END';
    EXEC sp_executesql @sql;

    -- Limited Visibility — read from [Is this confidential?] if present,
    -- else from already-renamed [Does this require Limited Visibility?]
    SET @sql = N'
    UPDATE ' + @i + N'
    SET [Does this require Limited Visibility?] =
        CASE
            WHEN COALESCE([Is this confidential?],
                          [Does this require Limited Visibility?]) = N''Confidential''
                THEN N''Yes - Privileged & Confidential''
            WHEN COALESCE([Is this confidential?],
                          [Does this require Limited Visibility?]) = N''Ultra-Confidential''
                THEN N''Yes - Privileged & Confidential''
            WHEN COALESCE([Is this confidential?],
                          [Does this require Limited Visibility?]) = N''No''
                THEN N''No''
            ELSE N''ERROR''
        END';
    EXEC sp_executesql @sql;

    -- =========================================================================
    -- SECTION 4 — OTHER IMPACTED PORTFOLIOS  (Initiatives)
    -- SP1 renames [Impacted Portfolios] → [Other Impacted Portfolios].
    -- Guard ADD with IF NOT EXISTS — New SP builds the correct pipe-delimited
    -- string from the 5 flag columns regardless (overwrites SP1's simple rename).
    -- =========================================================================

    SET @sql = N'
    IF NOT EXISTS (SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID(''' + @i + N''') AND name = N''Other Impacted Portfolios'')
        ALTER TABLE ' + @i + N' ADD [Other Impacted Portfolios] NVARCHAR(500);';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE ' + @i + N'
    SET [Other Impacted Portfolios] =
        STUFF(
            ISNULL(CASE WHEN [Impacts Commercial Portfolio?]              = N''Yes'' THEN N''|Commercial''              ELSE N'''' END, N''''  )
          + ISNULL(CASE WHEN [Impacts Data & AI Portfolio?]               = N''Yes''
                          OR [Impacts Platform Portfolio?]                = N''Yes'' THEN N''|Platforms''               ELSE N'''' END, N''''  )
          + ISNULL(CASE WHEN [Impacts Enterprise Services Portfolio?]     = N''Yes'' THEN N''|Enterprise Services''     ELSE N'''' END, N''''  )
          + ISNULL(CASE WHEN [Impacts Supply Chain Operations Portfolio?] = N''Yes'' THEN N''|Supply Chain Operations'' ELSE N'''' END, N''''  ),
            1, 1, N''''
        )';
    EXEC sp_executesql @sql;

    -- =========================================================================
    -- SECTION 5 — EXECUTION TYPE REMAP  (Initiatives + Epics)
    -- [Demand Type - Legacy] and [Execution Type - Legacy] are pre-populated
    -- by Python merge step before this SP runs.
    -- This section only adds the columns if missing and derives [Execution Type New].
    -- =========================================================================

    -- Initiatives: add Legacy cols if not already there, derive New
    SET @sql = N'
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(''' + @i + N''') AND name = N''Demand Type - Legacy'')
        ALTER TABLE ' + @i + N' ADD [Demand Type - Legacy] NVARCHAR(255);
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(''' + @i + N''') AND name = N''Execution Type - Legacy'')
        ALTER TABLE ' + @i + N' ADD [Execution Type - Legacy] NVARCHAR(255);
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(''' + @i + N''') AND name = N''Execution Type New'')
        ALTER TABLE ' + @i + N' ADD [Execution Type New] NVARCHAR(255)';
    EXEC sp_executesql @sql;

    -- Populate Legacy from source columns using dynamic detection
    SET @sql = N'
    UPDATE t SET
        [Demand Type - Legacy]    = COALESCE([Demand Type - Legacy],    src.[Demand Type]),
        [Execution Type - Legacy] = COALESCE([Execution Type - Legacy], src.[Execution Type])
    FROM ' + @i + N' t
    CROSS APPLY (SELECT
        (SELECT TOP 1 val FROM (VALUES
            ((SELECT TOP 1 CAST(c.name AS SQL_VARIANT) FROM sys.columns c WHERE c.object_id = OBJECT_ID(''' + @i + N''') AND c.name LIKE N''%Demand Type%'' AND c.name NOT LIKE N''%Legacy%''))
        ) v(val)) AS [Demand Type],
        (SELECT TOP 1 val FROM (VALUES
            ((SELECT TOP 1 CAST(c.name AS SQL_VARIANT) FROM sys.columns c WHERE c.object_id = OBJECT_ID(''' + @i + N''') AND c.name LIKE N''%Execution Type%'' AND c.name NOT LIKE N''%Legacy%'' AND c.name NOT LIKE N''%New%''))
        ) v(val)) AS [Execution Type]
    ) src
    WHERE [Demand Type - Legacy] IS NULL OR [Execution Type - Legacy] IS NULL';

    -- Simpler approach: just use direct column names with TRY
    SET @sql = N'
    UPDATE ' + @i + N' SET
        [Demand Type - Legacy]    = COALESCE([Demand Type - Legacy],    [Demand Type]),
        [Execution Type - Legacy] = COALESCE([Execution Type - Legacy], [Execution Type])
    WHERE [Demand Type - Legacy] IS NULL OR [Execution Type - Legacy] IS NULL';
    BEGIN TRY EXEC sp_executesql @sql; END TRY BEGIN CATCH END CATCH;

    SET @sql = N'
    UPDATE ' + @i + N'
    SET [Execution Type New] =
        CASE [Demand Type - Legacy]
            WHEN N''Business w/ Tech'' THEN N''D&T Value Bundle''
            WHEN N''Business Only''    THEN N''Business Demand''
            ELSE N''ERROR''
        END
    WHERE [Execution Type New] IS NULL';
    EXEC sp_executesql @sql;

    -- Epics: same pattern
    SET @sql = N'
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(''' + @e + N''') AND name = N''Demand Type - Legacy'')
        ALTER TABLE ' + @e + N' ADD [Demand Type - Legacy] NVARCHAR(255);
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(''' + @e + N''') AND name = N''Execution Type - Legacy'')
        ALTER TABLE ' + @e + N' ADD [Execution Type - Legacy] NVARCHAR(255);
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(''' + @e + N''') AND name = N''Execution Type New'')
        ALTER TABLE ' + @e + N' ADD [Execution Type New] NVARCHAR(255)';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE ' + @e + N' SET
        [Demand Type - Legacy]    = COALESCE([Demand Type - Legacy],    [Demand Type]),
        [Execution Type - Legacy] = COALESCE([Execution Type - Legacy], [Execution Type])
    WHERE [Demand Type - Legacy] IS NULL OR [Execution Type - Legacy] IS NULL';
    BEGIN TRY EXEC sp_executesql @sql; END TRY BEGIN CATCH END CATCH;

    SET @sql = N'
    UPDATE ' + @e + N'
    SET [Execution Type New] =
        CASE [Execution Type - Legacy]
            WHEN N''Initiative Milestones & Risks'' THEN N''Architecture Task''
            ELSE N''Epic''
        END
    WHERE [Execution Type New] IS NULL';
    EXEC sp_executesql @sql;

    -- =========================================================================
    -- SECTION 6 — PARENT SEQUENCE ID  (Initiatives)
    -- Reads: [Demand Type], [Is this confidential?],
    --        [What Business Unit does this request support?], [Strategy Seq ID]
    -- Joins to @WorkHierarchyTable
    -- No conflicts — [Parent Sequence ID] is a new column.
    -- =========================================================================

    SET @sql = N'
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(''' + @i + N''') AND name = N''Parent Sequence ID'')
        ALTER TABLE ' + @i + N' ADD [Parent Sequence ID] NVARCHAR(255)';
    EXEC sp_executesql @sql;

    -- Check if WorkHierarchy table exists before attempting join
    IF OBJECT_ID(@WorkHierarchyTable) IS NOT NULL
    BEGIN

    SET @sql = N'
    ;WITH
    CTE_FixedNode AS (
        SELECT
            i.[Strategy Seq ID],
            wh.[Normalized_Sequence_ID] AS ParentSeqID
        FROM ' + @i + N' i
        LEFT JOIN ' + @WorkHierarchyTable + N' wh
            ON wh.[Normalized_Name] =
                CASE
                    WHEN i.[Demand Type] IN (N''Business w/ Tech'', N''Local Enhancement'', N''Lifecycle Management'')
                    THEN
                        CASE
                            WHEN COALESCE(i.[Is this confidential?],
                                          i.[Does this require Limited Visibility?]) = N''Confidential''
                                THEN N''C-D&T Cross-Portfolio Demand''
                            WHEN COALESCE(i.[Is this confidential?],
                                          i.[Does this require Limited Visibility?]) = N''Ultra-Confidential''
                                THEN N''P&C-D&T Cross-Portfolio Demand''
                            ELSE N''D&T Cross-Portfolio Demand''
                        END
                    ELSE NULL
                END
        WHERE i.[Demand Type] IN (N''Business w/ Tech'', N''Local Enhancement'', N''Lifecycle Management'')
    ),
    CTE_BusinessOnly AS (
        SELECT
            i.[Strategy Seq ID],
            wh.[Normalized_Sequence_ID] AS ParentSeqID
        FROM ' + @i + N' i
        LEFT JOIN ' + @WorkHierarchyTable + N' wh
            ON wh.[Lvl2] =
                CASE
                    WHEN COALESCE(i.[Is this confidential?],
                                  i.[Does this require Limited Visibility?]) = N''Confidential''
                        THEN N''C-Business Demand''
                    WHEN COALESCE(i.[Is this confidential?],
                                  i.[Does this require Limited Visibility?]) = N''Ultra-Confidential''
                        THEN N''P&C-Business Demand''
                    ELSE N''Business Demand''
                END
           AND wh.[Normalized_Name] = i.[What Business Unit does this request support?]
        WHERE i.[Demand Type] = N''Business Only''
    )
    UPDATE i
    SET i.[Parent Sequence ID] =
        CASE
            WHEN i.[Demand Type] IN (N''Business w/ Tech'', N''Local Enhancement'', N''Lifecycle Management'')
                THEN ISNULL(fn.ParentSeqID, N''ERROR - No Matching Hierarchy Node'')
            WHEN i.[Demand Type] = N''Business Only''
                THEN ISNULL(bo.ParentSeqID, N''ERROR - No Matching BU'')
            ELSE N''ERROR - Unmapped Demand Type''
        END
    FROM ' + @i + N' i
    LEFT JOIN CTE_FixedNode    fn ON fn.[Strategy Seq ID] = i.[Strategy Seq ID]
    LEFT JOIN CTE_BusinessOnly bo ON bo.[Strategy Seq ID] = i.[Strategy Seq ID]';
    EXEC sp_executesql @sql;

    END -- WorkHierarchy exists check
    ELSE
    BEGIN
        -- ref_WorkHierarchy not loaded — set ERROR flag, do not crash
        SET @sql = N'UPDATE ' + @i + N' SET [Parent Sequence ID] = N''ERROR - ref_WorkHierarchy not loaded'' WHERE [Parent Sequence ID] IS NULL';
        EXEC sp_executesql @sql;
    END;

    -- =========================================================================
    -- SECTION 7 — EPIC PARENT RESOLUTION + FLOW TYPE INHERITANCE  (Epics)
    -- Reads from @DevPPL1Table and output Initiatives (already transformed above)
    -- No conflicts — all 4 columns are new.
    -- =========================================================================

    SET @sql = N'
    ALTER TABLE ' + @e + N'
        ADD [GrandParent Index]   NVARCHAR(255),
            [Parent Sequence ID]  NVARCHAR(255),
            [Inherited Flow Type] NVARCHAR(255),
            [Epic Flow Type]      NVARCHAR(255)';
    EXEC sp_executesql @sql;

    -- Step A: Derive GrandParent Index
    SET @sql = N'
    UPDATE e
    SET e.[GrandParent Index] =
        CASE
            WHEN e.[Execution Type - Legacy] IN (N''Lifecycle Management Epic'', N''Local Enhancement Epic'')
                THEN N''Prod-EpicLMLEPPL0-'' + CAST(e.[Sequence ID] AS NVARCHAR(50))
            WHEN e.[Associated Initiative Seq ID] IS NULL
                THEN N''N/A - No Parent Found''
            WHEN i.[Strategy Seq ID] IS NOT NULL
                THEN N''Prod-Init-'' + CAST(i.[Strategy Seq ID] AS NVARCHAR(50))
            ELSE N''ERROR-NO MATCH''
        END
    FROM ' + @e + N' e
    LEFT JOIN ' + @i + N' i
        ON CAST(i.[Strategy Seq ID] AS NVARCHAR(50))
         = CAST(e.[Associated Initiative Seq ID] AS NVARCHAR(50))';
    EXEC sp_executesql @sql;

    -- Step B: Resolve Parent Sequence ID from Dev PPL+1 (standard Epics)
    IF OBJECT_ID(@DevPPL1Table) IS NOT NULL
    BEGIN
        SET @sql = N'
        UPDATE e
        SET e.[Parent Sequence ID] =
            CASE
                WHEN e.[GrandParent Index] LIKE N''N/A%''  THEN e.[GrandParent Index]
                WHEN p.[Sequence_ID] IS NOT NULL           THEN p.[Sequence_ID]
                ELSE N''ERROR-NO PPL1 MATCH''
            END
        FROM ' + @e + N' e
        LEFT JOIN ' + @DevPPL1Table + N' p
            ON p.[Previous_Seq_ID] = e.[GrandParent Index]
        WHERE e.[GrandParent Index] NOT LIKE N''Prod-EpicLMLEPPL0%''';
        EXEC sp_executesql @sql;
    END
    ELSE
    BEGIN
        -- ref_DevPPL1 not loaded — set ERROR flag, do not crash
        SET @sql = N'UPDATE ' + @e + N' SET [Parent Sequence ID] = N''ERROR - ref_DevPPL1 not loaded'' WHERE [Parent Sequence ID] IS NULL AND [GrandParent Index] NOT LIKE N''Prod-EpicLMLEPPL0%''';
        EXEC sp_executesql @sql;
    END;

    -- Step B (continued): LM/LE Epics — GrandParent IS the parent at PPL+0
    SET @sql = N'
    UPDATE ' + @e + N'
    SET [Parent Sequence ID] = [GrandParent Index]
    WHERE [GrandParent Index] LIKE N''Prod-EpicLMLEPPL0%''';
    EXEC sp_executesql @sql;

    -- Step C: Inherit Flow Type from parent Initiative
    SET @sql = N'
    UPDATE e
    SET e.[Inherited Flow Type] = i.[Flow Type]
    FROM ' + @e + N' e
    LEFT JOIN ' + @i + N' i
        ON N''Prod-Init-'' + CAST(i.[Strategy Seq ID] AS NVARCHAR(50)) = e.[GrandParent Index]';
    EXEC sp_executesql @sql;

    -- Step C (continued): Derive final Epic Flow Type
    -- LM/LE Epics get hardcoded Flow Type; all others inherit from Initiative
    SET @sql = N'
    UPDATE ' + @e + N'
    SET [Epic Flow Type] =
        CASE [Execution Type - Legacy]
            WHEN N''Lifecycle Management Epic'' THEN N''Non-Discretionary - Run the Business''
            WHEN N''Local Enhancement Epic''    THEN N''Discretionary - Other''
            ELSE [Inherited Flow Type]
        END';
    EXEC sp_executesql @sql;

    -- =========================================================================
    -- RETURN RESULT SETS TO PYTHON
    -- RS1 = Initiatives — all original SP2 columns + SP1 merged columns
    --                     + all 7 New SP PQ block columns
    -- RS2 = Epics       — all original SP2 columns + SP1 merged columns
    --                     + Execution Type remap + Parent resolution + Flow Type
    -- Ordered by Index_ID to match SP2 pattern
    -- =========================================================================

    SET @sql = N'SELECT * FROM ' + @i + N' ORDER BY [Index_ID]';
    EXEC sp_executesql @sql;

    SET @sql = N'SELECT * FROM ' + @e + N' ORDER BY [Index_ID]';
    EXEC sp_executesql @sql;

END;
GO
