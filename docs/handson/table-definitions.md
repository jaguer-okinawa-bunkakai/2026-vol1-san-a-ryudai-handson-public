---
layout: default
title: テーブル定義書
---

# サンエー提供データ テーブル定義書

> **データ提供**: 株式会社サンエー様
> **対象イベント**: Jagu'e'r 沖縄分科会 Meetup #8（2026-04-11）
> **参照形式**: `` `{自分のプロジェクトID}.sana_ryudai_handson.{テーブル名}` ``

---

## 1. データ概要

### テーブル・マート一覧

参加者が Analytics Hub（データクリーンルーム）経由でアクセスできるテーブル・マート。

#### ビュー（5テーブル）

| テーブル名 | 論理名 | 件数 | 期間 | 備考 |
|-----------|--------|------|------|------|
| `card_master` | カードマスター | 2,576,484件 | — | card_no は SHA-256 ハッシュ化済み |
| `customer_master` | 顧客マスター | 1,412,052件 | — | 氏名・住所・電話番号は除外済み |
| `customer_sales_details` | 顧客売上明細 ★メイン | 75,140,401件 | **2025年8〜9月** | card_no は SHA-256 ハッシュ化済み |
| `food_item_master` | 商品マスター（食品） | 634,707件 | — | 原価カラム除外済み |
| `shop_item_daily_performance` | 店別単品別実績（日別） | 58,248,949件 | **2025/08-09・2025/12-2026/01** | 10〜11月データなし |

#### データマート（4テーブル）

重いフルスキャンを避けるための集計済みテーブル。参加者のクエリコスト削減に活用。

| マート名 | 件数 | 集計粒度 | 主要指標 |
|---------|------|---------|---------|
| `mart_daily_sales` | 5,411件 | 日別 × 店舗別 | 取引数、売上合計、ユニーク顧客数 |
| `mart_customer_summary` | 590,919件 | カード番号別 | 来店日数、購入回数、合計金額、平均単価 |
| `mart_product_ranking` | 286,866件 | 商品コード別 | 販売数量、売上金額、購入者数 |
| `mart_basket_analysis` | 9,595,190件 | 取引（バスケット）別 | バスケット内商品数、合計金額、平均単価 |

### テーブル間のリレーション

```
customer_master（顧客 / 1,412,052件）
    │  cif_no
    ▼
card_master（カード / 2,576,484件）
    │  card_no（SHA-256 ハッシュ化）
    ▼
customer_sales_details（売上明細★ / 75,140,401件 / 2025年8〜9月）
    │  product_code（STRING）
    ▼
food_item_master（商品 / 634,707件）※ product_code は INT64 → CAST が必要
    ↑  product_code（STRING）
shop_item_daily_performance（日別実績 / 58,248,949件）
```

### クエリ利用上の注意

| 注意点 | 内容 |
|--------|------|
| **クエリコスト** | `customer_sales_details` のフルスキャンは約75億件。日付フィルタやマートを活用すること |
| **異常データ** | `customer_sales_details` に 0円・1,719品のレコードあり。分析時は `WHERE tax_included_amount > 0` を推奨 |
| **型不一致** | `food_item_master.product_code` は `INT64`。他テーブルとの JOIN には `CAST(product_code AS STRING)` が必要 |
| **空白期間** | `shop_item_daily_performance` の 2025年10〜11月データは含まれない |

---

## 2. ビュー テーブル定義

### card_master（カードマスター）

| 項目 | 値 |
|------|---|
| 件数 | 2,576,484件 |
| 粒度 | ポイントカード1枚につき1レコード |
| ソース | ユニケージ |

| 項番 | 物理名 | 論理名 | 型 | 備考 |
|------|--------|--------|-----|------|
| 1 | `card_no` | カード番号 | `STRING` | **PK**。SHA-256 ハッシュ化済み（64文字）。`customer_sales_details` との結合キー |
| 2 | `cif_no` | CIF番号 | `STRING` | `customer_master` との結合キー（8桁・前ゼロあり） |
| 3 | `own_store_name` | 所属店舗名 | `STRING` | |
| 4 | `issue_store_name` | 発行店舗名 | `STRING` | |
| 5 | `issue_date` | 発行日 | `STRING` | `yyyyMMdd` 形式 |
| 6 | `enrollment_date` | 入会日 | `STRING` | `yyyyMMdd` 形式 |
| 7 | `today_issued_point` | 本日付与ポイント | `INT64` | マイナス値あり |
| 8 | `total_point` | ポイント残高 | `INT64` | 現在の累計ポイント |
| 9 | `prev_day_total_point` | 前日累計ポイント | `INT64` | |
| 10 | `cumulative_issued_point` | 累計付与ポイント | `INT64` | 通算で付与されたポイント合計 |
| 11 | `settled_point` | 精算ポイント | `INT64` | 使用済みポイント |
| 12 | `cumulative_settled_point` | 累計精算ポイント | `INT64` | 通算の使用済みポイント合計 |
| 13 | `point_update_date` | ポイント更新日 | `STRING` | `yyyyMMdd` 形式 |

