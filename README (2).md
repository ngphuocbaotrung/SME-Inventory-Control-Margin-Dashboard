# SME Inventory Control & Margin Dashboard
> End-to-end inventory management platform built on Microsoft Fabric — from raw ERP data to executive dashboard.

![Microsoft Fabric](https://img.shields.io/badge/Microsoft_Fabric-Trial-0078D4?style=flat&logo=microsoft)
![Power BI](https://img.shields.io/badge/Power_BI-Direct_Lake-F2C811?style=flat&logo=powerbi)
![Python](https://img.shields.io/badge/Python-PySpark-3776AB?style=flat&logo=python)
![Dataflow](https://img.shields.io/badge/Dataflow_Gen2-Medallion-00B4D8?style=flat&logo=microsoft)

---

## Overview

A portfolio project simulating a real-world SME inventory management system with automated daily refresh, WAC-based COGS tracking, and a 3-page executive dashboard — built entirely on Microsoft Fabric.

**The core question this project answers:**
> *"Is our inventory healthy today — and what do we need to do about it right now?"*

---

## Business Problems Solved

### Problem 1 — No Real-Time Inventory Visibility
**Before:** Managers relied on outdated Excel files. Stockouts were only discovered when customers complained.

**After:** Dashboard refreshes at 6AM daily. Stock status across all 3 warehouses (NYC, LA, Paris) visible in under 30 seconds. Out of Stock and Reorder Now flags surface issues before they become lost revenue.

---

### Problem 2 — Capital Tied Up Without Visibility
**Before:** No one knew how much working capital was locked in slow-moving stock. With 27 out of 30 SKUs flagged as Critical slow movers and Days on Hand exceeding 1,000+ days for some products, capital was silently being eroded.

**After:** Slow Mover Value, Dead Stock Value, and per-product Days on Hand are tracked daily. Teams can prioritize clearance, stop-buy, or inter-warehouse transfer decisions with data.

---

### Problem 3 — No WAC-Based Cost Visibility
**Before:** Pricing and margin analysis were based on base cost, not actual weighted average cost. Margin erosion from purchase price fluctuations was invisible.

**After:** WAC cost per SKU per warehouse is calculated daily via Dataflow Gen2. Inventory Value (€573,880 total) and per-row WAC are visible in the Inventory Details drill-down table.

---

### Problem 4 — Slow Decision Making
**Before:** Replenishment and stockout decisions required manual cross-referencing of multiple spreadsheets.

**After:** Stock Balance table shows exact Qty To Order per product per warehouse (total 261 units needed). Managers can act immediately without additional analysis.

---

## Architecture

```
Python Notebook (PySpark)
        ↓  generate & load raw ERP data
Inventory_Lakehouse  ─────────────── Bronze Layer (Delta tables)
        ↓
Dataflow Gen2 — df_inventory_transform
  STG layer (in-memory, no staging)
  TRF layer (write to Warehouse)  ── Silver → Gold Layer
        ↓
inventory_warehouse (Fabric Warehouse)
  gold_stock_balance     gold_wac_cost
  gold_slow_movers       gold_margin_kpis
  gold_stock_movement                 ── Gold Serving Layer
        ↓
Power BI Direct Lake                 ── Reporting Layer
  sm_inventory_platform (semantic model)
  3-page dashboard
        ↓
pl_inventory_daily (Pipeline)        ── Orchestration (6AM daily)
```

---

## Tech Stack

| Layer | Tool | Purpose |
|---|---|---|
| Ingestion | Python Notebook (PySpark) | Generate & load ERP data into Lakehouse |
| Storage | OneLake / Lakehouse | Bronze Delta tables |
| Transform | Dataflow Gen2 (M code) | STG + TRF Medallion pattern |
| Serving | Fabric Warehouse (T-SQL) | Gold tables + SQL Views |
| Reporting | Power BI Direct Lake | 3-page executive dashboard |
| Orchestration | Fabric Pipeline | 6AM daily automation |

---

## Data Model

**Simulated ERP data — FY2025, 3 warehouses (NYC, LA, Paris)**

| Table | Rows | Description |
|---|---|---|
| fact_transactions | ~880 | PURCHASE / SALE / ADJUSTMENT events |
| dim_product | 30 SKUs | 5 categories: Electronics, Components, Office Supplies, Accessories, Consumables |
| dim_warehouse | 3 | NYC Warehouse, LA Warehouse, Paris Warehouse |
| dim_date | 365 | Calendar table FY2025 |

**Costing Method:** WAC (Weighted Average Cost) — IFRS/GAAP compliant

**Gold Tables:** `gold_stock_balance` · `gold_wac_cost` · `gold_slow_movers` · `gold_margin_kpis` · `gold_stock_movement`

---

## Dashboard Pages

### Page 1 — Overview
Executive health check with 6 KPI cards and trend analysis.

| KPI | Value | Description |
|---|---|---|
| Inventory Value Today | €573K | Current stock × WAC per product |
| Total Stock Qty | 3,039 units | Total units across all warehouses |
| DIO | 293 days | Days Inventory Outstanding |
| Inventory Turnover | 1.24x | COGS / Inventory Value |
| Stockout Rate | 43% | Out of Stock SKUs / Total SKUs |
| Slow Mover Value | €551K | Capital tied in slow-moving stock |

**Visuals:**
- Revenue, COGS & Avg Margin % trend by month
- Best 5 Selling Products (by Qty Out)
- Worst 5 Selling Products (by Qty Out)
- Top 5 Products by Days on Hand
- Total Qty In vs Qty Out by date

---

### Page 2 — Inventory Status
Stockout risk and slow mover analysis with Warehouse + Category slicers.

| KPI | Value |
|---|---|
| Total SKU | 30 |
| Total Stock Qty | 3K |
| Out of Stock | 13 |
| Reorder Now | 7 |
| Slow Movers | 27 |

**Visuals:**
- Stock Status distribution donut (OK 70% · Out of Stock 16.67% · Reorder Now 8.89%)
- Out of Stock by Category (Components 3, Electronics 3, Consumables 3, Office Supplies 2, Accessories 2)
- Reorder Now by Category
- Stock Balance by Product table (with Qty To Order + conditional formatting)
- Slow Movers — Days on Hand table (Critical flag, current stock, sold in 90 days)

---

### Page 3 — Inventory Details
Full drill-down table with Warehouse + Product Name slicers.

**Columns:** Product ID · Product Name · Warehouse Name · Total Qty In · Total Qty Out · Total Stock Qty · WAC · Inventory Value · Out of Stock · Reorder Now

**Totals:** Qty In 7,554 · Qty Out 4,515 · Stock 3,039 · WAC avg €5,336 · Inventory Value €573,880 · Out of Stock 13 · Reorder Now 7

---

## Key DAX Measures

```dax
-- Inventory snapshot
Inventory Value    = CALCULATE(SUMX(gold_stock_balance, stock_qty * LOOKUPVALUE(wac_cost...)), ALL(dim_date))
Total Stock Qty    = CALCULATE(SUM(gold_stock_balance[stock_qty]), ALL(dim_date))

-- Efficiency KPIs
DIO                = DIVIDE([Inventory Value], [Total COGS]) * 365
Inventory Turnover = DIVIDE([Total COGS], [Inventory Value])
Stockout Rate      = DIVIDE([Out of Stock], [Total SKUs])
Service Level      = 1 - [Stockout Rate]

-- Capital at risk
Slow Mover Value   = SUMX(FILTER(gold_slow_movers, slow_mover_flag <> "Normal"), current_stock * wac_cost)
Qty To Order       = SUMX(FILTER(gold_stock_balance, stock_qty <= reorder_point), reorder_point - stock_qty)
```

---

## How to Run

```
1. Open Notebook 1 → Run All  (generates FY2025 data into Lakehouse)
2. Open df_inventory_transform → Refresh  (transforms & loads gold tables)
3. Open Report in Power BI Web → data updates automatically via Direct Lake
4. pl_inventory_daily runs automatically at 6AM daily
```

---

## Known Limitations

| Limitation | Business Impact | Workaround |
|---|---|---|
| Simulated random data | No seasonality or real demand patterns | Replace with live ERP connector |
| Static reorder points | May over/under-order | Manual quarterly review |
| No demand forecasting | Reactive stockout management only | Use Days on Hand as proxy |
| 6AM refresh only | Intraday stockouts undetected | Manual check for high-velocity SKUs |
| No supplier lead time | Safety stock not dynamically optimized | Conservative buffer applied |
| No financial integration | COGS may not match accounting records | Monthly reconciliation with finance |

---

## How to Make It Better

### Quick Wins (1–2 weeks)
- **Incremental load** — Append only new daily transactions instead of full refresh
- **Pipeline failure alerts** — Email/Teams notification when pipeline fails
- **Row Level Security** — Each warehouse manager sees only their own data
- **Git integration** — Version control for notebooks, SQL, and M code

### Medium Term (1 month)
- **Fabric Activator** — Real-time alert the moment a stockout occurs mid-day
- **dim_supplier table** — Track actual vs promised lead time, supplier reliability score
- **Inter-warehouse transfer logic** — Flag when a product is overstocked in one warehouse but critical in another
- **Accrual transactions** — Handle goods received but not yet invoiced

### Long Term (3+ months)
- **Demand forecasting** — Fabric Data Science + Prophet/ARIMA for dynamic reorder points
- **Real ERP integration** — Replace fake data with live SAP/Oracle/Dynamics connector
- **Power Apps action tracking** — Assign owner, due date, and completion status to each action item
- **P&L integration** — Link inventory COGS directly into full financial reporting

---

## Author

Built as a portfolio project to demonstrate end-to-end data engineering and business analytics on Microsoft Fabric.

> *"This project moves SME inventory management from reactive Excel reporting to a proactive, always-on decision platform. The next evolution: from descriptive analytics to predictive — forecasting demand before stockouts happen."*
