-- =============================================================================
-- mart_god — 全課題対応の統合神マート
-- =============================================================================
-- Jagu'e'r 沖縄分科会 Meetup #8（2026-04-11）
-- サンエー POSデータ（2025年8〜9月）を完全に分析するための単一マート
--
-- 粒度: 日付 × 店舗 × 商品
-- ソース: customer_sales_details + food_item_master（75M行を事前結合・集約）
--
-- カラム名は Agent指示書の既存テーブルと完全に統一:
--   usage_date    ← mart_daily_sales, mart_basket_analysis と同じ
--   store_name    ← mart_daily_sales と同じ
--   product_code  ← customer_sales_details と同じ（STRING型）
--   product_name  ← food_item_master と同じ
--   total_sales   ← mart_daily_sales と同じ（税抜）
--   tax_included_amount ← customer_sales_details と同じ（税込）
--   unique_buyers ← mart_product_ranking と同じ
--
-- Agent指示書の注意事項がそのまま適用可能:
--   usage_date = '20250906' のように文字列でフィルタ
--   WHERE product_name IS NOT NULL で商品名あり行に絞り込み
--   売上金額はすべて税抜（total_sales）
--
-- この1テーブルから GROUP BY だけで全課題に回答可能:
--
--   共通課題（最高売上日）:
--     GROUP BY usage_date → SUM(total_sales) ORDER BY DESC
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
--     WHERE is_typhoon_period GROUP BY usage_date, typhoon_label, product_name
--
--   Q5（旧盆4日間ある店舗）:
--     WHERE is_obon_extended GROUP BY store_name, usage_date → PIVOT売上維持率
--
--   Q6（営業短縮日の推定）:
--     GROUP BY store_name, usage_date → transaction_count vs 同曜日平均
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
    FORMAT_DATE('%Y%m%d', d) AS usage_date,
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
  -- 日付（STRING, YYYYMMDD — 既存テーブルと同じ形式・同じ名前）
  c.usage_date,
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

  -- 店舗
  sd.store_name,

  -- 商品（food_item_master と同じカラム名）
  sd.product_code,
  f.product_name,
  f.department_code,
  f.mid_category,
  f.sub_category,
  f.brand_name,

  -- 指標（既存テーブルと同じカラム名）
  COUNT(DISTINCT CONCAT(sd.card_no, sd.store_name, CAST(sd.usage_date AS STRING), sd.trans_no)) AS transaction_count,
  SUM(sd.quantity) AS total_quantity,
  SUM(sd.amount) AS total_sales,
  SUM(sd.tax_included_amount) AS tax_included_amount,
  COUNT(DISTINCT sd.card_no) AS unique_buyers

FROM `{PROJECT_ID}.{DATASET}.customer_sales_details` sd
JOIN calendar c
  ON CAST(sd.usage_date AS STRING) = c.usage_date
LEFT JOIN `{PROJECT_ID}.{DATASET}.food_item_master` f
  ON sd.product_code = CAST(f.product_code AS STRING)
WHERE sd.tax_included_amount > 0
GROUP BY
  c.usage_date, c.month_num, c.month_label, c.week_num,
  c.dow_number, c.dow_ja, c.is_weekend,
  c.obon_label, c.is_obon, c.is_obon_extended,
  c.typhoon_label, c.is_typhoon_period, c.period_type,
  sd.store_name, sd.product_code,
  f.product_name, f.department_code, f.mid_category, f.sub_category, f.brand_name;
