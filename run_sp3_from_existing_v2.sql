-- ============================================================================
-- SP3 OUTPUT FROM EXISTING TABLES — CLEAN VERSION
-- Source : [PlanviewMigration_Transform_Output].[Initiatives_v8]
--          [PlanviewMigration_Transform_Output].[Epics_v8]
-- Output : [PlanviewMigration_Transform_Output].[Initiatives_SP3_v{n}]
--          [PlanviewMigration_Transform_Output].[Epics_SP3_v{n}]
-- NOTE   : Existing tables are NEVER dropped — only new versioned tables created
-- ============================================================================

-- ============================================================================
-- STEP 1: Create output_v8 schema if not exists
-- New SP expects output_{run_ts} schema — we use run_ts = 'v8'
-- ============================================================================

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'output_v8')
    EXEC('CREATE SCHEMA [output_v8]')

-- ============================================================================
-- STEP 2: Point output_v8.Initiatives to existing Initiatives_v8 data
-- Uses SELECT INTO only if table does not already exist
-- ============================================================================

IF OBJECT_ID('[output_v8].[Initiatives]') IS NULL
BEGIN
    SELECT * INTO [output_v8].[Initiatives]
    FROM [PlanviewMigration_Transform_Output].[Initiatives_v8]
    PRINT 'output_v8.Initiatives created: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
END
ELSE
    PRINT 'output_v8.Initiatives already exists — using as-is'

-- ============================================================================
-- STEP 3: Point output_v8.Epics to existing Epics_v8 data
-- ============================================================================

IF OBJECT_ID('[output_v8].[Epics]') IS NULL
BEGIN
    SELECT * INTO [output_v8].[Epics]
    FROM [PlanviewMigration_Transform_Output].[Epics_v8]
    PRINT 'output_v8.Epics created: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
END
ELSE
    PRINT 'output_v8.Epics already exists — using as-is'

-- ============================================================================
-- STEP 4: Add Strategy Type from view (needed by SP3 Section 5)
-- ============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('[output_v8].[Initiatives]')
    AND name = 'Strategy Type'
)
    ALTER TABLE [output_v8].[Initiatives] ADD [Strategy Type] NVARCHAR(255)

UPDATE o
SET o.[Strategy Type] = v.[Strategy Type]
FROM [output_v8].[Initiatives] o
JOIN [FDXMIG].[ip].[FDXPROD_initiatives_extract] v
    ON REPLACE(CAST(o.[Strategy Seq ID] AS NVARCHAR(50)), 'Prod-Init-', '')
     = CAST(v.[Strategy Seq ID] AS NVARCHAR(50))
WHERE o.[Strategy Type] IS NULL

PRINT 'Strategy Type populated: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'

-- ============================================================================
-- STEP 5: Add Lifecycle Status from view (needed by SP3 Section 3)
-- ============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('[output_v8].[Initiatives]')
    AND name = 'Lifecycle Status'
)
    ALTER TABLE [output_v8].[Initiatives] ADD [Lifecycle Status] NVARCHAR(255)

UPDATE o
SET o.[Lifecycle Status] = v.[Lifecycle Status]
FROM [output_v8].[Initiatives] o
JOIN [FDXMIG].[ip].[FDXPROD_initiatives_extract] v
    ON REPLACE(CAST(o.[Strategy Seq ID] AS NVARCHAR(50)), 'Prod-Init-', '')
     = CAST(v.[Strategy Seq ID] AS NVARCHAR(50))
WHERE o.[Lifecycle Status] IS NULL

PRINT 'Lifecycle Status populated: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'

-- Quick verify before running SP3
SELECT
    COUNT(*) AS Total_Rows,
    SUM(CASE WHEN [Strategy Type]    IS NOT NULL THEN 1 ELSE 0 END) AS Strategy_Type_OK,
    SUM(CASE WHEN [Lifecycle Status] IS NOT NULL THEN 1 ELSE 0 END) AS Lifecycle_Status_OK,
    SUM(CASE WHEN [Stage]            IS NOT NULL THEN 1 ELSE 0 END) AS Stage_OK,
    SUM(CASE WHEN [Flow Type]        IS NOT NULL THEN 1 ELSE 0 END) AS Flow_Type_OK,
    SUM(CASE WHEN [Demand Type]      IS NOT NULL THEN 1 ELSE 0 END) AS Demand_Type_OK
FROM [output_v8].[Initiatives]

-- ============================================================================
-- STEP 6: Run New SP (SP3)
-- Mutates output_v8.Initiatives and output_v8.Epics directly
-- Adds: Disposition, 16 approvals, Status, Work Status, Limited Visibility,
--       Other Impacted Portfolios, Execution Type, Parent Seq ID (Init)
--       GrandParent Index, Parent Seq ID, Flow Type (Epics)
-- ============================================================================

EXEC dbo.usp_Planview_PQ_Transformation
    @run_ts             = N'v8',
    @WorkHierarchyTable = N'dbo.ref_WorkHierarchy',
    @DevPPL1Table       = N'dbo.ref_DevPPL1'

