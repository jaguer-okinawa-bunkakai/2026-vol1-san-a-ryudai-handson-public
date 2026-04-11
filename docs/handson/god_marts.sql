-- =============================================================================
-- 神マート（God Marts）定義
-- =============================================================================
-- Jagu'e'r 沖縄分科会 Meetup #8（2026-04-11）
-- サンエー POSデータ（2025年8〜9月）を完全に分析するためのデータマート群
--
-- 対応課題:
--   共通課題: 売上が一番高かった日はいつ？
--   Q1: 旧盆に何が売れた？通常の何倍？
--   Q2: 曜日で売上に差はある？
--   Q3: 一番売れている商品は？時期で変わる？
--   Q4: 台風が来ると何が売れる？（8/19前後）
--   Q5: 旧盆が4日間ある店舗は？
--   Q6: 営業時間が早く終わる日は？
--
-- 使い方:
--   {PROJECT_ID} を自分のプロジェクトIDに置換して実行
--   {DATASET} を自分のデータセット名に置換して実行
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. mart_god_calendar — イベントカレンダーマスター
-- ---------------------------------------------------------------------------
-- 全マートの基盤。日付に曜日・旧盆・台風などのイベントフラグを付与。
-- 対応: 共通課題, Q2, Q4, Q5, Q6
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET}.mart_god_calendar` AS
WITH date_range AS (
  SELECT FORMAT_DATE('%Y%m%d', d) AS date_key, d AS date_val
  FROM UNNEST(GENERATE_DATE_ARRAY('2025-08-01', '2025-09-30')) AS d
)
SELECT
  date_key,
  date_val,
  FORMAT_DATE('%Y-%m-%d', date_val) AS date_iso,
  EXTRACT(MONTH FROM date_val) AS month_num,
  FORMAT_DATE('%m月', date_val) AS month_label,
  EXTRACT(ISOWEEK FROM date_val) AS week_num,
  FORMAT_DATE('%a', date_val) AS dow_short,        -- Mon,Tue...
  EXTRACT(DAYOFWEEK FROM date_val) AS dow_number,  -- 1=Sun,...,7=Sat
  CASE EXTRACT(DAYOFWEEK FROM date_val)
    WHEN 1 THEN '日' WHEN 2 THEN '月' WHEN 3 THEN '火'
    WHEN 4 THEN '水' WHEN 5 THEN '木' WHEN 6 THEN '金' WHEN 7 THEN '土'
  END AS dow_ja,
  CASE
    WHEN EXTRACT(DAYOFWEEK FROM date_val) IN (1, 7) THEN TRUE
    ELSE FALSE
  END AS is_weekend,

  -- 旧盆フラグ（2025年旧暦7月13〜15日 = 新暦9/4〜9/6）
  CASE
    WHEN date_key = '20250903' THEN '旧盆前日（買い出しピーク）'
    WHEN date_key = '20250904' THEN 'ウンケー（迎え盆）'
    WHEN date_key = '20250905' THEN 'ナカヌヒー（中日）'
    WHEN date_key = '20250906' THEN 'ウークイ（送り盆）'
    WHEN date_key = '20250907' THEN '旧盆翌日'
    ELSE NULL
  END AS obon_label,
  CASE WHEN date_key BETWEEN '20250904' AND '20250906' THEN TRUE ELSE FALSE END AS is_obon,
  CASE WHEN date_key BETWEEN '20250903' AND '20250907' THEN TRUE ELSE FALSE END AS is_obon_extended,

  -- 台風フラグ（台風LINGLING: 8/19直撃）
  CASE
    WHEN date_key = '20250818' THEN '台風前日（備蓄買い）'
    WHEN date_key = '20250819' THEN '台風直撃日'
    WHEN date_key = '20250820' THEN '台風明け（回復買い）'
    ELSE NULL
  END AS typhoon_label,
  CASE WHEN date_key BETWEEN '20250818' AND '20250820' THEN TRUE ELSE FALSE END AS is_typhoon_period,

  -- 期間区分
  CASE
    WHEN date_key BETWEEN '20250904' AND '20250906' THEN '旧盆'
    WHEN date_key BETWEEN '20250818' AND '20250820' THEN '台風'
    ELSE '通常'
  END AS period_type
FROM date_range;


-- ---------------------------------------------------------------------------
-- 2. mart_god_daily_overview — 日別全店サマリー（イベント情報付き）
-- ---------------------------------------------------------------------------
-- 全店合計の日別売上にカレンダー情報を結合。
-- 対応: 共通課題（最高売上日）, Q2（曜日別）, Q4（台風の凹み）, Q6（取引数異常日）
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET}.mart_god_daily_overview` AS
SELECT
  c.*,
  COALESCE(d.store_count, 0) AS store_count,
  COALESCE(d.total_transactions, 0) AS total_transactions,
  COALESCE(d.total_lines, 0) AS total_lines,
  COALESCE(d.total_quantity, 0) AS total_quantity,
  COALESCE(d.total_sales, 0) AS total_sales,
  COALESCE(d.total_customers, 0) AS total_customers,
  SAFE_DIVIDE(d.total_sales, d.total_transactions) AS avg_transaction_amount,
  SAFE_DIVIDE(d.total_sales, d.total_customers) AS avg_customer_spend
