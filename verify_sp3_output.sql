-- ============================================================================
-- SP3 OUTPUT VERIFICATION
-- Replace Initiatives_SP3_v1 and Epics_SP3_v1 with your actual version
-- ============================================================================

-- ============================================================================
-- INITIATIVES — SP3 Column Check
-- ============================================================================

SELECT '=== INITIATIVES SP3 VERIFICATION ===' AS Section

-- Section 2: 16 Approval fields — should be Approved for G:L3 and I:L4 rows
SELECT
    [Stage],
    COUNT(*)                                                                      AS Row_Count,
    SUM(CASE WHEN [SL3 EPG Approval]                  = 'Approved'             THEN 1 ELSE 0 END) AS SL3_EPG,
    SUM(CASE WHEN [SL3 Business Finance Approval]     = 'Approved'             THEN 1 ELSE 0 END) AS SL3_BizFin,
    SUM(CASE WHEN [Ready for L3 EPM Quality Check?]   = 'Yes'                  THEN 1 ELSE 0 END) AS Ready_L3_EPM,
    SUM(CASE WHEN [L3 EPM Review 1]                   = 'Passed Quality Check' THEN 1 ELSE 0 END) AS L3_EPM_Rev,
    SUM(CASE WHEN [L3 Epic Approval]                  = 'Approved'             THEN 1 ELSE 0 END) AS L3_Epic,
    SUM(CASE WHEN [SL4 Close Work Bundle -D&T Finance Approval] = 'Approved'   THEN 1 ELSE 0 END) AS SL4_Close
FROM [PlanviewMigration_Transform_Output].[Initiatives_SP3_v1]
WHERE [Stage] IN ('G: L3', 'I: L4')
GROUP BY [Stage]
ORDER BY [Stage]

-- Section 3: Status and Work Status — check distinct values
SELECT '--- Status Values ---' AS Check_Name
SELECT [Status], COUNT(*) AS Row_Count
FROM [PlanviewMigration_Transform_Output].[Initiatives_SP3_v1]
GROUP BY [Status]
ORDER BY [Status]

SELECT '--- Work Status Values ---' AS Check_Name
SELECT [Work Status], COUNT(*) AS Row_Count
FROM [PlanviewMigration_Transform_Output].[Initiatives_SP3_v1]
GROUP BY [Work Status]
ORDER BY [Work Status]

-- Section 3: Limited Visibility
SELECT '--- Limited Visibility Values ---' AS Check_Name
SELECT [Does this require Limited Visibility?], COUNT(*) AS Row_Count
FROM [PlanviewMigration_Transform_Output].[Initiatives_SP3_v1]
GROUP BY [Does this require Limited Visibility?]

-- Section 5: Execution Type — check derived values
SELECT '--- Execution Type Values ---' AS Check_Name
SELECT [Demand Type], [Execution Type], COUNT(*) AS Row_Count
FROM [PlanviewMigration_Transform_Output].[Initiatives_SP3_v1]
GROUP BY [Demand Type], [Execution Type]
ORDER BY [Demand Type]

-- Section 5: Execution Type Legacy — from Strategy Type
SELECT '--- Execution Type Legacy (from Strategy Type) ---' AS Check_Name
SELECT [Execution Type - Legacy], COUNT(*) AS Row_Count
FROM [PlanviewMigration_Transform_Output].[Initiatives_SP3_v1]
GROUP BY [Execution Type - Legacy]
ORDER BY [Execution Type - Legacy]

-- Section 1: Disposition
SELECT '--- Disposition Values ---' AS Check_Name
SELECT
    ISNULL([Disposition], 'NULL') AS Disposition,
    COUNT(*) AS Row_Count
FROM [PlanviewMigration_Transform_Output].[Initiatives_SP3_v1]
GROUP BY [Disposition]

-- Section 4: Other Impacted Portfolios
SELECT '--- Other Impacted Portfolios (sample) ---' AS Check_Name
SELECT TOP 10 [Other Impacted Portfolios]
FROM [PlanviewMigration_Transform_Output].[Initiatives_SP3_v1]
WHERE [Other Impacted Portfolios] IS NOT NULL

