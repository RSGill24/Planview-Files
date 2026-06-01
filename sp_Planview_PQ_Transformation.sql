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
    -- PQ: Add_Disposition_Stage_and_SBA + Remove_Disposition
    -- =========================================================================

    SET @sql = N'ALTER TABLE ' + @i + N' ADD [Disposition] NVARCHAR(100)';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE ' + @i + N'
    SET [Disposition] =
        CASE
            WHEN [Exclude from Migration] = N''Exclude''
                THEN N''Suppressed - Replaced by SBA''
            WHEN Stage_Remapped IN (N''A: L0'', N''B: SL1'')
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
    -- PQ: Add_SL3_EPG through Add_SL4_CloseWB_DnTFinance
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
        [SL3 EPG Approval]                            = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 Business Finance Approval]               = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [Ready for L3 EPM Quality Check?]             = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Yes''                  ELSE NULL END,
        [L3 EPM Review 1]                             = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Passed Quality Check'' ELSE NULL END,
        [Ready for L3 Epic Approval?]                 = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Yes''                  ELSE NULL END,
        [L3 Epic Approval]                            = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 Program Owner Approval]                  = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 D&T Captain Approval]                    = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 ESPM Review]                             = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 TO Approval]                             = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 D&T Finance Approval]                    = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 DTU Approval]                            = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [SL3 D&T SMO Review]                          = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Approved''             ELSE NULL END,
        [L3 ESPM Review]                              = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Passed Quality Check'' ELSE NULL END,
        [L3 D&T SMO Review]                           = CASE WHEN [Stage_Remapped] IN (N''G: L3'', N''I: L4'') THEN N''Passed Quality Check'' ELSE NULL END,
        [SL4 Close Work Bundle -D&T Finance Approval] = CASE WHEN [Stage_Remapped] =  N''I: L4''              THEN N''Approved''             ELSE NULL END';
    EXEC sp_executesql @sql;

    -- =========================================================================
    -- SECTION 3 — STATUS + WORK STATUS + LIMITED VISIBILITY  (Initiatives)
    -- PQ: Add_Status + Add_Work_Status + WR31_wbs154_Confidential
    -- =========================================================================

    SET @sql = N'
    ALTER TABLE ' + @i + N'
        ADD [Status]                                NVARCHAR(100),
            [Work Status]                           NVARCHAR(100),
            [Does this require Limited Visibility?] NVARCHAR(100)';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE ' + @i + N'
    SET
        [Status] =
            CASE [Lifecycle Status]
                WHEN N''Active''               THEN N''Active''
                WHEN N''Completed''            THEN N''Completed''
                WHEN N''Cancellation Request'' THEN N''Cancelled''
                WHEN N''Cancelled''            THEN N''Cancelled''
                WHEN N''Rejected''             THEN N''Rejected''
                WHEN N''On Hold''              THEN N''On Hold''
                ELSE N''ERROR''
            END,
        [Work Status] =
            CASE [Lifecycle Status]
                WHEN N''Active''               THEN N''Active''
                WHEN N''Completed''            THEN N''Completed/Closed''
                WHEN N''Cancellation Request'' THEN N''Cancelled''
                WHEN N''Cancelled''            THEN N''Cancelled''
                WHEN N''Rejected''             THEN N''Rejected''
                WHEN N''On Hold''              THEN N''On Hold''
                ELSE N''ERROR''
            END,
        [Does this require Limited Visibility?] =
            CASE [Is this confidential?]
                WHEN N''Confidential''       THEN N''Yes - Privileged & Confidential''
                WHEN N''Ultra-Confidential'' THEN N''Yes - Privileged & Confidential''
                WHEN N''No''                 THEN N''No''
                ELSE N''ERROR''
            END';
    EXEC sp_executesql @sql;

    -- =========================================================================
    -- SECTION 4 — OTHER IMPACTED PORTFOLIOS  (Initiatives)
    -- PQ: Add_Consolidated_ImpactsPlatformsColumn + Add Other Impacted Portfolios
    -- =========================================================================

    SET @sql = N'
    ALTER TABLE ' + @i + N'
        ADD [Other Impacted Portfolios] NVARCHAR(500)';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE ' + @i + N'
    SET [Other Impacted Portfolios] =
        STUFF(
            ISNULL(CASE WHEN [Impacts Commercial Portfolio?]              = N''Yes'' THEN N''|Commercial''              ELSE N'''' END, N'''')
          + ISNULL(CASE WHEN [Impacts Data & AI Portfolio?]               = N''Yes''
                          OR [Impacts Platform Portfolio?]                = N''Yes'' THEN N''|Platforms''               ELSE N'''' END, N'''')
          + ISNULL(CASE WHEN [Impacts Enterprise Services Portfolio?]     = N''Yes'' THEN N''|Enterprise Services''     ELSE N'''' END, N'''')
          + ISNULL(CASE WHEN [Impacts Supply Chain Operations Portfolio?] = N''Yes'' THEN N''|Supply Chain Operations'' ELSE N'''' END, N''''),
            1, 1, N''''
        )';
    EXEC sp_executesql @sql;

    -- =========================================================================
    -- SECTION 5 — EXECUTION TYPE REMAP  (Initiatives + Epics)
    -- PQ: Rename_DemandType_Legacy + Rename_ExecutionType_Legacy + Add_Execution_Type
    -- =========================================================================

    SET @sql = N'
    ALTER TABLE ' + @i + N'
        ADD [Demand Type - Legacy]    NVARCHAR(255),
            [Execution Type - Legacy] NVARCHAR(255),
            [Execution Type New]      NVARCHAR(255)';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE ' + @i + N'
    SET [Demand Type - Legacy]    = [Demand Type],
        [Execution Type - Legacy] = [Execution Type]';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE ' + @i + N'
    SET [Execution Type New] =
        CASE [Demand Type - Legacy]
            WHEN N''Business w/ Tech'' THEN N''D&T Value Bundle''
            WHEN N''Business Only''    THEN N''Business Demand''
            ELSE N''ERROR''
        END';
    EXEC sp_executesql @sql;

    SET @sql = N'
    ALTER TABLE ' + @e + N'
        ADD [Demand Type - Legacy]    NVARCHAR(255),
            [Execution Type - Legacy] NVARCHAR(255),
            [Execution Type New]      NVARCHAR(255)';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE ' + @e + N'
    SET [Demand Type - Legacy]    = [Demand Type],
        [Execution Type - Legacy] = [Execution Type]';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE ' + @e + N'
    SET [Execution Type New] =
        CASE [Execution Type - Legacy]
            WHEN N''Initiative Milestones & Risks'' THEN N''Architecture Task''
            ELSE N''Epic''
        END';
    EXEC sp_executesql @sql;

    -- =========================================================================
    -- SECTION 6 — PARENT SEQUENCE ID  (Initiatives)
    -- PQ: Add_Parent_Sequence_ID
    -- Reads from @WorkHierarchyTable
    -- =========================================================================

    SET @sql = N'
    ALTER TABLE ' + @i + N'
        ADD [Parent Sequence ID] NVARCHAR(255)';
    EXEC sp_executesql @sql;

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
                        CASE i.[Is this confidential?]
                            WHEN N''Confidential''        THEN N''C-D&T Cross-Portfolio Demand''
                            WHEN N''Ultra-Confidential''  THEN N''P&C-D&T Cross-Portfolio Demand''
                            ELSE                               N''D&T Cross-Portfolio Demand''
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
                CASE i.[Is this confidential?]
                    WHEN N''Confidential''        THEN N''C-Business Demand''
                    WHEN N''Ultra-Confidential''  THEN N''P&C-Business Demand''
                    ELSE                               N''Business Demand''
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

    -- =========================================================================
    -- SECTION 7 — EPIC PARENT RESOLUTION + FLOW TYPE INHERITANCE  (Epics)
    -- PQ: Prod_Epic_Transformations join chain
    -- Reads from @DevPPL1Table + output Initiatives (already transformed above)
    -- =========================================================================

    SET @sql = N'
    ALTER TABLE ' + @e + N'
        ADD [GrandParent Index]   NVARCHAR(255),
            [Parent Sequence ID]  NVARCHAR(255),
            [Inherited Flow Type] NVARCHAR(255),
            [Epic Flow Type]      NVARCHAR(255)';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE e
    SET e.[GrandParent Index] =
        CASE
            WHEN e.[Execution Type] IN (N''Lifecycle Management Epic'', N''Local Enhancement Epic'')
                THEN N''Prod-EpicLMLEPPL0-'' + CAST(e.[Sequence ID] AS NVARCHAR(50))
            WHEN e.[Associated Initiative Seq ID] IS NULL
                THEN N''N/A - No Parent Found''
            WHEN i.[Strategy Seq ID] IS NOT NULL
                THEN N''Prod-Init-'' + CAST(i.[Strategy Seq ID] AS NVARCHAR(50))
            ELSE N''ERROR-NO MATCH''
        END
    FROM ' + @e + N' e
    LEFT JOIN ' + @i + N' i
        ON CAST(i.[Strategy Seq ID] AS NVARCHAR(50)) = CAST(e.[Associated Initiative Seq ID] AS NVARCHAR(50))';
    EXEC sp_executesql @sql;

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

    SET @sql = N'
    UPDATE ' + @e + N'
    SET [Parent Sequence ID] = [GrandParent Index]
    WHERE [GrandParent Index] LIKE N''Prod-EpicLMLEPPL0%''';
    EXEC sp_executesql @sql;

    SET @sql = N'
    UPDATE e
    SET e.[Inherited Flow Type] = i.[Flow Type]
    FROM ' + @e + N' e
    LEFT JOIN ' + @i + N' i
        ON N''Prod-Init-'' + CAST(i.[Strategy Seq ID] AS NVARCHAR(50)) = e.[GrandParent Index]';
    EXEC sp_executesql @sql;

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
    -- Result set 1 = Initiatives (all columns + 7 new block columns)
    -- Result set 2 = Epics       (all columns + execution type + parent + flow type)
    -- Same pattern as SP2: SELECT * from output tables ordered by Index_ID
    -- =========================================================================

    SET @sql = N'SELECT * FROM ' + @i + N' ORDER BY [Index_ID]';
    EXEC sp_executesql @sql;

    SET @sql = N'SELECT * FROM ' + @e + N' ORDER BY [Index_ID]';
    EXEC sp_executesql @sql;

END;
GO