FROM `{PROJECT_ID}.{DATASET}.mart_god_calendar` c
LEFT JOIN (
  SELECT
    usage_date,
    COUNT(DISTINCT store_name) AS store_count,
    SUM(transaction_count) AS total_transactions,
    SUM(line_count) AS total_lines,
    SUM(total_quantity) AS total_quantity,
    SUM(total_sales) AS total_sales,
    SUM(unique_customers) AS total_customers
  FROM `{PROJECT_ID}.{DATASET}.mart_daily_sales`
  GROUP BY usage_date
) d ON c.date_key = d.usage_date
ORDER BY c.date_key;


-- ---------------------------------------------------------------------------
-- 3. mart_god_store_daily — 店舗×日別売上（イベント情報付き）
-- ---------------------------------------------------------------------------
-- 店舗別の日別売上にカレンダー情報を結合。
-- 対応: Q5（旧盆4日間店舗）, 共通課題（店舗別ランキング）
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET}.mart_god_store_daily` AS
SELECT
  c.date_key,
  c.date_iso,
  c.dow_ja,
  c.is_weekend,
  c.obon_label,
  c.is_obon,
  c.is_obon_extended,
  c.typhoon_label,
  c.is_typhoon_period,
  c.period_type,
  d.store_name,
  d.transaction_count,
  d.line_count,
  d.total_quantity,
  d.total_sales,
  d.unique_customers,
  SAFE_DIVIDE(d.total_sales, d.transaction_count) AS avg_transaction_amount,
  SAFE_DIVIDE(d.total_sales, d.unique_customers) AS avg_customer_spend
FROM `{PROJECT_ID}.{DATASET}.mart_daily_sales` d
JOIN `{PROJECT_ID}.{DATASET}.mart_god_calendar` c ON d.usage_date = c.date_key;


-- ---------------------------------------------------------------------------
-- 4. mart_god_dow_summary — 曜日別サマリー（旧盆・台風除外版付き）
-- ---------------------------------------------------------------------------
-- 曜日ごとの平均売上・客数・客単価。イベント日を除外した「通常パターン」も算出。
-- 対応: Q2（曜日別売上差）
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET}.mart_god_dow_summary` AS
WITH daily AS (
  SELECT * FROM `{PROJECT_ID}.{DATASET}.mart_god_daily_overview`
  WHERE total_sales > 0
)
SELECT
  dow_number,
  dow_ja,

  -- 全日含む
  COUNT(*) AS days_count_all,
  ROUND(AVG(total_sales)) AS avg_sales_all,
  ROUND(AVG(total_transactions)) AS avg_txn_all,
  ROUND(AVG(SAFE_DIVIDE(total_sales, total_transactions))) AS avg_unit_price_all,
  ROUND(AVG(total_customers)) AS avg_customers_all,

  -- 通常日のみ（旧盆・台風除外）
  COUNTIF(period_type = '通常') AS days_count_normal,
  ROUND(AVG(IF(period_type = '通常', total_sales, NULL))) AS avg_sales_normal,
  ROUND(AVG(IF(period_type = '通常', total_transactions, NULL))) AS avg_txn_normal,
  ROUND(AVG(IF(period_type = '通常', SAFE_DIVIDE(total_sales, total_transactions), NULL))) AS avg_unit_price_normal,
  ROUND(AVG(IF(period_type = '通常', total_customers, NULL))) AS avg_customers_normal

