# Dataflow Gen2 — M Code
> df_inventory_transform — SME Inventory Platform

All M queries used in Dataflow Gen2. STG queries have staging disabled (Enable staging = OFF). TRF queries write to Fabric Warehouse (inventory_warehouse).

---

## STG Queries (Enable staging = OFF, no destination)

### stg_fact_transactions
```m
let
    Source     = Lakehouse.Contents(null),
    Navigation = Source{[workspaceId = "17a38d06-25be-4b10-9f15-a08999f75886"]}[Data],
    Nav1       = Navigation{[lakehouseId = "8ba75944-9d92-4ad7-af0e-6dd71f1ee3d5"]}[Data],
    RawTable   = Nav1{[Id = "fact_transactions", ItemKind = "Table"]}[Data],
    Typed = Table.TransformColumnTypes(RawTable, {
        {"transaction_id",   Int64.Type},
        {"date",             type datetime},
        {"product_id",       Int64.Type},
        {"warehouse_id",     Int64.Type},
        {"transaction_type", type text},
        {"quantity",         Int64.Type},
        {"unit_cost",        type number},
        {"unit_price",       type number},
        {"lot_number",       type text},
        {"reference",        type text}
    })
in
    Typed
```

### stg_dim_product
```m
let
    Source     = Lakehouse.Contents(null),
    Navigation = Source{[workspaceId = "17a38d06-25be-4b10-9f15-a08999f75886"]}[Data],
    Nav1       = Navigation{[lakehouseId = "8ba75944-9d92-4ad7-af0e-6dd71f1ee3d5"]}[Data],
    RawTable   = Nav1{[Id = "dim_product", ItemKind = "Table"]}[Data],
    Typed = Table.TransformColumnTypes(RawTable, {
        {"product_id",     Int64.Type},
        {"product_name",   type text},
        {"category",       type text},
        {"base_cost",      type number},
        {"base_price",     type number},
        {"reorder_point",  Int64.Type},
        {"safety_stock",   Int64.Type},
        {"lead_time_days", Int64.Type},
        {"supplier",       type text},
        {"is_active",      Int64.Type}
    })
in
    Typed
```

### stg_dim_warehouse
```m
let
    Source     = Lakehouse.Contents(null),
    Navigation = Source{[workspaceId = "17a38d06-25be-4b10-9f15-a08999f75886"]}[Data],
    Nav1       = Navigation{[lakehouseId = "8ba75944-9d92-4ad7-af0e-6dd71f1ee3d5"]}[Data],
    RawTable   = Nav1{[Id = "dim_warehouse", ItemKind = "Table"]}[Data],
    Typed = Table.TransformColumnTypes(RawTable, {
        {"warehouse_id",   Int64.Type},
        {"warehouse_name", type text},
        {"city",           type text},
        {"country",        type text},
        {"region",         type text},
        {"capacity_sqm",   Int64.Type},
        {"timezone",       type text}
    })
in
    Typed
```

### stg_dim_date
```m
let
    Source     = Lakehouse.Contents(null),
    Navigation = Source{[workspaceId = "17a38d06-25be-4b10-9f15-a08999f75886"]}[Data],
    Nav1       = Navigation{[lakehouseId = "8ba75944-9d92-4ad7-af0e-6dd71f1ee3d5"]}[Data],
    RawTable   = Nav1{[Id = "dim_date", ItemKind = "Table"]}[Data],
    Typed = Table.TransformColumnTypes(RawTable, {
        {"date",        type date},
        {"year",        Int64.Type},
        {"quarter",     Int64.Type},
        {"month",       Int64.Type},
        {"month_name",  type text},
        {"week",        Int64.Type},
        {"day_of_week", type text},
        {"is_weekend",  Int64.Type}
    })
in
    Typed
```

---

## TRF Queries (Enable staging = ON, destination = Fabric Warehouse, Replace mode)