```sql
-- ポイント残留率（使い切っているか？）
SELECT
  card_no,
  total_point,
  cumulative_issued_point,
  ROUND(SAFE_DIVIDE(total_point, cumulative_issued_point) * 100, 1) AS point_retention_pct
FROM `{自分のプロジェクトID}.sana_ryudai_handson.card_master`
ORDER BY total_point DESC
LIMIT 10;
```

---

### customer_master（顧客マスター）

| 項目 | 値 |
|------|---|
| 件数 | 1,412,052件 |
| 粒度 | 顧客（CIF）1名につき1レコード |
| ソース | ユニケージ |

| 項番 | 物理名 | 論理名 | 型 | 備考 |
|------|--------|--------|-----|------|
| 1 | `cif_no` | CIF番号 | `STRING` | **PK**。8桁・前ゼロあり。`card_master` との結合キー |
| 2 | `gender_type` | 性別 | `INT64` | `1`=男性、`2`=女性 |
| 3 | `occupation_code` | 職業コード | `STRING` | 2桁コード |
| 4 | `customer_status` | 顧客ステータス | `STRING` | |

> 氏名・住所・電話番号・生年月日はビューから**除外**済み。

```sql
-- 性別×職業コード別の顧客数
SELECT
  gender_type,
  occupation_code,
  COUNT(*) AS customer_count
FROM `{自分のプロジェクトID}.sana_ryudai_handson.customer_master`
GROUP BY gender_type, occupation_code
ORDER BY customer_count DESC;
```

---

### customer_sales_details（顧客売上明細）★メイン

| 項目 | 値 |
|------|---|
| 件数 | 75,140,401件 |
| 粒度 | 1購買取引の1商品（明細行）につき1レコード |
| 期間 | 2025-08-01 〜 2025-09-30 |
| ソース | ユニケージ |

| 項番 | 物理名 | 論理名 | 型 | 備考 |
|------|--------|--------|-----|------|
| 1 | `card_no` | カード番号 | `STRING` | SHA-256 ハッシュ化済み。`card_master` との結合キー |
| 2 | `store_name` | 店舗名 | `STRING` | 例: 「那覇メインプレイス」 |
| 3 | `register_no` | レジ番号 | `STRING` | |
| 4 | `trans_no` | 取引番号 | `STRING` | 同一取引の明細を束ねるキー |
| 5 | `usage_date` | ご利用年月日 | `STRING` | `yyyyMMdd` 形式。例: `20250906` |
| 6 | `line_no` | 行番号 | `INT64` | 取引内の明細行番号 |
| 7 | `product_code` | 商品コード | `STRING` | `food_item_master` との結合キー。**注: food_item_master は INT64 のため CAST が必要** |
| 8 | `amount` | 金額（税抜） | `INT64` | |
| 9 | `quantity` | 数量 | `INT64` | |
| 10 | `tax_included_amount` | 金額（税込） | `INT64` | 分析ではこちらを使用 |

> 取引キー: `CONCAT(card_no, store_name, usage_date, trans_no)`

```sql
-- 日別売上集計（コスト大：フルスキャン。マート推奨）
SELECT
  usage_date,
  COUNT(DISTINCT CONCAT(card_no, store_name, usage_date, trans_no)) AS txn_count,
  SUM(tax_included_amount) AS total_sales
FROM `{自分のプロジェクトID}.sana_ryudai_handson.customer_sales_details`
WHERE tax_included_amount > 0
GROUP BY usage_date
ORDER BY total_sales DESC
LIMIT 10;
```

---

### food_item_master（商品マスター・食品）

| 項目 | 値 |
|------|---|
| 件数 | 634,707件 |
| 粒度 | 商品1つにつき1レコード |
| ソース | AS400 |

| 項番 | 物理名 | 論理名 | 型 | 備考 |
|------|--------|--------|-----|------|
| 1 | `product_code` | 商品コード | `INT64` | **PK**。⚠️ **INT64型**。他テーブルとの JOIN には `CAST(product_code AS STRING)` が必要 |
| 2 | `product_name_kana` | 商品名カナ | `STRING` | |
| 3 | `product_name` | 商品名 | `STRING` | |
| 4 | `department_code` | 部門コード | `INT64` | |
| 5 | `mid_category` | 中分類 | `INT64` | |
| 6 | `sub_category` | 小分類 | `INT64` | |
| 7 | `standard_price` | 標準売単価 | `INT64` | |
| 8 | `brand_name` | ブランド名 | `STRING` | |

