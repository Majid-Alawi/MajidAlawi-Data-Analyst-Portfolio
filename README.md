[README.md](https://github.com/user-attachments/files/34326942/README.md)# End-to-End E-commerce Analytics \& Data Pipeline Portfolio Case Study

A transaction dataset of 138,116 rows, cleaned in Python, stored in MySQL, and reported in Power BI. Every dashboard figure comes from a SQL query against one table, `fact\_sales`, so each number can be traced and reproduced.

## Core Workflow \& Data Lineage

```text
DATA SOURCE (CSV)
  ecommerce\_sales\_customer\_analytics\_150k.csv    138,116 rows x 46 cols
  order\_items.csv / customer\_master.csv / product\_catalog.csv
        |
        v
PYTHON ETL (Jupyter Notebook: Pandas, NumPy, SQLAlchemy)
  standardize headers -> normalize keys -> validate nulls and zeros
  -> load in 5,000-row chunks -> validate row count
        |
        v
MYSQL WAREHOUSE (localhost:3306)
  database: ecommerce\_analytics
  table:    fact\_sales (138,116 rows x 46 cols)
  4 KPI scripts
        |
        v
POWER BI PRESENTATION
  executive dashboard with regional slicer
```

The sales file held 138,116 rows when it was loaded and 138,116 rows at every check after. No rows were dropped. The `150k` in the filename is not a row count.

## Phase 1: Python Processing \& Database Migration

**Schema standardization**

Applied to all four tables in place, so `fact\_sales` inherits it:

* Column headers were stripped, lowercased, and converted to snake\_case. Keys are identical across the sales, customer, and product tables, so joins match and MySQL column names need no quoting.
* ID columns (`customer\_id`, `order\_id`, `product\_id`) were cast to text, trimmed, and stripped of float artifacts such as `101.0`. Left as floats, the same ID would fail to match across tables.

**Null counts in the sales table**

|Column group|Nulls|
|-|-|
|`delivery\_days`, `estimated\_delivery\_days`, `customer\_rating`, `review\_sentiment`, `customer\_review`|24,557 each|
|`return\_status`, `return\_reason`|128,654 each|
|`campaign\_name`|83,233|
|`coupon\_code`|110,502|

The customer, item, and product tables had no nulls.

**Nulls versus zeros in `fact\_sales`**

`AVG()` skips NULL and counts 0 as a value, so the two must stay separate. Missing values are kept as NULL in `fact\_sales`. Real zeros are kept as 0.

The zero and null counts were validated against the raw file, and row order was confirmed with an assertion on `net\_sales`.

|Column|Real zeros|Missing (NULL)|
|-|-|-|
|`delivery\_days`|6,674|24,557|
|`estimated\_delivery\_days`|5,794|24,557|
|`customer\_rating`|0|24,557|

**Master file for external use**

A separate cleaned export, `cleaned\_ecommerce\_master\_sales.csv` (397,569 rows x 56 cols), joins line items, customers, and products to the sales table. It fills missing numbers with `0` and missing text with `Not Specified`, and parses date columns with `errors='coerce'`. The notebook generates this file (In \[6]). It is about 200 MB, so it is excluded from the repo, and it is not the source for `fact\_sales`.

* Merges use `validate='one\_to\_many'` and `validate='many\_to\_one'`. Pandas raises an error if a join duplicates rows by mistake.
* The master file has more rows than the sales table because one order can hold several line items.
* Cleaning ran on copies, so the raw data stayed untouched.

**Upload logic**

`fact\_sales` is loaded into MySQL with `DataFrame.to\_sql()` through a SQLAlchemy engine, using `chunksize=5000`.

* Each batch sends 5,000 rows, so memory use and connection load stay flat regardless of table size.
* A single 138k-row import froze MySQL Workbench. The chunked load through Python did not.
* After the load, `SELECT COUNT(\*)` on `fact\_sales` is compared to `len(df)`. Both must equal 138,116.

The upload step runs locally and is not included in the published notebook.

## Phase 2: Relational Database Aggregations

Four scripts run against `fact\_sales`, plus `Field\_Names.sql` (`DESCRIBE fact\_sales`) as a schema check:

|Script|Question it answers|
|-|-|
|`Total\_Performance\_Summary.sql`|Revenue, profit, margin, order volume|
|`Channel\_Insights.sql`|Net sales by sales channel|
|`Logistics\_Efficiency.sql`|Average delivery days by region|
|`Segment\_Metrics.sql`|Average rating and customer age by segment|

**Total Performance Summary**

```sql
-- 1. Total Performance Summary: Revenue, Profit, Margin %, Order Volume
SELECT 
    ROUND(SUM(net\_sales), 2)                                  AS total\_revenue,
    ROUND(SUM(profit), 2)                                     AS total\_profit,
    ROUND((SUM(profit) / NULLIF(SUM(net\_sales), 0)) \* 100, 2) AS profit\_margin\_pct,
    COUNT(DISTINCT order\_id)                                  AS total\_orders
FROM fact\_sales;
```

* `NULLIF` turns a zero denominator into NULL, so the margin calculation cannot fail on a divide-by-zero.
* `COUNT(DISTINCT order\_id)` counts orders, not rows.
* Margin is summed profit over summed sales, not an average of row-level margins. This weights large orders correctly.

## Phase 3: Visual Intelligence Engineering

**Headline metrics**

|Metric|Value|
|-|-|
|Revenue|$177M|
|Profit|$76M|
|Orders|138K|
|Margin|43%|

**Layout**

* **Palette:** slate and charcoal. Neutral backgrounds keep attention on the numbers.
* **Regional slicer:** one dropdown filters every visual on the page.

**Axis floors**

|Chart|Axis minimum|Reason|
|-|-|-|
|Delivery days|X-axis at 4.0|Regional averages sit within a fraction of a day of each other|
|Customer ratings|Y-axis at 3.0|Segment ratings differ by a few tenths of a point|

Power BI defaults to a zero baseline. At zero, bars that differ by 0.2 look identical, and the chart says nothing. Raising the floor spreads the bars apart so the ranking is readable.

The trade-off is that truncated axes exaggerate small gaps. Both minimums are labeled on the charts so the scale is visible.

!\[Executive dashboard](dashboard/dashboard\_screenshot.png)

## Tech Stack

Python (Pandas, NumPy, SQLAlchemy), Jupyter Notebook, MySQL, Power BI