### gold_stock_balance → inventory_warehouse.gold_stock_balance
```m
let
    fact = stg_fact_transactions,
    dimP = stg_dim_product,
    dimW = stg_dim_warehouse,

    WithSign = Table.AddColumn(fact, "signed_qty", each
        if   [transaction_type] = "PURCHASE" then  [quantity]
        else if [transaction_type] = "SALE"  then -[quantity]
        else [quantity], Int64.Type),

    WithPQty = Table.AddColumn(WithSign, "purchase_qty", each
        if [transaction_type] = "PURCHASE" then [quantity] else 0, Int64.Type),

    WithSQty = Table.AddColumn(WithPQty, "sold_qty", each
        if [transaction_type] = "SALE" then [quantity] else 0, Int64.Type),

    Grouped = Table.Group(WithSQty, {"product_id", "warehouse_id"}, {
        {"raw_stock_qty",   each List.Sum([signed_qty]),   Int64.Type},
        {"total_purchases", each List.Sum([purchase_qty]), Int64.Type},
        {"total_sold",      each List.Sum([sold_qty]),     Int64.Type},
        {"last_movement",   each List.Max([date]), type nullable datetime}
    }),

    WithDQ = Table.AddColumn(Grouped, "dq_negative_flag",
        each [raw_stock_qty] < 0, type logical),

    WithClamp = Table.AddColumn(WithDQ, "stock_qty", each
        if [raw_stock_qty] < 0 then 0 else [raw_stock_qty],
    Int64.Type),

    JP = Table.NestedJoin(WithClamp,{"product_id"},dimP,{"product_id"},"_p",JoinKind.LeftOuter),
    EP = Table.ExpandTableColumn(JP,"_p",
        {"product_name","category","reorder_point","safety_stock"},
        {"product_name","category","reorder_point","safety_stock"}),

    JW = Table.NestedJoin(EP,{"warehouse_id"},dimW,{"warehouse_id"},"_w",JoinKind.LeftOuter),
    EW = Table.ExpandTableColumn(JW,"_w",
        {"warehouse_name","city","country","region"},
        {"warehouse_name","city","country","region"}),

    WithStatus = Table.AddColumn(EW, "stock_status", each
        if   [stock_qty] <= 0                  then "Out of Stock"
        else if [stock_qty] <= [safety_stock]  then "Critical"
        else if [stock_qty] <= [reorder_point] then "Reorder Now"
        else "OK", type text),

    Result = Table.SelectColumns(WithStatus, {
        "product_id","product_name","category",
        "warehouse_id","warehouse_name","city","country","region",
        "stock_qty","raw_stock_qty","total_purchases","total_sold",
        "reorder_point","safety_stock","stock_status",
        "dq_negative_flag","last_movement"})
in
    Result
```

### gold_wac_cost → inventory_warehouse.gold_wac_cost
```m
let
    fact = stg_fact_transactions,
    dimP = stg_dim_product,

    Purchases = Table.SelectRows(fact, each [transaction_type] = "PURCHASE"),

    WithCostQty = Table.AddColumn(Purchases, "cost_x_qty",
        each [unit_cost] * [quantity], type number),

    Grouped = Table.Group(WithCostQty, {"product_id"}, {
        {"total_cost_x_qty", each List.Sum([cost_x_qty]),  type number},
        {"total_qty",        each List.Sum([quantity]),    Int64.Type},
        {"purchase_count",   each Table.RowCount(_),       Int64.Type},
        {"latest_cost", each
            let s = Table.Sort(_,{{"date", Order.Descending}})
            in s{0}[unit_cost], type number}
    }),

    WithWAC = Table.AddColumn(Grouped, "wac_cost", each
        if [total_qty] = 0 then null
        else Number.Round([total_cost_x_qty] / [total_qty], 2),
    type number),

    JP = Table.NestedJoin(WithWAC,{"product_id"},dimP,{"product_id"},"_p",JoinKind.LeftOuter),

    Result = Table.ExpandTableColumn(JP,"_p",
        {"product_name","category","base_price"},
        {"product_name","category","base_price"}),

    WithMargin = Table.AddColumn(Result, "gross_margin_pct", each
        if [base_price] = 0 then null
        else Number.Round(([base_price] - [wac_cost]) / [base_price] * 100, 1),
    type number)
in
    WithMargin
```

### gold_slow_movers → inventory_warehouse.gold_slow_movers
```m
let
    fact = stg_fact_transactions,
    dimP = stg_dim_product,

    Sales    = Table.SelectRows(fact, each [transaction_type] = "SALE"),
    Purchases= Table.SelectRows(fact, each [transaction_type] = "PURCHASE"),

    MaxDate  = Date.From(List.Max(fact[date])),

    Sales90  = Table.Group(Sales, {"product_id"}, {
        {"sold_90d", each
            let filtered = Table.SelectRows(_, each
                [date] >= DateTime.From(Date.AddDays(MaxDate, -90)))
            in List.Sum(filtered[quantity]),
        Int64.Type},
        {"last_sale_date", each List.Max([date]), type nullable datetime}
    }),

    PGroup   = Table.Group(Purchases, {"product_id"},
        {{"total_purchased", each List.Sum([quantity]), Int64.Type}}),

    SGroup   = Table.Group(Sales, {"product_id"},
        {{"total_sold_all", each List.Sum([quantity]), Int64.Type}}),

    J1 = Table.NestedJoin(PGroup,{"product_id"},SGroup,{"product_id"},"_s",JoinKind.LeftOuter),
    E1 = Table.ExpandTableColumn(J1,"_s",{"total_sold_all"},{"total_sold_all"}),

    WithStock = Table.AddColumn(E1, "current_stock", each
        [total_purchased] - (if [total_sold_all] = null then 0 else [total_sold_all]),
    Int64.Type),

    J2 = Table.NestedJoin(WithStock,{"product_id"},Sales90,{"product_id"},"_90",JoinKind.LeftOuter),
    E2 = Table.ExpandTableColumn(J2,"_90",
        {"sold_90d","last_sale_date"},{"sold_90d","last_sale_date"}),

    WithDOH  = Table.AddColumn(E2, "days_on_hand", each
        let rate = if [sold_90d] = null or [sold_90d] = 0 then 0.1
                   else [sold_90d] / 90
        in Number.Round([current_stock] / rate, 0),
    type number),

    WithFlag = Table.AddColumn(WithDOH, "slow_mover_flag", each
        if   [days_on_hand] >= 90 then "Critical (>90d)"
        else if [days_on_hand] >= 60 then "Warning (>60d)"
        else "Normal",
    type text),

    JP = Table.NestedJoin(WithFlag,{"product_id"},dimP,{"product_id"},"_p",JoinKind.LeftOuter),

    Result = Table.ExpandTableColumn(JP,"_p",
        {"product_name","category","reorder_point"},
        {"product_name","category","reorder_point"})
in
    Result
```

