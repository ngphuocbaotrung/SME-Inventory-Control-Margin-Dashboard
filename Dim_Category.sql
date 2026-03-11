-- ============================================
-- SME Inventory Platform
-- dim_category — inventory_warehouse
-- Note: Direct Lake does not support calculated
-- tables, so dim_category is created as a
-- physical table in Fabric Warehouse
-- ============================================

-- Step 1: Create table
CREATE TABLE dbo.dim_category (
    category VARCHAR(100)
);

-- Step 2: Insert distinct categories
INSERT INTO dbo.dim_category (category)
SELECT DISTINCT category
FROM dbo.gold_stock_balance;

-- Verify
SELECT * FROM dbo.dim_category;