```sql
-- 売上明細と商品マスターを結合（CAST が必要）
SELECT
  f.product_name,
  SUM(s.tax_included_amount) AS total_sales
FROM `{自分のプロジェクトID}.sana_ryudai_handson.customer_sales_details` s
LEFT JOIN `{自分のプロジェクトID}.sana_ryudai_handson.food_item_master` f
  ON s.product_code = CAST(f.product_code AS STRING)
WHERE s.usage_date = '20250906'
  AND s.tax_included_amount > 0
  AND f.product_name IS NOT NULL
GROUP BY f.product_name
ORDER BY total_sales DESC
LIMIT 20;
```

---

### shop_item_daily_performance（店別単品別実績・日別）

| 項目 | 値 |
|------|---|
| 件数 | 58,248,949件 |
| 粒度 | 日付 × 店舗 × 商品（1日1店舗1商品につき1レコード） |
| 期間 | 2025/08-09・2025/12-2026/01（10〜11月データなし） |
| ソース | ユニケージ |

| 項番 | 物理名 | 論理名 | 型 | 備考 |
|------|--------|--------|-----|------|
| 1 | `perf_date` | 日付 | `STRING` | `yyyyMMdd` 形式 |
| 2 | `store_name` | 店舗名 | `STRING` | |
| 3 | `product_code` | 商品コード | `STRING` | `food_item_master` との結合には CAST が必要 |
| 4 | `department_code` | 部門コード | `STRING` | |
| 5 | `selling_price` | 売単価 | `INT64` | |
| 6 | `sales_qty` | 販売数量 | `INT64` | |
| 7 | `sales_amount` | 売上金額 | `INT64` | |
| 8 | `customer_count` | 客数 | `INT64` | |
| 9 | `markdown_qty` | 値引き数量 | `INT64` | |
| 10 | `markdown_amount` | 値引き金額 | `INT64` | |
| 11 | `disposal_qty` | 廃棄数量 | `INT64` | |
| 12 | `disposal_amount` | 廃棄金額 | `INT64` | |
| 13 | `order_qty` | 発注数量 | `INT64` | |
| 14 | `delivery_qty` | 納品数量 | `INT64` | |
| 15 | `return_qty` | 返品数量 | `INT64` | |
| 16 | `transfer_qty` | 移動数量 | `INT64` | |
| 17 | `price_change_amount` | 売変金額 | `INT64` | |
| 18 | `inventory_qty` | 在庫数量 | `INT64` | |
| 19 | `inventory_amount` | 在庫金額 | `INT64` | |

> 原単価（原価）はマスキング済みのため非公開。

```sql
-- 旧盆前後の廃棄・値引き推移
SELECT
  perf_date,
  FORMAT_DATE('%a', PARSE_DATE('%Y%m%d', perf_date)) AS dow,
  SUM(sales_amount) AS total_sales,
  SUM(disposal_qty) AS total_disposal,
  SUM(disposal_amount) AS total_disposal_amount,
  SUM(markdown_qty) AS total_markdown
FROM `{自分のプロジェクトID}.sana_ryudai_handson.shop_item_daily_performance`
WHERE perf_date BETWEEN '20250901' AND '20250915'
GROUP BY perf_date
ORDER BY perf_date;
```

---

## 3. データマート テーブル定義

> **活用推奨**: Q1〜Q3の謎解きはマートを使うとスキャンコストを大幅削減できる。

### mart_daily_sales（日別売上マート）

| 項目 | 値 |
|------|---|
| 件数 | 5,411件 |
| 粒度 | 日付 × 店舗（1日1店舗につき1レコード） |

| 物理名 | 論理名 | 型 | 備考 |
|--------|--------|-----|------|
| `usage_date` | 利用年月日 | `STRING` | `yyyyMMdd` 形式 |
| `store_name` | 店舗名 | `STRING` | |
| `transaction_count` | 取引数 | `INT64` | |
| `line_count` | 明細行数 | `INT64` | |
| `total_quantity` | 販売点数 | `INT64` | |
| `total_sales` | 売上金額 | `INT64` | |
| `unique_customers` | ユニーク顧客数 | `INT64` | |

```sql
-- 日別売上ランキング
SELECT
  usage_date,
  FORMAT_DATE('%a', PARSE_DATE('%Y%m%d', usage_date)) AS dow,
  SUM(total_sales) AS daily_sales,
  SUM(transaction_count) AS daily_txn,
  ROUND(SAFE_DIVIDE(SUM(total_sales), SUM(transaction_count)), 0) AS avg_per_txn
FROM `{自分のプロジェクトID}.sana_ryudai_handson.mart_daily_sales`
GROUP BY usage_date
ORDER BY daily_sales DESC
LIMIT 20;
```

---

### mart_customer_summary（顧客サマリーマート）