### gold_margin_kpis → inventory_warehouse.gold_margin_kpis
```m
let
    fact = stg_fact_transactions,
    dimP = stg_dim_product,
    dimW = stg_dim_warehouse,
    dimD = stg_dim_date,

    Sales = Table.SelectRows(fact, each [transaction_type] = "SALE"),

    WithRevCogs = Table.AddColumn(
        Table.AddColumn(Sales,
            "revenue", each [unit_price] * [quantity], type number),
        "cogs", each [unit_cost] * [quantity], type number),

    WithYM = Table.AddColumn(WithRevCogs, "year_month", each
        Date.ToText(Date.From([date]), "yyyy-MM"),
    type text),

    JP = Table.NestedJoin(WithYM, {"product_id"}, dimP, {"product_id"}, "_p", JoinKind.LeftOuter),
    EP = Table.ExpandTableColumn(JP, "_p", {"category"}, {"category"}),

    JW = Table.NestedJoin(EP, {"warehouse_id"}, dimW, {"warehouse_id"}, "_w", JoinKind.LeftOuter),
    EW = Table.ExpandTableColumn(JW, "_w", {"warehouse_name","city","country"}, {"warehouse_name","city","country"}),

    Grouped = Table.Group(EW, {"year_month","category","warehouse_name","city","country"}, {
        {"total_revenue",     each List.Sum([revenue]),   type number},
        {"total_cogs",        each List.Sum([cogs]),      type number},
        {"units_sold",        each List.Sum([quantity]),  Int64.Type},
        {"transaction_count", each Table.RowCount(_),     Int64.Type}
    }),

    WithGP = Table.AddColumn(Grouped, "gross_profit",
        each [total_revenue] - [total_cogs], type number),

    WithMargin = Table.AddColumn(WithGP, "gross_margin_pct", each
        if [total_revenue] = 0 then null
        else Number.Round([gross_profit] / [total_revenue] * 100, 1),
    type number),

    WithDate = Table.AddColumn(
        WithMargin,
        "month_date",
        each Date.FromText([year_month] & "-01"),
        type date),

    Result = Table.Sort(WithDate, {{"year_month", Order.Ascending}})
in
    Result
```

### gold_stock_movement → inventory_warehouse.gold_stock_movement
```m
let
    fact = stg_fact_transactions,
    dimP = stg_dim_product,
    dimW = stg_dim_warehouse,

    WithYM = Table.AddColumn(fact, "year_month",
        each Date.ToText(Date.From([date]), "yyyy-MM"),
        type text),

    WithDate = Table.AddColumn(WithYM, "txn_date",
        each Date.From([date]),
        type date),

    WithQty = Table.AddColumn(WithDate, "signed_qty",
        each if [transaction_type] = "PURCHASE" then [quantity]
             else if [transaction_type] = "SALE" then -[quantity]
             else [quantity],
        type number),

    WithCost = Table.AddColumn(WithQty, "total_cost",
        each [unit_cost] * [quantity], type number),

    WithRevenue = Table.AddColumn(WithCost, "total_revenue",
        each if [transaction_type] = "SALE"
             then [unit_price] * [quantity]
             else 0,
        type number),

    JP = Table.NestedJoin(WithRevenue, {"product_id"}, dimP, {"product_id"}, "_p", JoinKind.LeftOuter),
    EP = Table.ExpandTableColumn(JP, "_p", {"product_name","category","supplier"}, {"product_name","category","supplier"}),

    JW = Table.NestedJoin(EP, {"warehouse_id"}, dimW, {"warehouse_id"}, "_w", JoinKind.LeftOuter),
    EW = Table.ExpandTableColumn(JW, "_w", {"warehouse_name","city","country"}, {"warehouse_name","city","country"}),

    Result = Table.SelectColumns(EW, {
        "transaction_id","txn_date","year_month",
        "product_id","product_name","category","supplier",
        "warehouse_id","warehouse_name","city","country",
        "transaction_type","quantity","signed_qty",
        "unit_cost","unit_price","total_cost","total_revenue",
        "lot_number","reference"
    })
in
    Result
```