FROM daily
GROUP BY dow_number, dow_ja
ORDER BY dow_number;


-- ---------------------------------------------------------------------------
-- 5. mart_god_product_daily — 商品×日別売上
-- ---------------------------------------------------------------------------
-- customer_sales_details と food_item_master を事前結合。
-- 75M行のフルスキャンを毎回避けるための核心マート。
-- 対応: Q1（旧盆商品）, Q3（売れ筋変動）, Q4（台風前後の商品）
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET}.mart_god_product_daily` AS
SELECT
  c.date_key,
  c.date_iso,
  c.dow_ja,
  c.month_num,
  c.obon_label,
  c.is_obon,
  c.is_obon_extended,
  c.typhoon_label,
  c.is_typhoon_period,
  c.period_type,
  sd.store_name,
  sd.product_code,
  f.product_name,
  f.department_code,
  f.mid_category,
  f.sub_category,
  f.brand_name,
  COUNT(DISTINCT CONCAT(sd.card_no, sd.store_name, CAST(sd.usage_date AS STRING), sd.trans_no)) AS transaction_count,
  SUM(sd.quantity) AS total_quantity,
  SUM(sd.amount) AS total_amount,
  SUM(sd.tax_included_amount) AS total_amount_tax_incl,
  COUNT(DISTINCT sd.card_no) AS unique_buyers
FROM `{PROJECT_ID}.{DATASET}.customer_sales_details` sd
JOIN `{PROJECT_ID}.{DATASET}.mart_god_calendar` c
  ON CAST(sd.usage_date AS STRING) = c.date_key
LEFT JOIN `{PROJECT_ID}.{DATASET}.food_item_master` f
  ON sd.product_code = CAST(f.product_code AS STRING)
WHERE sd.tax_included_amount > 0
GROUP BY
  c.date_key, c.date_iso, c.dow_ja, c.month_num,
  c.obon_label, c.is_obon, c.is_obon_extended,
  c.typhoon_label, c.is_typhoon_period, c.period_type,
  sd.store_name, sd.product_code,
  f.product_name, f.department_code, f.mid_category, f.sub_category, f.brand_name;


-- ---------------------------------------------------------------------------
-- 6. mart_god_product_ranking_monthly — 月別商品ランキング
-- ---------------------------------------------------------------------------
-- 8月 vs 9月の売れ筋変動を直接比較可能。
-- 対応: Q3（時期で変わるか）
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET}.mart_god_product_ranking_monthly` AS
SELECT
  month_num,
  CASE month_num WHEN 8 THEN '8月' WHEN 9 THEN '9月' END AS month_label,
  product_code,
  product_name,
  department_code,
  mid_category,
  sub_category,
  brand_name,
  SUM(total_quantity) AS total_qty,
  SUM(total_amount) AS total_revenue,
  SUM(total_amount_tax_incl) AS total_revenue_tax_incl,
  SUM(unique_buyers) AS total_buyers,
  COUNT(DISTINCT date_key) AS days_sold,
  RANK() OVER (
    PARTITION BY month_num
    ORDER BY SUM(total_amount) DESC
  ) AS revenue_rank,
  RANK() OVER (
    PARTITION BY month_num
    ORDER BY SUM(total_quantity) DESC
  ) AS qty_rank
