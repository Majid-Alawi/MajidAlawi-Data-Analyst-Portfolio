# Supply Chain Logistics Optimization & Bottleneck Analysis

![Python](https://img.shields.io/badge/Python-Pandas%20%7C%20NumPy-3776AB?logo=python&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-Window%20Functions%20%7C%20CTEs-4479A1?logo=mysql&logoColor=white)
![Power BI](https://img.shields.io/badge/Power%20BI-DAX%20%7C%20Power%20Query-F2C811?logo=powerbi&logoColor=black)
![Status](https://img.shields.io/badge/Status-Complete-success)

End-to-end analytics pipeline that audits order fulfillment, carrier performance, freight cost and warehouse capacity for a multi-plant logistics network. Raw Excel sheets are cleaned in Python, warehoused in MySQL, analysed with advanced SQL, and delivered as an executive Power BI dashboard.

![Dashboard preview](Images/dashboard_preview.png)

---

## Executive Summary & Core Metric Baselines

The network delivers **98% OTIF** across **9,215 orders**, but the headline hides a structural risk: **one plant handles 92.7% of all orders and runs at 843% of its daily capacity.** Service quality is strong today because orders ship early, not because capacity has headroom.

| Metric | Baseline |
|---|---|
| **OTIF Ratio** | **98% (97.9%: 9,023 of 9,215 orders with zero late days)** |
| Total orders analysed | 9,215 |
| Carriers / service levels / plants | 3 / 3 / 7 |
| Customers / products | 46 / 772 |
| Orders shipped ahead of schedule | 52.0% (4,789 orders) |
| Late-shipment orders | 192 (2.1%) |
| Plants breaching daily capacity | 4 of 7 |
| Overflow orders above capacity | 7,708 |
| Top node share of orders (PLANT03) | 92.7% |
| Highest spend-concentration cohort | W4 / P3 / Short, 79.9% of estimated freight spend |

**Bottom line:** fulfillment performance is healthy, but it depends on early shipping and a single overloaded node. The analysis pinpoints where cost and capacity risk sit so operations can act before service levels slip.

---

## Directory Map

```text
4_Supply_Chain_Logistics/
├── README.md
├── 1_data_cleaning.ipynb                      # Phase 1: Python ETL
├── Images/
│   └── dashboard_preview.png
├── Data/
│   ├── Supply chain lgistics problem.xlsx     # Raw 7-sheet source workbook
│   ├── Clean_Supply_Chain_Logistics_Problem.xlsx
│   ├── clean_orderlist.csv
│   ├── clean_freightrates.csv
│   ├── clean_whcapacities.csv
│   ├── clean_whcosts.csv
│   ├── clean_plantports.csv
│   ├── clean_productsperplant.csv
│   ├── clean_vmicustomers.csv
│   ├── anomaly_missing_order_ports.csv        # Exception report (0 rows found)
│   └── anomaly_missing_lane_ports.csv         # Exception report (0 rows found)
└── Scripts/
    ├── Carrier_Delay_Velocity.sql
    ├── Route_Cost_Cohort_Analysis.sql
    ├── High_Risk_Bottleneck_Tracking.sql
    └── Supply_Chain_Logistics_Dashboard.pbix  # Executive dashboard
```

---

## Pipeline Breakdown

```text
Excel (7 sheets) ──► Python ETL ──► Clean CSV/XLSX ──► MySQL warehouse ──► SQL analysis ──► Power BI dashboard
```

### 1. Python ETL (Jupyter)

**Source:** `Supply chain lgistics problem.xlsx` with 7 sheets: `OrderList`, `FreightRates`, `WhCosts`, `WhCapacities`, `ProductsPerPlant`, `VmiCustomers`, `PlantPorts`.

| Step | What it does | Why it matters |
|---|---|---|
| Ingestion | `pd.read_excel(sheet_name=None)` loads all sheets into one dict; an `assert` fails fast if a sheet is missing or renamed | Every later step is a loop over one structure |
| Schema standardization | Headers cleaned to lowercase `snake_case`, with a regex that also fixes headers like `Cost/unit` | Predictable join keys across tables |
| ID hygiene | ID columns cast to trimmed text, `101.0` float artifacts stripped, `'nan'` restored to a true null | Prevents silent join mismatches |
| Anomaly isolation | Rows with missing origin, destination or lane ports are quarantined into `anomaly_missing_order_ports.csv` and `anomaly_missing_lane_ports.csv` before any null filling | Unroutable records are reviewed, never silently dropped (this dataset produced 0 exceptions) |
| Defensive cleaning | Text nulls labelled `'Not Specified'`; numeric nulls kept as NULL so a missing rate never looks like a free shipment | Protects averages and cost totals |
| De-duplication | 3 exact duplicate lanes removed from `freightrates` (1,540 to 1,537 rows) | Prevents double-counted freight rates in joins |
| Validation | Asserts for lowercase headers, zero text nulls, no filler ports, non-empty tables, and **row conservation** (`clean + anomaly = raw`) | Export only happens if the data passes every check |
| Export | One consolidated workbook plus one CSV per table | Excel for review, CSV for database loading |

**Cleaned table baselines**

| Table | Rows | Columns |
|---|---|---|
| `orderlist` | 9,215 | 14 |
| `freightrates` | 1,537 | 11 |
| `productsperplant` | 2,036 | 2 |
| `plantports` | 22 | 2 |
| `whcosts` | 19 | 2 |
| `whcapacities` | 19 | 2 |
| `vmicustomers` | 14 | 2 |

### 2. MySQL Workbench Warehousing

Clean tables are streamed from Python into the `supply_chain_logistics` schema with SQLAlchemy and PyMySQL, using a **chunked load** (`chunksize=500`) and explicit column types (`INT`, `FLOAT`, `DATETIME`, `VARCHAR(100)`).

```python
df.to_sql(name, con=engine, if_exists='replace', index=False, dtype=sql_types[name], chunksize=500)
```

**Load safeguards**
- A connection test asserts the active database before any write.
- A `VARCHAR(100)` length check prevents silent text truncation.
- Post-load assertions compare CSV row and column counts with `COUNT(*)` and `information_schema.columns`.
- `if_exists='replace'` keeps the loader safely re-runnable.

**Relational joins** connect operational boundaries across tables. Warehouse cost (`whcosts.wh`) and capacity (`whcapacities.plant_id`) map directly to `orderlist.plant_code`, and orders map to freight rate cards on carrier, origin port, destination port, service level and weight bracket.

**Analytical SQL scripts** (all CTE-driven, UPPERCASE keywords, window functions throughout):

| Script | Business question | Techniques |
|---|---|---|
| `Carrier_Delay_Velocity.sql` | How often and how long are carriers late, and is it getting better or worse? | Lane benchmark CTE, `AVG() OVER` with a 7-row frame, `LAG`, `DENSE_RANK` |
| `Route_Cost_Cohort_Analysis.sql` | Which weight, price and distance cohorts carry inefficient freight cost? | Rate card CTE, `NTILE`, weighted benchmark with `SUM() OVER (PARTITION BY ...)`, `RANK` |
| `High_Risk_Bottleneck_Tracking.sql` | Which plants breach daily capacity and what does the overflow cost? | `LEFT JOIN` to capacity and cost, `SUM() OVER`, `LAG`, `RANK`, tiered risk flag |

Each script aggregates lookup tables to one row per join key **before** joining, so the fact table cannot fan out and inflate counts.

### 3. Power BI Analytics

**Dashboard file:** `Scripts/Supply_Chain_Logistics_Dashboard.pbix` (1920 × 1080 executive canvas).

**Theme:** Corporate Slate and High-Contrast Amber.

| Role | Hex |
|---|---|
| Slate (primary text) | `#212529` |
| Slate muted | `#6C757D` |
| Header band | `#F8F9FA` |
| Amber accent | `#D97706` |
| Deep teal (data series) | `#074650` |

**Power Query cleaning:** conditional columns replace raw database strings with corporate labels, for example carrier `V444_0` becomes **Logistics Express** (exposed as `Clean Carrier Name`) and service code `DTP` becomes **Door-to-Port**, so stakeholders never read system codes.

**DAX measures**

```dax
Total Orders = COUNTROWS ( 'supply_chain_logistics orderlist' )

OTIF Orders =
CALCULATE (
    [Total Orders],
    'supply_chain_logistics orderlist'[ship_late_day_count] = 0
)

OTIF Ratio = DIVIDE ( [OTIF Orders], [Total Orders], 0 )
```

`DIVIDE` with an alternate result of `0` makes the ratio error-safe when a slicer selection returns no orders.

**Dashboard components**

| Visual | Fields | Purpose |
|---|---|---|
| KPI cards | `OTIF Ratio`, `Average Lead Time`, `Total Volume Shipped`, `High Weight Shipments` | Headline health check |
| Clustered bar | `Average Lead Time` by `Clean Carrier Name` | Carrier lead time performance |
| Clustered column | `Total Orders` by `ship_ahead_day_count` | Fulfillment schedule variance distribution |
| Decomposition tree | `Total Orders` explained by origin and destination port | Lane-level drill-down |
| Pie chart | `Total Orders` by service level | Service mix |
| Table | Warehouse list (`wh`) from the cost table | Plant reference |
| Slicer | `plant_code` | Plant-level filtering |

---

## Key Operational Insights

### Fulfillment Schedule Variance Distribution

| Days shipped ahead of schedule | Orders | Share |
|---|---|---|
| 0 (on schedule) | 4,426 | 48.0% |
| 1 | 117 | 1.3% |
| 3 | 3,206 | 34.8% |
| 5 | 1,462 | 15.9% |
| 6 | 4 | <0.1% |

**What it means for stakeholders**
- **52.0% of orders ship ahead of schedule**, mostly in 3-day and 5-day blocks. Early dispatch is what holds OTIF near 98%, and it works as a buffer against late shipments (192 late orders, 2.1%).
- The tight clustering at 3 and 5 days suggests promise dates carry deliberate slack. Over-quoting lead times to customers protects the OTIF score but may be giving away competitive speed.
- Early shipping pulls volume forward onto nodes that are already overloaded. At the capacity-limited plant, that pressure can turn the buffer into a bottleneck.

### Carrier Lead Time Performance

| Carrier | Orders | Avg transit (days) | Late-shipment orders |
|---|---|---|---|
| Logistics Express (`V444_0`) | 6,264 | 2.00 | 183 |
| `V444_1` | 2,097 | 1.05 | 9 |
| `V44_3` | 854 | 1.29 | 0 |

**What it means for stakeholders**
- **Logistics Express carries 68% of volume and is the slowest carrier at 2.00 days on average**, almost twice the transit time of `V444_1`. It also accounts for 183 of the 192 late-shipment orders (95%). This is the first carrier to review in a contract negotiation.
- The two delay lenses point at different problems. The OTIF measure counts late shipments, where Logistics Express leads. The SQL delay script also counts transit beyond contracted days, where `V444_1` shows the highest rate (5.82%, against 3.85% for `V444_0`). Fixing dispatch discipline and fixing carrier transit overruns are separate workstreams.
- Heavy dependence on one carrier is itself a risk. Shifting even part of the volume to faster lanes would cut average lead time.

### Cost and Capacity Risk

- **Capacity concentration:** PLANT03 processes 8,541 of 9,215 orders (92.7%) against a daily capacity of 1,013, a utilization of 843%. It generates 7,528 of the 7,708 overflow orders.
- **Network shortfall:** the seven plants have 2,748 orders of combined daily capacity against 9,215 orders placed. Rerouting alone cannot clear the overflow, because the three plants within capacity have only about 1,240 orders of spare room between them.
- **Cost concentration:** the W4 / P3 / Short cohort (heaviest weight bracket, top price tier, short distance) holds 79.9% of estimated freight spend at 4.98 per kg, against a bracket benchmark of 0.53. It is the clearest target for rate renegotiation or shipment consolidation.

---

## Recommendations

1. **Relieve the capacity bottleneck first.** PLANT03 is the single point of failure. Rebalance order allocation to the three plants with spare room, then size additional capacity for the remaining shortfall.
2. **Open a performance review with Logistics Express.** It combines the longest transit times with 95% of late shipments on 68% of volume.
3. **Renegotiate or consolidate the W4 / P3 / Short lanes.** They hold 79.9% of estimated freight spend at roughly nine times the bracket benchmark per kg.
4. **Review promise-date slack.** If most orders ship 3 to 5 days early, tighter quoted lead times could be a commercial advantage without hurting OTIF.

---

## Data Notes & Limitations

- **Single-day snapshot:** all 9,215 orders share one order date (2013-05-26). Trailing-window and `LAG` logic in the SQL scripts is built for multi-day data but cannot show trends here, so results are read as a ranked snapshot.
- **OTIF definition:** an order counts as on time when `ship_late_day_count = 0`. The dataset has no order-quantity fulfillment field, so "in full" is not independently measurable.
- **Capacity scale:** utilization compares order counts with `daily_capacity`, assuming capacity is expressed per order. Summed `unit_quantity` is on a different scale and is not used for breach tests.
- **Distance proxy:** the dataset has no distance field, so contracted transit days stand in for distance cohorts.
- **Estimated freight cost:** cost is modelled as the higher of the minimum charge and rate times weight. Orders without a matching rate card row are excluded from cost metrics.

---

## Skills Demonstrated

| Area | Evidence |
|---|---|
| Data cleaning and validation | Schema standardization, ID hygiene, anomaly quarantine, de-duplication, row-conservation asserts |
| Data engineering | Chunked, typed, assertion-checked Python to MySQL load |
| Advanced SQL | CTEs, `NTILE`, `LAG`, `RANK`, `DENSE_RANK`, framed `AVG` and `SUM OVER`, fan-out prevention |
| BI and storytelling | Executive dashboard, DAX with error-safe division, Power Query relabelling, themed layout |
| Business analysis | Capacity concentration, carrier performance, cost-cohort inefficiency, actionable recommendations |

---

## How to Reproduce

1. Place the source workbook in `Data/` and run `1_data_cleaning.ipynb` top to bottom (Python 3.13, `pandas`, `numpy`, `openpyxl`).
2. Create the load connection with `sqlalchemy`, `pymysql` and `cryptography`, then run the MySQL upload cells to build the `supply_chain_logistics` schema.
3. Run the three scripts in `Scripts/` in MySQL Workbench.
4. Open `Scripts/Supply_Chain_Logistics_Dashboard.pbix` in Power BI Desktop and refresh against the local MySQL instance.

---

## Tech Stack

| Layer | Tools |
|---|---|
| Ingestion and ETL | Python, Pandas, NumPy, Jupyter, openpyxl |
| Warehouse | MySQL, SQLAlchemy, PyMySQL |
| Analysis | Advanced SQL (CTEs, window functions) |
| Visualization | Power BI Desktop, DAX, Power Query |