| 項目 | 値 |
|------|---|
| 件数 | 590,919件 |
| 粒度 | カード番号1枚につき1レコード |

| 物理名 | 論理名 | 型 | 備考 |
|--------|--------|-----|------|
| `card_no` | カード番号 | `STRING` | SHA-256 ハッシュ化済み |
| `gender_type` | 性別 | `INT64` | `1`=男性、`2`=女性 |
| `occupation_code` | 職業コード | `STRING` | |
| `visit_days` | 来店日数 | `INT64` | |
| `transaction_count` | 購入回数 | `INT64` | |
| `total_items` | 購入点数 | `INT64` | |
| `total_spend` | 購入総額 | `INT64` | |
| `avg_item_price` | 平均単価 | `FLOAT64` | |
| `first_purchase` | 初回購入日 | `STRING` | `yyyyMMdd` 形式 |
| `last_purchase` | 最終購入日 | `STRING` | `yyyyMMdd` 形式 |

```sql
-- ヘビーユーザー × ポイント残留率
SELECT
  cs.card_no,
  cs.total_spend,
  cs.transaction_count,
  cs.visit_days,
  cm.total_point,
  cm.cumulative_issued_point,
  ROUND(SAFE_DIVIDE(cm.total_point, cm.cumulative_issued_point) * 100, 1) AS point_retention_pct
FROM `{自分のプロジェクトID}.sana_ryudai_handson.mart_customer_summary` cs
LEFT JOIN `{自分のプロジェクトID}.sana_ryudai_handson.card_master` cm
  ON cs.card_no = cm.card_no
ORDER BY cs.total_spend DESC
LIMIT 20;
```

---

### mart_product_ranking（商品ランキングマート）

| 項目 | 値 |
|------|---|
| 件数 | 286,866件 |
| 粒度 | 商品コード1つにつき1レコード |

> ⚠️ `product_name` が null のレコードが多数（227,551件）。`food_item_master.product_code`（INT64）と `customer_sales_details.product_code`（STRING）の型不一致が原因と推定。分析時は `WHERE product_name IS NOT NULL` を推奨。

| 物理名 | 論理名 | 型 | 備考 |
|--------|--------|-----|------|
| `product_code` | 商品コード | `STRING` | |
| `product_name` | 商品名 | `STRING` | null の場合は未登録商品 |
| `department_code` | 部門コード | `INT64` | |
| `mid_category` | 中分類 | `INT64` | |
| `sub_category` | 小分類 | `INT64` | |
| `total_qty_sold` | 総販売数量 | `INT64` | |
| `total_revenue` | 総売上金額 | `INT64` | |
| `unique_buyers` | ユニーク購入者数 | `INT64` | |
| `days_sold` | 販売日数 | `INT64` | |

```sql
-- 売上TOP商品（商品名あり）
SELECT
  product_code,
  product_name,
  total_qty_sold,
  total_revenue,
  unique_buyers
FROM `{自分のプロジェクトID}.sana_ryudai_handson.mart_product_ranking`
WHERE product_name IS NOT NULL AND total_revenue > 0
ORDER BY total_revenue DESC
LIMIT 20;
```

---

### mart_basket_analysis（バスケット分析マート）

| 項目 | 値 |
|------|---|
| 件数 | 9,595,190件 |
| 粒度 | 取引（バスケット）1件につき1レコード |

> ⚠️ `basket_total = 0` のレコードが含まれる（異常データ）。分析時は `WHERE basket_total > 0` を推奨。

| 物理名 | 論理名 | 型 | 備考 |
|--------|--------|-----|------|
| `card_no` | カード番号 | `STRING` | SHA-256 ハッシュ化済み |
| `usage_date` | 利用年月日 | `STRING` | `yyyyMMdd` 形式 |
| `store_name` | 店舗名 | `STRING` | |
| `trans_no` | 取引番号 | `STRING` | |
| `items_in_basket` | バスケット内品数 | `INT64` | |
| `basket_total` | バスケット合計金額 | `INT64` | |
| `avg_item_price` | 平均単価 | `FLOAT64` | |

```sql
-- 最も多く品数を買った取引 TOP10
SELECT
  card_no,
  usage_date,
  store_name,
  items_in_basket,
  basket_total,
  ROUND(avg_item_price, 0) AS avg_price
FROM `{自分のプロジェクトID}.sana_ryudai_handson.mart_basket_analysis`
WHERE basket_total > 0
ORDER BY items_in_basket DESC
LIMIT 10;

-- 最も高額な取引 TOP10
SELECT
  card_no,
  usage_date,
  store_name,
  items_in_basket,
  basket_total
FROM `{自分のプロジェクトID}.sana_ryudai_handson.mart_basket_analysis`
WHERE basket_total > 0
ORDER BY basket_total DESC
LIMIT 10;
```
