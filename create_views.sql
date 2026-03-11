-- ============================================
-- SME Inventory Platform
-- SQL Views — inventory_warehouse
-- ============================================

-- View 1: Stock Summary
CREATE OR ALTER VIEW dbo.vw_stock_summary AS
SELECT 
    product_name,
    category,
    warehouse_name,
    city,
    country,
    region,
    stock_qty,
    total_purchases,
    total_sold,
    reorder_point,
    safety_stock,
    stock_status,
    dq_negative_flag,
    last_movement
FROM dbo.gold_stock_balance;
GO

-- View 2: Margin Analysis
CREATE OR ALTER VIEW dbo.vw_margin_analysis AS
SELECT 
    year_month,
    category,
    warehouse_name,
    total_revenue,
    total_cogs,
    gross_profit,
    gross_margin_pct,
    units_sold,
    transaction_count
FROM dbo.gold_margin_kpis;
GO

-- View 3: Slow Movers
CREATE OR ALTER VIEW dbo.vw_slow_movers AS
SELECT 
    product_name,
    category,
    current_stock,
    sold_90d,
    days_on_hand,
    slow_mover_flag,
    last_sale_date,
    reorder_point
FROM dbo.gold_slow_movers;
GO

-- View 4: WAC Cost
CREATE OR ALTER VIEW dbo.vw_wac_cost AS
SELECT 
    product_name,
    category,
    wac_cost,
    latest_cost,
    base_price,
    gross_margin_pct,
    purchase_count,
    total_qty
FROM dbo.gold_wac_cost;
GO
