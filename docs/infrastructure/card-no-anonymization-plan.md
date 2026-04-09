# card_no SHA-256 ハッシュ化 修正計画

## 背景

丸山さんから `card_master` と `customer_sales_details` の `card_no` について、指定のハッシュ値ではなく **12桁の生番号がそのまま投入されている** との連絡があった（2026-03-21）。

現状のビュー（`sana_meetup8`）は `card_no` をそのまま透過しており、DCR 経由で参加者に生番号が露出するリスクがある。

## 現状の問題

```
sana_bronze.card_master.card_no              = "190811279747"  ← 12桁生番号
sana_bronze.customer_sales_details.card_no   = "190811279747"  ← 同上（未投入だが同様の想定）

sana_meetup8.card_master (VIEW)              → card_no をそのまま SELECT
sana_meetup8.customer_sales_details (VIEW)   → card_no をそのまま SELECT
```

参加者は DCR 経由で `sana_meetup8` のビューにアクセスするため、ビュー層でハッシュ化すれば生番号は露出しない。

## 方針: ビュー層での SHA-256 ハッシュ化

**bronze テーブルのデータは変更しない。** ビュー定義を修正し、`card_no` に `SHA256()` を適用してハッシュ値を公開する。

### 理由

| 方式 | メリット | デメリット |
|:---|:---|:---|
| **A. ビュー層でハッシュ（採用）** | データ非破壊、ロールバック不要、Terraform差分のみ | ビュークエリ時に毎回計算（性能影響は軽微） |
| B. bronze データを直接書き換え | クエリ時計算不要 | 不可逆操作、再投入が必要になる可能性 |
| C. 中間 silver レイヤー追加 | 層が明確 | 過剰設計、テーブル増加 |

### ハッシュ仕様

```sql
-- BigQuery SHA-256 関数
TO_HEX(SHA256(card_no)) AS card_no
```

- **入力**: 12桁の生カード番号（STRING）
- **出力**: 64文字の16進数小文字文字列（例: `a3f2b8c1d4...`）
- **特性**: 同じ入力 → 同じ出力（テーブル間の JOIN 整合性を維持）
- **不可逆**: 元の12桁番号には復元不可

## 修正対象

### 1. Terraform: `main.tf` — ビュー定義 2箇所

#### 1-1. `sana_meetup8.card_master` ビュー

**修正前:**
```sql
SELECT
  card_no,
  cif_no,
  sm.store_name AS own_store_name,
  ...
FROM `<project-id>.sana_bronze.card_master` c
```

**修正後:**
```sql
SELECT
  TO_HEX(SHA256(card_no)) AS card_no,
  cif_no,
  sm.store_name AS own_store_name,
  ...
FROM `<project-id>.sana_bronze.card_master` c
```

#### 1-2. `sana_meetup8.customer_sales_details` ビュー

**修正前:**
```sql
SELECT
  s.card_no,
  sm.store_name,
  ...
FROM `<project-id>.sana_bronze.customer_sales_details` s
```

**修正後:**
```sql
SELECT
  TO_HEX(SHA256(s.card_no)) AS card_no,
  sm.store_name,
  ...
FROM `<project-id>.sana_bronze.customer_sales_details` s
```

### 2. Terraform: `main.tf` — スキーマの description 修正

以下の description を更新（実態に合わせる）:

- `sana_bronze.card_master.card_no`: `"カード番号（12桁・生番号）"`
- `sana_bronze.customer_sales_details.card_no`: `"カード番号（12桁・生番号）"`
- `sana_meetup8.card_master.card_no`: `"カード番号（SHA-256ハッシュ化済み・64文字hex）"`
- `sana_meetup8.customer_sales_details.card_no`: `"カード番号（SHA-256ハッシュ化済み・64文字hex）"`

### 3. `setup_data.sh` — マートテーブル作成クエリ

マートテーブルはビュー（`sana_meetup8.*`）を参照して作成されるため、**ビュー修正が自動的に反映される。追加修正は不要。**

参照関係:
```
mart_daily_sales          → sana_meetup8.customer_sales_details (card_no はハッシュ済みで渡る)
mart_customer_summary     → sana_meetup8.customer_sales_details + card_master (両方ハッシュ済み、JOIN 整合性OK)
mart_product_ranking      → sana_meetup8.customer_sales_details (card_no はハッシュ済みで渡る)
mart_basket_analysis      → sana_meetup8.customer_sales_details (card_no はハッシュ済みで渡る)
```

### 4. テストデータ（`terraform/test/`）

テスト環境にも同様のビュー修正を適用する（本番と同じロジック）。

## JOIN 整合性の検証

ハッシュ化後もテーブル間の JOIN が正しく機能することを確認する。

```sql
-- 検証クエリ: card_master と customer_sales_details の JOIN
SELECT COUNT(*) AS matched_rows
FROM `<project-id>.sana_meetup8.customer_sales_details` s
INNER JOIN `<project-id>.sana_meetup8.card_master` cm
  ON s.card_no = cm.card_no
LIMIT 10;
```

両ビューとも `TO_HEX(SHA256(card_no))` を適用するため、同じ生番号 → 同じハッシュ値となり、JOIN は正常に動作する。

## 実行手順

```
1. main.tf のビュー定義を修正（上記 1-1, 1-2, 2）
2. terraform plan で差分確認（ビュー2つの UPDATE のみであること）
3. terraform apply 実行
4. BigQuery Console でビューの card_no がハッシュ値になっていることを確認
5. 丸山さんの残りデータ投入を待つ（customer_master, customer_sales_details, shop_item_daily_performance）
6. 全データ投入後に setup_data.sh を実行（マート作成・DCRリスティング追加）
7. JOIN 整合性検証クエリを実行
```

## 確認用クエリ

```sql
-- ビュー適用後の card_no 形式確認
SELECT card_no, LENGTH(card_no) AS len
FROM `<project-id>.sana_meetup8.card_master`
LIMIT 5;
-- 期待: card_no = "a3f2b8c1..." (64文字), len = 64

-- bronze 側は生番号のまま保持されていることを確認
SELECT card_no, LENGTH(card_no) AS len
FROM `<project-id>.sana_bronze.card_master`
LIMIT 5;
-- 期待: card_no = "190811279747" (12文字), len = 12
```

## リスク・注意事項

| リスク | 対策 |
|:---|:---|
| ビュー更新時に既存の DCR サブスクライバーに影響 | Egress 制御 ON のため、サブスクライバーはデータをコピーしていない。ビュー更新はリアルタイム反映 |
| ハッシュ化で card_no が長くなり、参加者のクエリが変わる | card_no は JOIN キーとして使用するのみ。表示形式が変わっても分析への影響なし |
| 性能劣化 | SHA256 の計算コストは軽微。257万行の card_master でも数秒以内 |
| bronze テーブルに生番号が残る | bronze データセットは参加者に非公開。IAM で GScale メンバーのみアクセス可 |
