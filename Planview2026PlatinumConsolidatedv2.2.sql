-- ============================================================
-- Stored Procedure : dbo.Planview2026PlatinumConsolidatedv2
-- Description      : Applies Rajinder transformation logic
--                    (26 blocks) to Prod Initiatives, Epics
--                    and Tasks sourced from SQL Server views.
--                    Writes results to 3 dbo staging tables.
-- Source Views      : ip.FDXPROD_initiatives_extract
--                     ip.FDXPROD_epics_extract
--                     ip.FDXPROD_tasks_extract
-- Output Staging   : dbo.stg_prod_init
--                    dbo.stg_prod_epic
--                    dbo.stg_prod_task
-- Author           : Rajinder
-- Version          : v2.0
-- Date             : 2026-06-10
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.Planview2026PlatinumConsolidatedv2
AS
BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    PRINT '======================================================';
    PRINT 'Planview2026PlatinumConsolidatedv2 — START';
    PRINT CONVERT(VARCHAR, GETDATE(), 120);
    PRINT '======================================================';

    -- ============================================================
    -- SECTION 1 : PROD INITIATIVES
    -- Source      : ip.FDXPROD_initiatives_extract
    -- Tracker IDs : Prod-Init-002, -003, -004, -019, -020,
    --               -026, -030, -032, -033
    -- ============================================================

    PRINT '';
    PRINT '-- SECTION 1: Prod Initiatives';

    IF OBJECT_ID('dbo.stg_prod_init', 'U') IS NOT NULL
        DROP TABLE dbo.stg_prod_init;

    SELECT

        -- ── Prod-Init-002 : Type Cast ──────────────────────────
        -- ID fields → NVARCHAR; financial fields → BIGINT
        CAST([Strategy Seq ID]                                          AS NVARCHAR(50))     AS [Strategy Seq ID],
        CAST([EAI #]                                                    AS NVARCHAR(50))     AS [EAI #],

        CAST(ISNULL([L1 Net Recurring Benefits ($, annualized)-P&L/Hard], 0)
                                                                        AS BIGINT)           AS [L1 Net Recurring Benefits ($, annualized)-P&L/Hard],
        CAST(ISNULL([L1 Net Recurring Benefits ($, annualized)-Soft], 0)
                                                                        AS BIGINT)           AS [L1 Net Recurring Benefits ($, annualized)-Soft],
        CAST(ISNULL([L2 Net Recurring Benefits ($, annualized)-P&L/Hard], 0)
                                                                        AS BIGINT)           AS [L2 Net Recurring Benefits ($, annualized)-P&L/Hard],
        CAST(ISNULL([NRB (Exit Rate) 2028 (Latest Estimate)], 0)
                                                                        AS BIGINT)           AS [NRB (Exit Rate) 2028 (Latest Estimate)],
        CAST(ISNULL([L1 One-time Benefit ($)], 0)
                                                                        AS BIGINT)           AS [L1 One-time Benefit ($)],

        -- ── Prod-Init-003 : Prod_Init_Rename ──────────────────
        -- Hardcoded Old → New column aliases
        [Name]                                                                               AS [Work Name],
        [Lifecycle Status]                                                                   AS [Lifecycle Status],
        [Stage]                                                                              AS [Stage],
        [Demand Type]                                                                        AS [Demand Type],
        [Demand SubType]                                                                     AS [Demand SubType],
        [Execution Type]                                                                     AS [Execution Type],
        [Initiative Owner]                                                                   AS [Initiative Owner],
        [Is this confidential?]                                                              AS [Is this confidential?],
        [Exclude from Migration]                                                             AS [Exclude from Migration],
        [Home Portfolio]                                                                     AS [Home Portfolio],
        [Demand Domain or Portfolio]                                                         AS [Demand Domain or Portfolio],
        [T-Shirt Size]                                                                       AS [T-Shirt Size],
        [Estimated Annualized Value Range]                                                   AS [Estimated Annualized Value Range],
        [Primary Type of Value]                                                              AS [Primary Type of Value],
        -- Note: view has [Is this request vital to business continuity?]
        -- PQ uses [Is this non-discretionary demand vital to business continuity?]
        -- Mapping to correct source column name from view
        [Is this request vital to business continuity?]                                      AS [Is this non-discretionary demand vital to business continuity?],
        [Impacts Data & AI Portfolio?]                                                       AS [Impacts Data & AI Portfolio?],
        [Impacts Platform Portfolio?]                                                        AS [Impacts Platform Portfolio?],
        [Impacts Commercial Portfolio?]                                                      AS [Impacts Commercial Portfolio?],
        [Impacts Enterprise Services Portfolio?]                                             AS [Impacts Enterprise Services Portfolio?],
        [Impacts Supply Chain Operations Portfolio?]                                         AS [Impacts Supply Chain Operations Portfolio?],
        [Health Status]                                                                      AS [Health Status],
        [Status Rationale]                                                                   AS [Status Rationale],
        [Sponsor Name]                                                                       AS [Sponsor Name],
        [Expected Business Outcome]                                                          AS [Expected Business Outcome],
        [Brief Demand Description]                                                           AS [Brief Demand Description],
        [PPM Project Number]                                                                 AS [PPM Project Number],
        [Investment Dependencies]                                                            AS [Investment Dependencies],
        [Triage Comments]                                                                    AS [Triage Comments],
        [Key Assumptions Made in Quantifying Impact]                                         AS [Key Assumptions Made in Quantifying Impact],
        [EPM]                                                                                AS [EPM],
        [Domain]                                                                             AS [Domain],
        [Meta Domain]                                                                        AS [Meta Domain],
        [OnSpring ID]                                                                        AS [OnSpring ID],

        -- ── Prod-Init-004 : AddSourceColumn ───────────────────
        'Prod-Init'                                                                          AS [Data Source],

        -- Index key
        'Prod-Init-' + CAST([Strategy Seq ID] AS NVARCHAR(50))                              AS [Index],

        -- ── Prod-Init-019 : Add_Consolidated_ImpactsPlatformsColumn ──
        -- Data & AI = Yes OR Platform = Yes → 'Yes' ELSE NULL
        CASE
            WHEN [Impacts Data & AI Portfolio?]  = 'Yes'
              OR [Impacts Platform Portfolio?]   = 'Yes'
            THEN 'Yes'
            ELSE NULL
        END                                                                                  AS [Impacts Platforms Portfolio?],

        -- ── Prod-Init-020 : Add Other Impacted Portfolios ─────
        -- 4 flag columns → pipe-delimited string
        -- Uses new consolidated Platforms col (not old Data & AI)
        NULLIF(
            STUFF(
                ISNULL(CASE WHEN [Impacts Commercial Portfolio?]             = 'Yes'
                            THEN '|Commercial'           ELSE '' END, '') +
                ISNULL(CASE WHEN [Impacts Data & AI Portfolio?]              = 'Yes'
                              OR [Impacts Platform Portfolio?]               = 'Yes'
                            THEN '|Platforms'            ELSE '' END, '') +
                ISNULL(CASE WHEN [Impacts Enterprise Services Portfolio?]    = 'Yes'
                            THEN '|Enterprise Services'  ELSE '' END, '') +
                ISNULL(CASE WHEN [Impacts Supply Chain Operations Portfolio?]= 'Yes'
                            THEN '|Supply Chain Operations' ELSE '' END, ''),
                1, 1, ''
            ),
        '')                                                                                  AS [Other Impacted Portfolios],

        -- ── Prod-Init-026 : Transform_Primary_Type_of_Value ───
        CASE
            WHEN [Primary Type of Value] IN (
                'Service - FO/PO',
                'Service - IPF/IEF',
                'Service - Northern Border',
                'Service - EU'
            ) THEN 'Service - Other'
            ELSE [Primary Type of Value]
        END                                                                                  AS [Primary Type of Value - Transformed],

        -- ── Prod-Init-030 : Add_ArchitecturePM ────────────────
        'PLACEHOLDER USERNAME'                                                               AS [Architecture Program Manager],

        -- ── Prod-Init-032 : Add_Business_Demand_Manager + Add_Demand_Manager
        CASE
            WHEN [Demand Type] = 'Business Only' THEN [Initiative Owner]
            ELSE NULL
        END                                                                                  AS [Business Demand Manager],

        CASE
            WHEN [Demand Type] <> 'Business Only' THEN [Initiative Owner]
            ELSE NULL
        END                                                                                  AS [Demand Manager],

        -- ── Prod-Init-033 : Delimiter fix ─────────────────────
        -- Note: [Change - Impacted regions] and [Region(s) Impacted]
        -- are NOT in ip.FDXPROD_initiatives_extract view.
        -- These columns are sourced from Epics view — placeholders added.
        -- TODO: confirm if these fields exist elsewhere or can be removed.
        CAST(NULL AS NVARCHAR(500))                                                          AS [Change - Impacted regions - Transformed],
        CAST(NULL AS NVARCHAR(500))                                                          AS [Region(s) Impacted - Transformed]

    INTO dbo.stg_prod_init
    FROM ip.FDXPROD_initiatives_extract;

    PRINT 'stg_prod_init loaded — rows: ' + CAST(@@ROWCOUNT AS VARCHAR);


    -- ============================================================
    -- SECTION 2 : PROD EPICS
    -- Source      : ip.FDXPROD_epics_extract
    -- Tracker IDs : Prod-Epic-002, -003, -004, -009(SKIP),
    --               -014, -015, -016, -018, -019, -021, -022
    -- ============================================================

    PRINT '';
    PRINT '-- SECTION 2: Prod Epics';

    IF OBJECT_ID('dbo.stg_prod_epic', 'U') IS NOT NULL
        DROP TABLE dbo.stg_prod_epic;

    -- Prod-Epic-022 uses STRING_AGG + STRING_SPLIT which cannot be used
    -- as a subquery inside SELECT INTO. Solution: stage raw Epic data
    -- into a CTE first, then apply the dedup logic in a second step.

    -- Step A: stage all Epic columns except Impacted Portfolios transform
    -- into a temp table first
    IF OBJECT_ID('tempdb..#epic_stage', 'U') IS NOT NULL
        DROP TABLE #epic_stage;

    SELECT

        -- ── Prod-Epic-002 : Type Cast ──────────────────────────
        -- Note: [Schedule Duration] and [Baseline Duration] not in
        -- ip.FDXPROD_epics_extract — date casts applied to available cols
        CAST([Sequence ID]      AS NVARCHAR(50))    AS [Sequence ID],
        CAST([Actual Finish]    AS DATE)            AS [Actual Finish],
        CAST([Actual Start]     AS DATE)            AS [Actual Start],
        CAST([Baseline Finish]  AS DATE)            AS [Baseline Finish],
        CAST([Baseline Start]   AS DATE)            AS [Baseline Start],
        CAST([Schedule Finish]  AS DATE)            AS [Schedule Finish],
        CAST([Schedule Start]   AS DATE)            AS [Schedule Start],

        -- ── Prod-Epic-003 : Epic_Rename ────────────────────────
        -- Hardcoded Old → New aliases per Prod_Epic_Renamer
        -- Note: [Governance Level] in view = [Level of Governance] in target
        [Epic Name]                                 AS [Work Name],
        [Epic Owner]                                AS [Epic Owner],
        [Demand Type]                               AS [Demand Type],
        [Execution Type]                            AS [Execution Type],
        [Stage]                                     AS [Stage],
        [Work Status]                               AS [Work Status],
        [Governance Level]                          AS [Level of Governance],
        [Associated Initiative Seq ID]              AS [Associated Initiative Seq ID],
        [Primary Type of Value]                     AS [Primary Type of Value],
        [Impacted Portfolios]                       AS [Impacted Portfolios],
        [Change - Impacted regions]                 AS [Change - Impacted regions],
        [Change - Impacted stakeholder groups]      AS [Change - Impacted stakeholder groups],
        [Estimated Annualized Value Range]          AS [Estimated Annualized Value Range],
        [Health Status]                             AS [Health Status],
        [Demand SubType]                            AS [Demand SubType],
        [Home Portfolio]                            AS [Home Portfolio],
        [Demand Domain or Portfolio]                AS [Demand Domain or Portfolio],
        [T-Shirt Size]                              AS [T-Shirt Size],
        [Work ID #]                                 AS [Work ID],
        [Expected Business Outcome]                 AS [Expected Business Outcome],
        [Primary Type of Value Impact]              AS [Primary Type of Value Impact],
        [Investment Dependencies]                   AS [Investment Dependencies],
        [Sponsor Name]                              AS [Sponsor Name],
        [Triage Comments]                           AS [Triage Comments],
        [Status Rationale]                          AS [Status Rationale],
        [In Scope]                                  AS [In Scope],
        [Out of Scope]                              AS [Out of Scope],
        [EAI #]                                     AS [EAI #],
        [Epic Notes and Comments]                   AS [Epic Notes and Comments],
        [Key Assumptions Made in Quantifying Impact] AS [Key Assumptions Made in Quantifying Impact],
        [PPM Project Number]                        AS [PPM Project Number],
        [IT Architect]                              AS [IT Architect],
        [Business Architect]                        AS [Business Architect],
        [PEO]                                       AS [PEO],
        [Agility #]                                 AS [Agility #],
        [Agility URL]                               AS [Agility URL],

        -- ── Prod-Epic-004 : Add_DataSource ────────────────────
        'Prod-Epic'                                 AS [Data Source],

        -- Index key
        'Prod-Epic-' + CAST([Sequence ID] AS NVARCHAR(50))
                                                    AS [Index],

        -- ── Prod-Epic-009 : Add_Disposition ───────────────────
        -- SKIPPED — requires RosettaStone Parent Disposition
        -- NULL stub retained for schema completeness
        -- TODO: Bert to complete once RosettaStone is available
        CAST(NULL AS NVARCHAR(200))                 AS [Disposition],

        -- ── Prod-Epic-014 : Transform_Primary_Type_of_Value ───
        CASE
            WHEN [Primary Type of Value] IN (
                'Service - FO/PO',
                'Service - IPF/IEF',
                'Service - Northern Border',
                'Service - EU'
            ) THEN 'Service - Other'
            ELSE [Primary Type of Value]
        END                                         AS [Primary Type of Value - Transformed],

        -- ── Prod-Epic-015 : Add_Show_on_Roadmap ───────────────
        'Show on Strategy & Project'                AS [Show on Roadmap],

        -- ── Prod-Epic-016 : Add_Milestone_Flag ────────────────
        'N'                                         AS [Milestone Flag],

        -- ── Prod-Epic-018 : Add_Business_Only ─────────────────
        CASE
            WHEN [Demand Type] = 'Business Only' THEN 'Yes'
            ELSE 'No'
        END                                         AS [Is this demand Business Only?],

        -- ── Prod-Epic-019 : Add_Business_Demand_Manager + Add_Demand_Manager
        CASE
            WHEN [Demand Type] = 'Business Only' THEN [Epic Owner]
            ELSE NULL
        END                                         AS [Business Demand Manager],

        CASE
            WHEN [Demand Type] <> 'Business Only' THEN [Epic Owner]
            ELSE NULL
        END                                         AS [Demand Manager],

        -- ── Prod-Epic-021 : Replace_Delimiter ─────────────────
        REPLACE([Change - Impacted regions],            ', ', '|')
                                                    AS [Change - Impacted regions - Transformed],

        REPLACE([Change - Impacted stakeholder groups], ', ', '|')
                                                    AS [Change - Impacted stakeholder groups - Transformed],

        -- Impacted Portfolios raw — transform applied in Step B below
        [Impacted Portfolios]                       AS [Impacted Portfolios Raw]

    INTO #epic_stage
    FROM ip.FDXPROD_epics_extract;

    -- Step B: apply Prod-Epic-022 Transform_Impacted_Portfolios
    -- Data & AI → Platforms, deduplicate entries, rejoin with '|'
    -- STRING_AGG + STRING_SPLIT must run outside SELECT INTO
    IF OBJECT_ID('dbo.stg_prod_epic', 'U') IS NOT NULL
        DROP TABLE dbo.stg_prod_epic;

    SELECT
        e.*,
        -- ── Prod-Epic-022 : Transform_Impacted_Portfolios ─────
        CASE
            WHEN e.[Impacted Portfolios Raw] IS NULL THEN NULL
            ELSE ip_transform.Transformed
        END                                         AS [Impacted Portfolios - Transformed]
    INTO dbo.stg_prod_epic
    FROM #epic_stage e
    OUTER APPLY (
        SELECT STRING_AGG(LTRIM(RTRIM(val)), '|') AS Transformed
        FROM (
            SELECT DISTINCT
                REPLACE(LTRIM(RTRIM(value)), 'Data & AI', 'Platforms') AS val
            FROM STRING_SPLIT(
                REPLACE(e.[Impacted Portfolios Raw], 'Data & AI', 'Platforms'),
                ','
            )
            WHERE LTRIM(RTRIM(value)) <> ''
        ) deduped
    ) ip_transform;

    DROP TABLE #epic_stage;

    PRINT 'stg_prod_epic loaded — rows: ' + CAST(@@ROWCOUNT AS VARCHAR);


    -- ============================================================
    -- SECTION 3 : PROD TASKS
    -- Source      : ip.FDXPROD_tasks_extract
    -- Tracker IDs : Prod-Task-002, -003, -008, -009, -010(SKIP),
    --               -011
    -- Note        : View columns are mixed-case (not all-caps)
    -- ============================================================

    PRINT '';
    PRINT '-- SECTION 3: Prod Tasks';

    IF OBJECT_ID('dbo.stg_prod_task', 'U') IS NOT NULL
        DROP TABLE dbo.stg_prod_task;

    SELECT

        -- ── Prod-Task-002 : Rename_Cols + Remove Columns ───────
        -- Mixed-case source columns confirmed from view
        -- Dropped: [Path], [Place], [Execution Type], [Work Sequence ID]
        CAST([Sequence ID]          AS NVARCHAR(50))     AS [Sequence ID],
        CAST([Work ID]              AS NVARCHAR(50))     AS [Work ID],
        CAST([Parent Sequence ID]   AS NVARCHAR(50))     AS [Parent Sequence ID],
        [Name]                                           AS [Work Name],
        [Task or Milestone Type]                         AS [Task or Milestone Type],
        [Milestone Flag]                                 AS [Milestone Flag],
        [Milestone/Task Owner]                           AS [Milestone/Task Owner],
        [Work Status]                                    AS [Work Status Source],
        CAST([Schedule Start]       AS DATE)             AS [Schedule Start],
        CAST([Schedule Finish]      AS DATE)             AS [Schedule Finish],
        CAST([Baseline Start]       AS DATE)             AS [Baseline Start],
        CAST([Baseline Finish]      AS DATE)             AS [Baseline Finish],
        CAST([Actual Start]         AS DATE)             AS [Actual Start],
        CAST([Actual Finish]        AS DATE)             AS [Actual Finish],
        [Health Status]                                  AS [Health Status],
        CAST(ISNULL([Duration], 0)  AS BIGINT)           AS [Duration],
        [Show on Roadmap]                                AS [Show on Roadmap],
        -- Dropped columns (not selected):
        --   [Path], [Place], [Execution Type], [Work Sequence ID]

        -- Data Source + Index
        'Prod-Task'                                      AS [Data Source],
        'Prod-Task-' + CAST([Sequence ID] AS NVARCHAR(50))
                                                         AS [Index],

        -- ── Prod-Task-003 : Transform_Work_Status ─────────────
        -- 11-value mapping; null → null; unmapped → ERROR
        CASE [Work Status]
            WHEN 'Not Started'          THEN 'New'
            WHEN 'Approved'             THEN 'Active'
            WHEN 'In Progress'          THEN 'Active'
            WHEN 'Active'               THEN 'Active'
            WHEN 'On Hold'              THEN 'On Hold'
            WHEN 'Closed'               THEN 'Completed/Closed'
            WHEN 'Completed'            THEN 'Completed/Closed'
            WHEN 'Cancelled'            THEN 'Cancelled'
            WHEN 'Rejected'             THEN 'Rejected'
            WHEN 'Cancellation Request' THEN 'Cancelled'
            WHEN 'Assumed Completed'    THEN 'Completed/Closed'
            ELSE
                CASE WHEN [Work Status] IS NULL THEN NULL
                ELSE 'ERROR' END
        END                                              AS [Work Status],

        -- ── Prod-Task-008 : Add_Execution_Type ────────────────
        -- Milestone Flag = Y → 'Milestone'; else → 'Business Task'
        CASE
            WHEN [Milestone Flag] = 'Y' THEN 'Milestone'
            ELSE 'Business Task'
        END                                              AS [Execution Type],

        -- ── Prod-Task-009 : Add_Disposition ───────────────────
        -- Cascade from parent Epic Disposition
        -- [Parent Disposition] not in view — NULL stub
        -- TODO: Bert to populate via RosettaStone Epic join
        CAST(NULL AS NVARCHAR(200))                      AS [Disposition],

        -- ── Prod-Task-010 : Add_Work_Type ─────────────────────
        -- SKIPPED — requires RosettaStone grandparent Init Demand Type
        -- NULL stub retained for schema completeness
        -- TODO: Bert to complete once RosettaStone is available
        CAST(NULL AS NVARCHAR(100))                      AS [Work Type],

        -- ── Prod-Task-011 : Transform_Task_Milestone_Type ─────
        -- Full mapping per PQ v6.05
        CASE [Task or Milestone Type]
            WHEN 'Money Step'               THEN 'Money Step'
            WHEN 'Implementation'           THEN 'Implementation'
            WHEN 'Technology / Systems'     THEN 'Technology'
            WHEN 'Technology'               THEN 'Technology'
            WHEN 'Change Management'        THEN 'Change Management'
            WHEN 'Finance'                  THEN 'Other'
            WHEN 'Human Resources'          THEN 'Human Resources'
            WHEN 'Legal'                    THEN 'Legal / Regulatory'
            WHEN 'Other dependency'         THEN 'Other'
            WHEN 'Initiation & Governance'  THEN 'Other'
            WHEN 'Other'                    THEN 'Other'
            ELSE                                 'Other'
        END                                              AS [Task or Milestone Type - Transformed]

    INTO dbo.stg_prod_task
    FROM ip.FDXPROD_tasks_extract;

    PRINT 'stg_prod_task loaded — rows: ' + CAST(@@ROWCOUNT AS VARCHAR);


    -- ============================================================
    -- COMPLETION SUMMARY
    -- ============================================================
    DECLARE @cnt_init INT, @cnt_epic INT, @cnt_task INT;
    SELECT @cnt_init = COUNT(*) FROM dbo.stg_prod_init;
    SELECT @cnt_epic = COUNT(*) FROM dbo.stg_prod_epic;
    SELECT @cnt_task = COUNT(*) FROM dbo.stg_prod_task;

    PRINT '';
    PRINT '======================================================';
    PRINT 'Planview2026PlatinumConsolidatedv2 — COMPLETE';
    PRINT '  dbo.stg_prod_init : ' + CAST(@cnt_init AS VARCHAR) + ' rows';
    PRINT '  dbo.stg_prod_epic : ' + CAST(@cnt_epic AS VARCHAR) + ' rows';
    PRINT '  dbo.stg_prod_task : ' + CAST(@cnt_task AS VARCHAR) + ' rows';
    PRINT CONVERT(VARCHAR, GETDATE(), 120);
    PRINT '======================================================';

END;
GO