FROM `{PROJECT_ID}.{DATASET}.mart_god_product_daily`
WHERE product_name IS NOT NULL
GROUP BY month_num, product_code, product_name, department_code, mid_category, sub_category, brand_name;


-- ---------------------------------------------------------------------------
-- 7. mart_god_obon_product_comparison — 旧盆 vs 通常期間 商品比較
-- ---------------------------------------------------------------------------
-- 旧盆期間の商品売上を「通常の土曜日（8月）」と比較し倍率を算出。
-- 対応: Q1（旧盆に何が売れた？通常の何倍？）
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET}.mart_god_obon_product_comparison` AS
WITH obon AS (
  -- 旧盆期間（9/4〜9/6）の商品別売上
  SELECT
    product_code,
    product_name,
    department_code,
    brand_name,
    SUM(total_quantity) AS obon_qty,
    SUM(total_amount) AS obon_revenue,
    SUM(total_amount_tax_incl) AS obon_revenue_tax_incl,
    SUM(unique_buyers) AS obon_buyers,
    COUNT(DISTINCT date_key) AS obon_days
  FROM `{PROJECT_ID}.{DATASET}.mart_god_product_daily`
  WHERE is_obon = TRUE
  GROUP BY product_code, product_name, department_code, brand_name
),
normal_sat AS (
  -- 通常の土曜日（8月の土曜日、旧盆除外）の1日あたり平均
  SELECT
    product_code,
    AVG(total_quantity) AS normal_sat_avg_qty,
    AVG(total_amount) AS normal_sat_avg_revenue,
    AVG(total_amount_tax_incl) AS normal_sat_avg_revenue_tax_incl,
    COUNT(DISTINCT date_key) AS normal_sat_days
  FROM `{PROJECT_ID}.{DATASET}.mart_god_product_daily`
  WHERE month_num = 8
    AND dow_ja = '土'
    AND is_obon = FALSE
    AND is_typhoon_period = FALSE
  GROUP BY product_code
)
SELECT
  o.product_code,
  o.product_name,
  o.department_code,
  o.brand_name,
  o.obon_qty,
  o.obon_revenue,
  o.obon_revenue_tax_incl,
  o.obon_buyers,
  o.obon_days,
  -- 旧盆1日あたり
  ROUND(SAFE_DIVIDE(o.obon_revenue, o.obon_days)) AS obon_daily_avg_revenue,
  -- 通常土曜1日あたり
  ROUND(n.normal_sat_avg_revenue) AS normal_sat_daily_avg_revenue,
  -- 倍率
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(o.obon_revenue, o.obon_days),
    n.normal_sat_avg_revenue
  ), 2) AS obon_vs_normal_ratio,
  -- ランキング
  RANK() OVER (ORDER BY o.obon_revenue DESC) AS obon_revenue_rank
FROM obon o
LEFT JOIN normal_sat n ON o.product_code = n.product_code
WHERE o.product_name IS NOT NULL
ORDER BY o.obon_revenue DESC;


-- ---------------------------------------------------------------------------
-- 8. mart_god_typhoon_product_impact — 台風前後の商品売上変動
-- ---------------------------------------------------------------------------
-- 台風前日・当日・翌日の商品売上と通常期間を比較。
-- 対応: Q4（台風が来ると何が売れる？）
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET}.mart_god_typhoon_product_impact` AS
WITH typhoon_period AS (
  SELECT
    date_key,
    typhoon_label,
    product_code,
    product_name,
    department_code,
    brand_name,
    SUM(total_quantity) AS qty,
    SUM(total_amount) AS revenue,
    SUM(total_amount_tax_incl) AS revenue_tax_incl,
    SUM(unique_buyers) AS buyers
  FROM `{PROJECT_ID}.{DATASET}.mart_god_product_daily`
  WHERE is_typhoon_period = TRUE
  GROUP BY date_key, typhoon_label, product_code, product_name, department_code, brand_name
),
normal_avg AS (
  -- 通常期間の1日あたり平均（同じ曜日の平均）
  SELECT
    product_code,
    AVG(total_quantity) AS normal_daily_avg_qty,
    AVG(total_amount) AS normal_daily_avg_revenue
  FROM `{PROJECT_ID}.{DATASET}.mart_god_product_daily`
  WHERE period_type = '通常'
  GROUP BY product_code
)
SELECT
  t.date_key,
  t.typhoon_label,
  t.product_code,
  t.product_name,
  t.department_code,
  t.brand_name,
  t.qty,
  t.revenue,
  t.revenue_tax_incl,
  t.buyers,
  ROUND(n.normal_daily_avg_qty, 1) AS normal_daily_avg_qty,
  ROUND(n.normal_daily_avg_revenue) AS normal_daily_avg_revenue,
  ROUND(SAFE_DIVIDE(t.qty, n.normal_daily_avg_qty), 2) AS qty_vs_normal_ratio,
  ROUND(SAFE_DIVIDE(t.revenue, n.normal_daily_avg_revenue), 2) AS revenue_vs_normal_ratio,
  RANK() OVER (PARTITION BY t.date_key ORDER BY t.revenue DESC) AS revenue_rank_in_day