PRINT 'SP3 completed'

-- ============================================================================
-- STEP 7: Get next version number — never overwrites existing tables
-- ============================================================================

DECLARE @next_v INT
SELECT @next_v = ISNULL(MAX(
    CAST(REPLACE(t.name, 'Initiatives_SP3_v', '') AS INT)
), 0) + 1
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name = 'PlanviewMigration_Transform_Output'
AND t.name LIKE 'Initiatives_SP3_v%'
AND ISNUMERIC(REPLACE(t.name, 'Initiatives_SP3_v', '')) = 1

PRINT 'Saving as version v' + CAST(@next_v AS VARCHAR)

-- ============================================================================
-- STEP 8: Save versioned output — new tables only, existing never touched
-- ============================================================================

DECLARE @init_tbl NVARCHAR(200) = 
    '[PlanviewMigration_Transform_Output].[Initiatives_SP3_v' + CAST(@next_v AS VARCHAR) + ']'
DECLARE @epic_tbl NVARCHAR(200) = 
    '[PlanviewMigration_Transform_Output].[Epics_SP3_v'       + CAST(@next_v AS VARCHAR) + ']'

DECLARE @save_i NVARCHAR(MAX) = 
    N'SELECT * INTO ' + @init_tbl + N' FROM [output_v8].[Initiatives] ORDER BY [Index_ID]'
EXEC sp_executesql @save_i
PRINT 'Initiatives_SP3_v' + CAST(@next_v AS VARCHAR) + ' saved'

DECLARE @save_e NVARCHAR(MAX) = 
    N'SELECT * INTO ' + @epic_tbl + N' FROM [output_v8].[Epics] ORDER BY [Index_ID]'
EXEC sp_executesql @save_e
PRINT 'Epics_SP3_v' + CAST(@next_v AS VARCHAR) + ' saved'

-- ============================================================================
-- STEP 9: Verify SP3 column population
-- ============================================================================

DECLARE @verify_i NVARCHAR(MAX) = N'
SELECT
    COUNT(*)                                                                         AS Total_Rows,
    SUM(CASE WHEN [Disposition]                           IS NOT NULL THEN 1 ELSE 0 END) AS Disposition,
    SUM(CASE WHEN [SL3 EPG Approval]                      IS NOT NULL THEN 1 ELSE 0 END) AS Approvals_16,
    SUM(CASE WHEN [Status]                                IS NOT NULL THEN 1 ELSE 0 END) AS Status,
    SUM(CASE WHEN [Work Status]                           IS NOT NULL THEN 1 ELSE 0 END) AS Work_Status,
    SUM(CASE WHEN [Does this require Limited Visibility?] IS NOT NULL THEN 1 ELSE 0 END) AS Limited_Visibility,
    SUM(CASE WHEN [Other Impacted Portfolios]             IS NOT NULL THEN 1 ELSE 0 END) AS Other_Impacted_Portfolios,
    SUM(CASE WHEN [Demand Type - Legacy]                  IS NOT NULL THEN 1 ELSE 0 END) AS Demand_Type_Legacy,
    SUM(CASE WHEN [Execution Type - Legacy]               IS NOT NULL THEN 1 ELSE 0 END) AS ET_Legacy,
    SUM(CASE WHEN [Execution Type]                        IS NOT NULL THEN 1 ELSE 0 END) AS Execution_Type,
    SUM(CASE WHEN [Parent Sequence ID]                    IS NOT NULL THEN 1 ELSE 0 END) AS Parent_Seq_ID
FROM ' + @init_tbl
EXEC sp_executesql @verify_i

DECLARE @verify_e NVARCHAR(MAX) = N'
SELECT
    COUNT(*)                                                                    AS Total_Rows,
    SUM(CASE WHEN [Execution Type]          IS NOT NULL THEN 1 ELSE 0 END) AS Execution_Type,
    SUM(CASE WHEN [Execution Type - Legacy] IS NOT NULL THEN 1 ELSE 0 END) AS ET_Legacy,
    SUM(CASE WHEN [GrandParent Index]       IS NOT NULL THEN 1 ELSE 0 END) AS GrandParent_Index,
    SUM(CASE WHEN [Inherited Flow Type]     IS NOT NULL THEN 1 ELSE 0 END) AS Inherited_Flow_Type,
    SUM(CASE WHEN [Epic Flow Type]          IS NOT NULL THEN 1 ELSE 0 END) AS Epic_Flow_Type,
    SUM(CASE WHEN [Parent Sequence ID]      IS NOT NULL THEN 1 ELSE 0 END) AS Parent_Seq_ID
FROM ' + @epic_tbl
EXEC sp_executesql @verify_e

PRINT 'Done — Initiatives_SP3_v' + CAST(@next_v AS VARCHAR) + 
      ' and Epics_SP3_v' + CAST(@next_v AS VARCHAR) + ' ready in PlanviewMigration_Transform_Output'