-- Overall SP3 column count check
SELECT '--- SP3 Column Population Summary ---' AS Check_Name
SELECT
    COUNT(*)                                                                              AS Total_Rows,
    SUM(CASE WHEN [Disposition]                           IS NOT NULL THEN 1 ELSE 0 END) AS Disposition,
    SUM(CASE WHEN [SL3 EPG Approval]                      IS NOT NULL THEN 1 ELSE 0 END) AS Approvals_16,
    SUM(CASE WHEN [Status]          NOT IN ('ERROR','')   AND [Status] IS NOT NULL
                                                                        THEN 1 ELSE 0 END) AS Status_Valid,
    SUM(CASE WHEN [Work Status]     NOT IN ('ERROR','')   AND [Work Status] IS NOT NULL
                                                                        THEN 1 ELSE 0 END) AS Work_Status_Valid,
    SUM(CASE WHEN [Does this require Limited Visibility?] IS NOT NULL THEN 1 ELSE 0 END) AS Limited_Visibility,
    SUM(CASE WHEN [Other Impacted Portfolios]             IS NOT NULL THEN 1 ELSE 0 END) AS Other_Impacted,
    SUM(CASE WHEN [Demand Type - Legacy]                  IS NOT NULL THEN 1 ELSE 0 END) AS DT_Legacy,
    SUM(CASE WHEN [Execution Type - Legacy]               IS NOT NULL THEN 1 ELSE 0 END) AS ET_Legacy,
    SUM(CASE WHEN [Execution Type] NOT IN ('ERROR','')    AND [Execution Type] IS NOT NULL
                                                                        THEN 1 ELSE 0 END) AS ET_Valid,
    SUM(CASE WHEN [Parent Sequence ID] NOT LIKE 'ERROR%'  AND [Parent Sequence ID] IS NOT NULL
                                                                        THEN 1 ELSE 0 END) AS Parent_Seq_Valid
FROM [PlanviewMigration_Transform_Output].[Initiatives_SP3_v1]

-- ============================================================================
-- EPICS — SP3 Column Check
-- ============================================================================

SELECT '=== EPICS SP3 VERIFICATION ===' AS Section

-- Execution Type — should be Architecture Task or Epic
SELECT '--- Execution Type Values ---' AS Check_Name
SELECT [Execution Type], COUNT(*) AS Row_Count
FROM [PlanviewMigration_Transform_Output].[Epics_SP3_v1]
GROUP BY [Execution Type]
ORDER BY [Execution Type]

-- Execution Type Legacy — original source values
SELECT '--- Execution Type Legacy Values ---' AS Check_Name
SELECT [Execution Type - Legacy], COUNT(*) AS Row_Count
FROM [PlanviewMigration_Transform_Output].[Epics_SP3_v1]
GROUP BY [Execution Type - Legacy]
ORDER BY [Execution Type - Legacy]

-- GrandParent Index — should be Prod-Init-XXXXX (no double prefix)
SELECT '--- GrandParent Index (sample — check no double prefix) ---' AS Check_Name
SELECT TOP 5 [GrandParent Index]
FROM [PlanviewMigration_Transform_Output].[Epics_SP3_v1]
WHERE [GrandParent Index] IS NOT NULL
AND [GrandParent Index] NOT LIKE 'N/A%'
AND [GrandParent Index] NOT LIKE 'ERROR%'

-- Check for double prefix
SELECT '--- Double Prefix Check (should be 0) ---' AS Check_Name
SELECT COUNT(*) AS Double_Prefix_Rows
FROM [PlanviewMigration_Transform_Output].[Epics_SP3_v1]
WHERE [GrandParent Index] LIKE 'Prod-Init-Prod-Init-%'

-- Epic Flow Type
SELECT '--- Epic Flow Type Values ---' AS Check_Name
SELECT [Epic Flow Type], COUNT(*) AS Row_Count
FROM [PlanviewMigration_Transform_Output].[Epics_SP3_v1]
GROUP BY [Epic Flow Type]
ORDER BY [Epic Flow Type]

-- Inherited Flow Type
SELECT '--- Inherited Flow Type Values ---' AS Check_Name
SELECT
    ISNULL([Inherited Flow Type], 'NULL') AS Inherited_Flow_Type,
    COUNT(*) AS Row_Count
FROM [PlanviewMigration_Transform_Output].[Epics_SP3_v1]
GROUP BY [Inherited Flow Type]
ORDER BY [Inherited Flow Type]

-- Overall SP3 Epics column count check
SELECT '--- SP3 Epics Column Population Summary ---' AS Check_Name
SELECT
    COUNT(*)                                                                           AS Total_Rows,
    SUM(CASE WHEN [Execution Type]          IS NOT NULL THEN 1 ELSE 0 END) AS ET_Populated,
    SUM(CASE WHEN [Execution Type - Legacy] IS NOT NULL THEN 1 ELSE 0 END) AS ET_Legacy_Populated,
    SUM(CASE WHEN [GrandParent Index]       IS NOT NULL THEN 1 ELSE 0 END) AS GrandParent_Populated,
    SUM(CASE WHEN [Inherited Flow Type]     IS NOT NULL THEN 1 ELSE 0 END) AS Inherited_FT_Populated,
    SUM(CASE WHEN [Epic Flow Type]          IS NOT NULL THEN 1 ELSE 0 END) AS Epic_FT_Populated,
    SUM(CASE WHEN [Parent Sequence ID] NOT LIKE 'ERROR%'
             AND [Parent Sequence ID] IS NOT NULL        THEN 1 ELSE 0 END) AS Parent_Seq_Valid
FROM [PlanviewMigration_Transform_Output].[Epics_SP3_v1]