FROM typhoon_period t
LEFT JOIN normal_avg n ON t.product_code = n.product_code
WHERE t.product_name IS NOT NULL
ORDER BY t.date_key, t.revenue DESC;


-- ---------------------------------------------------------------------------
-- 9. mart_god_store_obon_retention — 店舗別旧盆売上維持率
-- ---------------------------------------------------------------------------
-- 旧盆翌日（9/7）の売上がどれだけ維持されたかを店舗別に算出。
-- 対応: Q5（旧盆が4日間ある店舗は？）
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET}.mart_god_store_obon_retention` AS
WITH store_obon AS (
  SELECT
    store_name,
    MAX(IF(date_key = '20250903', total_sales, NULL)) AS sales_0903_pre,
    MAX(IF(date_key = '20250904', total_sales, NULL)) AS sales_0904_unkee,
    MAX(IF(date_key = '20250905', total_sales, NULL)) AS sales_0905_nakanuhii,
    MAX(IF(date_key = '20250906', total_sales, NULL)) AS sales_0906_uukui,
    MAX(IF(date_key = '20250907', total_sales, NULL)) AS sales_0907_next,
    MAX(IF(date_key = '20250903', unique_customers, NULL)) AS customers_0903,
    MAX(IF(date_key = '20250904', unique_customers, NULL)) AS customers_0904,
    MAX(IF(date_key = '20250905', unique_customers, NULL)) AS customers_0905,
    MAX(IF(date_key = '20250906', unique_customers, NULL)) AS customers_0906,
    MAX(IF(date_key = '20250907', unique_customers, NULL)) AS customers_0907
  FROM `{PROJECT_ID}.{DATASET}.mart_god_store_daily`
  WHERE date_key BETWEEN '20250903' AND '20250907'
  GROUP BY store_name
),
normal_sat AS (
  -- 8月の通常土曜日の店舗別平均売上
  SELECT
    store_name,
    AVG(total_sales) AS normal_sat_avg_sales
  FROM `{PROJECT_ID}.{DATASET}.mart_god_store_daily`
  WHERE month_num = 8
    AND dow_ja = '土'
    AND is_obon = FALSE
    AND is_typhoon_period = FALSE
  GROUP BY store_name
)
SELECT
  o.store_name,
  o.sales_0903_pre,
  o.sales_0904_unkee,
  o.sales_0905_nakanuhii,
  o.sales_0906_uukui,
  o.sales_0907_next,
  -- ウークイ翌日の売上維持率（高い = 旧盆が4日間ある傾向）
  ROUND(SAFE_DIVIDE(o.sales_0907_next, o.sales_0906_uukui) * 100, 1) AS retention_rate_pct,
  -- 通常土曜比
  ROUND(n.normal_sat_avg_sales) AS normal_sat_avg_sales,
  ROUND(SAFE_DIVIDE(o.sales_0906_uukui, n.normal_sat_avg_sales), 2) AS uukui_vs_normal_ratio,
  -- 旧盆期間合計
  (COALESCE(o.sales_0904_unkee, 0) + COALESCE(o.sales_0905_nakanuhii, 0) + COALESCE(o.sales_0906_uukui, 0)) AS obon_3day_total,
  (COALESCE(o.sales_0904_unkee, 0) + COALESCE(o.sales_0905_nakanuhii, 0) + COALESCE(o.sales_0906_uukui, 0) + COALESCE(o.sales_0907_next, 0)) AS obon_4day_total,
  -- 客数推移
  o.customers_0903,
  o.customers_0904,
  o.customers_0905,
  o.customers_0906,
  o.customers_0907,
  -- 客単価推移
  ROUND(SAFE_DIVIDE(o.sales_0906_uukui, o.customers_0906)) AS unit_price_0906,
  ROUND(SAFE_DIVIDE(o.sales_0907_next, o.customers_0907)) AS unit_price_0907
FROM store_obon o
LEFT JOIN normal_sat n ON o.store_name = n.store_name
ORDER BY retention_rate_pct DESC;


-- ---------------------------------------------------------------------------
-- 10. mart_god_store_daily_txn_pattern — 店舗別日次取引パターン
-- ---------------------------------------------------------------------------
-- 取引数が通常より極端に少ない日（営業時間短縮の可能性）を検出。
-- 対応: Q6（営業時間が早く終わる日は？）
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET}.mart_god_store_daily_txn_pattern` AS
WITH store_stats AS (
  SELECT
    store_name,
    dow_ja,
    AVG(transaction_count) AS avg_txn,
    STDDEV(transaction_count) AS stddev_txn
  FROM `{PROJECT_ID}.{DATASET}.mart_god_store_daily`
  WHERE period_type = '通常'
  GROUP BY store_name, dow_ja
)
SELECT
  d.date_key,
  d.date_iso,
  d.dow_ja,
  d.obon_label,
  d.typhoon_label,
  d.period_type,
  d.store_name,
  d.transaction_count,
  d.total_sales,
  d.unique_customers,
  d.avg_transaction_amount,
  ROUND(s.avg_txn) AS normal_avg_txn_same_dow,
  ROUND(s.stddev_txn, 1) AS stddev_txn_same_dow,
  -- 通常の同曜日平均からの乖離（Zスコア）
  ROUND(SAFE_DIVIDE(d.transaction_count - s.avg_txn, s.stddev_txn), 2) AS txn_z_score,
  -- 通常比（低い = 営業時間短縮の可能性）
  ROUND(SAFE_DIVIDE(d.transaction_count, s.avg_txn) * 100, 1) AS txn_vs_normal_pct,
  CASE
    WHEN SAFE_DIVIDE(d.transaction_count, s.avg_txn) < 0.7 THEN '大幅減（-30%以上）'
    WHEN SAFE_DIVIDE(d.transaction_count, s.avg_txn) < 0.85 THEN '減少（-15%以上）'
    WHEN SAFE_DIVIDE(d.transaction_count, s.avg_txn) > 1.3 THEN '大幅増（+30%以上）'
    WHEN SAFE_DIVIDE(d.transaction_count, s.avg_txn) > 1.15 THEN '増加（+15%以上）'
    ELSE '通常範囲'
  END AS txn_anomaly_label
FROM `{PROJECT_ID}.{DATASET}.mart_god_store_daily` d
LEFT JOIN store_stats s ON d.store_name = s.store_name AND d.dow_ja = s.dow_ja
ORDER BY d.date_key, d.store_name;
