-- =============================================================================
-- mart_god — 全課題対応の統合神マート
-- =============================================================================
-- Jagu'e'r 沖縄分科会 Meetup #8（2026-04-11）
-- サンエー POSデータ（2025年8〜9月）を完全に分析するための単一マート
--
-- 粒度: 日付 × 店舗 × 商品
-- ソース: customer_sales_details + food_item_master（75M行を事前結合・集約）
--
-- この1テーブルから GROUP BY だけで全課題に回答可能:
--
--   共通課題（最高売上日）:
--     GROUP BY date_key → SUM(total_amount) ORDER BY DESC
--
--   Q1（旧盆に何が売れた？通常の何倍？）:
--     WHERE is_obon GROUP BY product_name vs WHERE period_type='通常' AND dow_ja='土'
--
--   Q2（曜日別売上差）:
--     GROUP BY dow_ja → AVG(SUM per day)
--
--   Q3（売れ筋商品・時期変動）:
--     GROUP BY month_num, product_name → RANK
--
--   Q4（台風で何が売れる？）:
--     WHERE is_typhoon_period GROUP BY date_key, typhoon_label, product_name
--
--   Q5（旧盆4日間ある店舗）:
--     WHERE is_obon_extended GROUP BY store_name, date_key → PIVOT売上維持率
--
--   Q6（営業短縮日の推定）:
--     GROUP BY store_name, date_key → COUNT(DISTINCT trans_key) vs 同曜日平均
--
-- 使い方:
--   {PROJECT_ID} を自分のプロジェクトIDに置換して実行
--   {DATASET} を自分のデータセット名に置換して実行
-- =============================================================================

CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET}.mart_god` AS
WITH
-- ---------------------------------------------------------------------------
-- カレンダーマスター: 日付に曜日・旧盆・台風のイベントフラグを付与
-- ---------------------------------------------------------------------------
calendar AS (
  SELECT
    FORMAT_DATE('%Y%m%d', d) AS date_key,
    d AS date_val,
    FORMAT_DATE('%Y-%m-%d', d) AS date_iso,
    EXTRACT(MONTH FROM d) AS month_num,
    CASE EXTRACT(MONTH FROM d) WHEN 8 THEN '8月' WHEN 9 THEN '9月' END AS month_label,
    EXTRACT(ISOWEEK FROM d) AS week_num,
    EXTRACT(DAYOFWEEK FROM d) AS dow_number,
    CASE EXTRACT(DAYOFWEEK FROM d)
      WHEN 1 THEN '日' WHEN 2 THEN '月' WHEN 3 THEN '火'
      WHEN 4 THEN '水' WHEN 5 THEN '木' WHEN 6 THEN '金' WHEN 7 THEN '土'
    END AS dow_ja,
    EXTRACT(DAYOFWEEK FROM d) IN (1, 7) AS is_weekend,

    -- 旧盆（2025年旧暦7月13〜15日 = 新暦9/4〜9/6）
    CASE FORMAT_DATE('%Y%m%d', d)
      WHEN '20250903' THEN '旧盆前日（買い出しピーク）'
      WHEN '20250904' THEN 'ウンケー（迎え盆）'
      WHEN '20250905' THEN 'ナカヌヒー（中日）'
      WHEN '20250906' THEN 'ウークイ（送り盆）'
      WHEN '20250907' THEN '旧盆翌日'
    END AS obon_label,
    FORMAT_DATE('%Y%m%d', d) BETWEEN '20250904' AND '20250906' AS is_obon,
    FORMAT_DATE('%Y%m%d', d) BETWEEN '20250903' AND '20250907' AS is_obon_extended,

    -- 台風LINGLING（8/19直撃）
    CASE FORMAT_DATE('%Y%m%d', d)
      WHEN '20250818' THEN '台風前日（備蓄買い）'
      WHEN '20250819' THEN '台風直撃日'
      WHEN '20250820' THEN '台風明け（回復買い）'
    END AS typhoon_label,
    FORMAT_DATE('%Y%m%d', d) BETWEEN '20250818' AND '20250820' AS is_typhoon_period,

    -- 期間区分
    CASE
      WHEN FORMAT_DATE('%Y%m%d', d) BETWEEN '20250904' AND '20250906' THEN '旧盆'
      WHEN FORMAT_DATE('%Y%m%d', d) BETWEEN '20250818' AND '20250820' THEN '台風'
      ELSE '通常'
    END AS period_type
  FROM UNNEST(GENERATE_DATE_ARRAY('2025-08-01', '2025-09-30')) AS d
)

-- ---------------------------------------------------------------------------
-- 本体: customer_sales_details × food_item_master × calendar を結合・集約
-- ---------------------------------------------------------------------------
SELECT
  -- ── 日付・カレンダー ──
  c.date_key,
  c.date_iso,
  c.month_num,
  c.month_label,
  c.week_num,
  c.dow_number,
  c.dow_ja,
  c.is_weekend,
  c.obon_label,
  c.is_obon,
  c.is_obon_extended,
  c.typhoon_label,
  c.is_typhoon_period,
  c.period_type,

  -- ── 店舗 ──
  sd.store_name,

  -- ── 商品 ──
  sd.product_code,
  f.product_name,
  f.department_code,
  f.mid_category,
  f.sub_category,
  f.brand_name,

  -- ── 指標 ──
  COUNT(DISTINCT CONCAT(sd.card_no, sd.store_name, CAST(sd.usage_date AS STRING), sd.trans_no)) AS transaction_count,
  SUM(sd.quantity) AS total_quantity,
  SUM(sd.amount) AS total_amount,
  SUM(sd.tax_included_amount) AS total_amount_tax_incl,
  COUNT(DISTINCT sd.card_no) AS unique_buyers

FROM `{PROJECT_ID}.{DATASET}.customer_sales_details` sd
JOIN calendar c
  ON CAST(sd.usage_date AS STRING) = c.date_key
LEFT JOIN `{PROJECT_ID}.{DATASET}.food_item_master` f
  ON sd.product_code = CAST(f.product_code AS STRING)
WHERE sd.tax_included_amount > 0
GROUP BY
  c.date_key, c.date_iso, c.month_num, c.month_label, c.week_num,
  c.dow_number, c.dow_ja, c.is_weekend,
  c.obon_label, c.is_obon, c.is_obon_extended,
  c.typhoon_label, c.is_typhoon_period, c.period_type,
  sd.store_name, sd.product_code,
  f.product_name, f.department_code, f.mid_category, f.sub_category, f.brand_name;
