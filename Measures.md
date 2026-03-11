# DAX Measures — SME Inventory Platform
> All measures used in the Power BI semantic model (sm_inventory_platform)

---

## Table: gold_stock_balance

### Inventory Value
```dax
Inventory Value =
CALCULATE(
    SUMX(
        gold_stock_balance,
        gold_stock_balance[stock_qty] *
        LOOKUPVALUE(
            gold_wac_cost[wac_cost],
            gold_wac_cost[product_id],
            gold_stock_balance[product_id]
        )
    ),
    ALL(dim_date)
)
```

### Total Stock Qty
```dax
Total Stock Qty =
CALCULATE(
    SUM(gold_stock_balance[stock_qty]),
    ALL(dim_date)
)
```

### Total SKUs
```dax
Total SKUs =
DISTINCTCOUNT(gold_stock_balance[product_name])
```

### Out of Stock
```dax
Out of Stock =
CALCULATE(
    DISTINCTCOUNT(gold_stock_balance[product_name]),
    gold_stock_balance[stock_status] = "Out of Stock"
)
```

### Critical Stock
```dax
Critical Stock =
CALCULATE(
    DISTINCTCOUNT(gold_stock_balance[product_name]),
    gold_stock_balance[stock_status] = "Critical"
)
```

### Reorder Now
```dax
Reorder Now =
CALCULATE(
    DISTINCTCOUNT(gold_stock_balance[product_name]),
    gold_stock_balance[stock_status] = "Reorder Now"
)
```

### Stockout Rate
```dax
Stockout Rate =
DIVIDE([Out of Stock], [Total SKUs])
```
> Format: 0.0%

### Service Level
```dax
Service Level =
1 - [Stockout Rate]
```
> Format: 0.0%

### Qty To Order
```dax
Qty To Order =
SUMX(
    FILTER(
        gold_stock_balance,
        gold_stock_balance[stock_qty] <= gold_stock_balance[reorder_point]
    ),
    gold_stock_balance[reorder_point] - gold_stock_balance[stock_qty]
)
```

### Overstock Value
```dax
Overstock Value =
SUMX(
    FILTER(
        gold_stock_balance,
        gold_stock_balance[stock_qty] > gold_stock_balance[reorder_point] * 2
    ),
    (gold_stock_balance[stock_qty] - gold_stock_balance[reorder_point] * 2) *
    LOOKUPVALUE(
        gold_wac_cost[wac_cost],
        gold_wac_cost[product_id],
        gold_stock_balance[product_id]
    )
)
```

---

## Table: gold_margin_kpis

### Total Revenue
```dax
Total Revenue =
SUM(gold_margin_kpis[total_revenue])
```

### Total COGS
```dax
Total COGS =
SUM(gold_margin_kpis[total_cogs])
```

### Gross Profit
```dax
Gross Profit =
SUM(gold_margin_kpis[gross_profit])
```

### Avg Margin %
```dax
Avg Margin % =
DIVIDE([Gross Profit], [Total Revenue])
```
> Format: 0.0%

### DIO (Days Inventory Outstanding)
```dax
DIO =
DIVIDE([Inventory Value], [Total COGS]) * 365
```
> Format: 0.0

### Inventory Turnover
```dax
Inventory Turnover =
DIVIDE([Total COGS], [Inventory Value])
```
> Format: 0.0x

### Revenue PM (Previous Month)
```dax
Revenue PM =
CALCULATE(
    [Total Revenue],
    DATEADD(dim_date[date], -1, MONTH)
)
```

### Revenue MoM %
```dax
Revenue MoM % =
DIVIDE([Total Revenue] - [Revenue PM], [Revenue PM])
```
> Format: 0.0%

---

## Table: gold_slow_movers

### Slow Mover Count
```dax
Slow Mover Count =
CALCULATE(
    DISTINCTCOUNT(gold_slow_movers[product_name]),
    gold_slow_movers[slow_mover_flag] <> "Normal"
)
```

### Slow Mover Value
```dax
Slow Mover Value =
SUMX(
    FILTER(
        gold_slow_movers,
        gold_slow_movers[slow_mover_flag] <> "Normal"
    ),
    gold_slow_movers[current_stock] *
    LOOKUPVALUE(
        gold_wac_cost[wac_cost],
        gold_wac_cost[product_id],
        gold_slow_movers[product_id]
    )
)
```

### Dead Stock Value
```dax
Dead Stock Value =
SUMX(
    FILTER(
        gold_stock_balance,
        gold_stock_balance[stock_qty] > 0
    ),
    VAR doh =
        LOOKUPVALUE(
            gold_slow_movers[days_on_hand],
            gold_slow_movers[product_id],
            gold_stock_balance[product_id]
        )
    RETURN
    IF(
        doh > 180,
        gold_stock_balance[stock_qty] *
        LOOKUPVALUE(
            gold_wac_cost[wac_cost],
            gold_wac_cost[product_id],
            gold_stock_balance[product_id]
        ),
        0
    )
)
```

### Slow Mover %
```dax
Slow Mover % =
DIVIDE([Slow Mover Value], [Inventory Value])
```
> Format: 0.0%

---

## Table: gold_wac_cost

### Low Margin Alert
```dax
Low Margin Alert =
CALCULATE(
    DISTINCTCOUNT(gold_wac_cost[product_name]),
    gold_wac_cost[gross_margin_pct] < 15
)
```

### Margin Warning
```dax
Margin Warning =
CALCULATE(
    DISTINCTCOUNT(gold_wac_cost[product_name]),
    gold_wac_cost[gross_margin_pct] >= 15,
    gold_wac_cost[gross_margin_pct] < 20
)
```
