# データクリーンルーム（DCR）アーキテクチャ概要

> **イベント**: データで考える、沖縄の「ちょうどいい」と「もっといい」
> **主催**: Jagu'e'r 沖縄支部 × サンエー × 琉球大学
> **開催日**: 2026-04-11

---

## 1. 全体アーキテクチャ

```mermaid
graph TB
    subgraph "データ提供者（サンエー）"
        A[("サンエー POS データ<br/>（匿名化・マスク済み）")]
    end

    subgraph "プロバイダー環境 — GCP Project"
        subgraph "Cloud Storage"
            B["GCS バケット<br/>CSV ファイル"]
        end

        subgraph "BigQuery"
            C["sana_bronze<br/>（生データ格納）"]
            D["sana_meetup8<br/>（公開ビュー＋データマート）"]
        end

        subgraph "Analytics Hub（DCR）"
            E["Data Exchange:<br/>sana_ryudai_handson<br/>（プライベート・DCR モード）"]
            F["9 リスティング<br/>（エグレス制御有効）"]
        end

        B -->|bq load| C
        C -->|VIEW / CTAS| D
        D --> F
        F --> E
    end

    subgraph "サブスクライバー環境 — 参加者の GCP Project"
        G["Linked Dataset<br/>（読み取り専用）"]
        H["Gemini in BigQuery<br/>自然言語 → SQL"]
        I["Looker Studio<br/>可視化"]
    end

    A -->|"CSV アップロード"| B
    E -->|"サブスクライブ"| G
    G --> H
    G --> I

    style A fill:#FFE4B5,stroke:#D2691E
    style E fill:#E8F5E9,stroke:#2E7D32
    style G fill:#E3F2FD,stroke:#1565C0
```

---

## 2. データフロー

```mermaid
flowchart LR
    subgraph Step1["Step 1: データ前処理"]
        S1A["データ提供者"] --> S1B["個人情報 HEX エンコード<br/>原価マスク（*****）"]
    end

    subgraph Step2["Step 2: アップロード"]
        S1B --> S2A["GCS バケット<br/>bronze/ フォルダ"]
    end

    subgraph Step3["Step 3: ロード & 変換"]
        S2A --> S3A["sana_bronze<br/>（6 テーブル — 内部専用）"]
        S3A --> S3B["sana_meetup8<br/>公開ビュー（5）+ データマート（4）"]
    end

    subgraph Step4["Step 4: DCR 公開"]
        S3B --> S4A["Analytics Hub<br/>9 リスティング（全てエグレス制御付き）"]
    end

    subgraph Step5["Step 5: 参加者利用"]
        S4A --> S5A["Linked Dataset"]
        S5A --> S5B["Gemini / Looker Studio<br/>で分析"]
    end

    style Step1 fill:#FFF3E0
    style Step2 fill:#FFF3E0
    style Step3 fill:#E8F5E9
    style Step4 fill:#E8F5E9
    style Step5 fill:#E3F2FD
```

---

## 3. セキュリティ多層防御

```mermaid
graph TB
    subgraph Layer1["Layer 1: ソースデータ匿名化"]
        L1A["個人情報 → HEX エンコード"]
        L1B["原価 → マスク（*****）"]
        L1C["カード番号 → SHA-256 ハッシュ"]
    end

    subgraph Layer2["Layer 2: ビューによるカラム制御"]
        L2A["HEX カラム → 除外"]
        L2B["原価カラム → 除外"]
        L2C["店舗コード → 店舗名に変換"]
    end

    subgraph Layer3["Layer 3: エグレス制御（DCR 機能）"]
        L3A["EXPORT TO GCS → ブロック"]
        L3B["COPY → ブロック"]
        L3C["CREATE TABLE AS SELECT → ブロック"]
    end

    subgraph Layer4["Layer 4: IAM アクセス制御"]
        L4A["Google Group メンバーのみ<br/>サブスクライブ可能"]
        L4B["bigquery.jobUser<br/>bigquery.dataViewer"]
    end

    subgraph Layer5["Layer 5: プロジェクト分離"]
        L5A["プロバイダー: 運営プロジェクト"]
        L5B["サブスクライバー: 参加者の個別 Project"]
        L5C["クエリコスト → 参加者負担"]
    end

    Layer1 --> Layer2 --> Layer3 --> Layer4 --> Layer5

    style Layer1 fill:#FFEBEE,stroke:#C62828
    style Layer2 fill:#FFF3E0,stroke:#E65100
    style Layer3 fill:#FFF8E1,stroke:#F57F17
    style Layer4 fill:#E8F5E9,stroke:#2E7D32
    style Layer5 fill:#E3F2FD,stroke:#1565C0
```

---

## 4. データセット構成

### 4.1 Bronze 層（`sana_bronze`）— 内部専用・参加者には非公開

生データを格納するテーブル群。個人情報（HEX エンコード済み）や原価（マスク済み）を含むため、参加者には直接公開しない。

| テーブル | 説明 | カラム数 | 備考 | 公開ビューとの対応 |
|:---|:---|:---:|:---|:---|
| `store_master` | 店舗マスター | 2 | store_code → store_name マッピング | **ビューなし**（各ビュー内で店舗名変換に内部利用） |
| `card_master` | カードマスター | 21 | ポイントカード情報 | → 公開ビュー `card_master` |
| `customer_master` | 顧客マスター | 21 | 個人情報は HEX エンコード済み | → 公開ビュー `customer_master` |
| `customer_sales_details` | 売上明細 | 15 | cost_price はマスク済み | → 公開ビュー `customer_sales_details` |
| `food_item_master` | 食品マスター | 147 | 日本語カラム名（CSV 自動検出） | → 公開ビュー `food_item_master` |
| `shop_item_daily_performance` | 店別日別実績 | 35 | cost_price はマスク済み | → 公開ビュー `shop_item_daily_performance` |

> **ポイント**: Bronze 層は 6 テーブルだが、`store_master` は各ビュー内部で店舗コード→店舗名の変換に使用するのみで、単独の公開ビューとしては提供しない。そのため公開ビューは **5 つ**になる。

### 4.2 公開ビュー（`sana_meetup8`）— 参加者に公開（5 ビュー）

Bronze 層のテーブルから、個人情報カラム（HEX エンコード済みの氏名・生年月日・住所・電話番号）と原価カラムを除外し、店舗コードを店舗名に変換した安全なビュー。

```mermaid
erDiagram
    card_master {
        string card_no "SHA-256 ハッシュ"
        string cif_no "顧客 ID（FK）"
        string own_store_name "所属店舗名"
        string issue_store_name "発行店舗名"
        string issue_date "発行日"
        string enrollment_date "入会日"
        int today_issued_point "本日付与ポイント"
        int total_point "ポイント残高"
        int cumulative_issued_point "累計付与ポイント"
        int settled_point "精算ポイント"
        string point_update_date "ポイント更新日"
    }

    customer_master {
        string cif_no "顧客 ID（PK）"
        int gender_type "性別（1=男 2=女）"
        string occupation_code "職業コード"
        string customer_status "顧客ステータス"
    }

    customer_sales_details {
        string card_no "カード番号（FK）"
        string store_name "店舗名"
        string usage_date "利用日"
        string trans_no "取引番号"
        string product_code "商品コード（FK）"
        int amount "金額（税抜）"
        int quantity "数量"
        int tax_included_amount "金額（税込）"
    }

    food_item_master {
        string product_code "商品コード（PK）"
        string product_name "商品名"
        string product_name_kana "商品名カナ"
        string department_code "部門コード"
        string mid_category "中分類"
        string sub_category "小分類"
        int standard_price "標準売単価"
        string brand_name "ブランド名"
    }

    shop_item_daily_performance {
        string perf_date "日付"
        string store_name "店舗名"
        string product_code "商品コード（FK）"
        string department_code "部門コード"
        int selling_price "売単価"
        int sales_qty "販売数"
        int sales_amount "売上金額"
        int customer_count "客数"
    }

    customer_master ||--o{ card_master : "cif_no"
    card_master ||--o{ customer_sales_details : "card_no"
    food_item_master ||--o{ customer_sales_details : "product_code"
    food_item_master ||--o{ shop_item_daily_performance : "product_code"
```

### 4.3 データマート（`sana_meetup8`）— 参加者に公開（4 マート）

公開ビューから集計・加工した分析用の実体テーブル（`CREATE TABLE AS SELECT` で作成）。ビューと異なりマテリアライズ済みのため、参加者のクエリパフォーマンスが向上する。

| マート | 集計粒度 | 主要指標 |
|:---|:---|:---|
| `mart_daily_sales` | 日別 × 店舗別 | 取引数、売上合計、ユニーク顧客数 |
| `mart_customer_summary` | カード番号別 | 来店日数、購入回数、合計金額、平均単価 |
| `mart_product_ranking` | 商品コード別 | 販売数量、売上金額、購入者数 |
| `mart_basket_analysis` | 取引（バスケット）別 | バスケット内商品数、合計金額、平均単価 |

### 4.4 公開データ構成サマリー

| 区分 | 数量 | データセット | 形式 | 備考 |
|:---|:---:|:---|:---|:---|
| Bronze テーブル | 6 | `sana_bronze` | TABLE | **非公開**（内部専用） |
| 公開ビュー | 5 | `sana_meetup8` | VIEW | Bronze 6 テーブルのうち `store_master` を除く 5 テーブルに対応 |
| データマート | 4 | `sana_meetup8` | TABLE | 公開ビューから集計した分析用テーブル |
| **Analytics Hub リスティング合計** | **9** | — | — | 公開ビュー 5 + データマート 4 |

---

## 5. Analytics Hub（DCR）構成

### 5.1 Data Exchange

| 項目 | 値 |
|:---|:---|
| **Exchange ID** | `sana_ryudai_handson` |
| **表示名** | `sana-ryudai-handson` |
| **リージョン** | `asia-northeast1` |
| **共有環境** | DCR（データクリーンルーム）モード |
| **公開範囲** | **プライベート**（Google Group メンバーのみ） |

### 5.2 リスティング一覧（9 リスティング = ビュー 5 + マート 4）

全リスティングで **エグレス制御** が有効（`restricted_export_config.enabled = true`、`restrict_query_result = true`）。

#### 公開ビュー（5 リスティング）

Bronze 層テーブルから個人情報・原価を除外した安全なビュー。

| # | リスティング ID | 表示名 | ソース | 元テーブル（Bronze） |
|:---:|:---|:---|:---|:---|
| 1 | `card_master` | カードマスター | `sana_meetup8.card_master` (VIEW) | `sana_bronze.card_master` |
| 2 | `customer_master` | 顧客マスター | `sana_meetup8.customer_master` (VIEW) | `sana_bronze.customer_master` |
| 3 | `customer_sales_details` | 売上明細 | `sana_meetup8.customer_sales_details` (VIEW) | `sana_bronze.customer_sales_details` |
| 4 | `shop_item_daily_perf` | 店別日別実績 | `sana_meetup8.shop_item_daily_performance` (VIEW) | `sana_bronze.shop_item_daily_performance` |
| 5 | `food_item_master` | 食品マスター | `sana_meetup8.food_item_master` (VIEW) | `sana_bronze.food_item_master` |

> **補足**: Bronze 層の `store_master` は各ビュー内で `JOIN` して店舗コード→店舗名に変換するために使用。単独のリスティングとしては提供しない。

#### データマート（4 リスティング）

公開ビューから集計・加工した分析用テーブル。

| # | リスティング ID | 表示名 | ソース |
|:---:|:---|:---|:---|
| 6 | `mart_daily_sales` | 日別売上マート | `sana_meetup8.mart_daily_sales` (TABLE) |
| 7 | `mart_customer_summary` | 顧客サマリーマート | `sana_meetup8.mart_customer_summary` (TABLE) |
| 8 | `mart_product_ranking` | 商品ランキングマート | `sana_meetup8.mart_product_ranking` (TABLE) |
| 9 | `mart_basket_analysis` | バスケット分析マート | `sana_meetup8.mart_basket_analysis` (TABLE) |

### 5.3 エグレス制御の効果

| 操作 | 許可/ブロック |
|:---|:---:|
| `SELECT` クエリ（`LIMIT` 含む） | 許可 |
| Gemini in BigQuery（自然言語 → SQL） | 許可 |
| Looker Studio 接続 | 許可 |
| `EXPORT DATA` (GCS へエクスポート) | **ブロック** |
| `CREATE TABLE AS SELECT` | **ブロック** |
| `COPY` (他テーブルへコピー) | **ブロック** |

---

## 6. IAM・アクセス制御

```mermaid
graph LR
    subgraph "Analytics Hub"
        AH["Data Exchange<br/>sana_ryudai_handson"]
    end

    subgraph "IAM Roles"
        R1["analyticshub.subscriber"]
        R2["bigquery.jobUser"]
        R3["bigquery.dataViewer"]
    end

    subgraph "プリンシパル"
        G["参加者用<br/>Google Group"]
        M["データ提供者"]
    end

    subgraph "Cloud Storage"
        BUCKET["GCS バケット"]
    end

    G -->|R1| AH
    G -->|R2| AH
    G -->|R3| AH
    M -->|"storage.objectAdmin"| BUCKET

    style G fill:#E3F2FD,stroke:#1565C0
    style M fill:#FFF3E0,stroke:#E65100
```

| ロール | プリンシパル | 用途 |
|:---|:---|:---|
| `analyticshub.subscriber` | 参加者用 Google Group | DCR リスティングへのサブスクライブ |
| `bigquery.jobUser` | 参加者用 Google Group | Linked Dataset でのクエリ実行 |
| `bigquery.dataViewer` | 参加者用 Google Group | Linked Dataset のテーブル閲覧 |
| `storage.objectAdmin` | データ提供者 | GCS へのデータアップロード |

---

## 7. 監査ログ

| サービス | ログタイプ | 目的 |
|:---|:---|:---|
| `bigquery.googleapis.com` | ADMIN_READ, DATA_READ, DATA_WRITE | 全クエリ・データアクセスの記録 |
| `analyticshub.googleapis.com` | ADMIN_READ, DATA_READ | サブスクライブ操作の記録 |

---

## 8. 匿名化方針

### データ要素ごとの処理

| データ要素 | 処理方法 | 公開ビューでの扱い |
|:---|:---|:---|
| カード番号 | SHA-256 ハッシュ（ビュー層） | ハッシュ値として公開（結合は可能） |
| 顧客 ID（cif_no） | 追加処理なし | そのまま公開（結合キー） |
| 氏名 | HEX エンコード（Bronze 層） | **除外** |
| 生年月日 | HEX エンコード（Bronze 層） | **除外** |
| 住所 | HEX エンコード（Bronze 層） | **除外** |
| 電話番号 | HEX エンコード（Bronze 層） | **除外** |
| 性別 | コード値（1/2） | 公開 |
| 職業コード | 2 桁コード | 公開 |
| 店舗コード | 店舗名に変換（ビュー層） | 店舗名として公開 |
| 原価 | マスク済み（*****） | **完全除外** |

---

## 9. 参加者のサブスクライブフロー

```mermaid
sequenceDiagram
    participant P as 参加者
    participant GCP as 参加者の GCP Project
    participant AH as Analytics Hub
    participant PJ as プロバイダー Project

    P->>GCP: 個人 Gmail で GCP Project 作成<br/>（バウチャー適用）
    P->>AH: Analytics Hub を開く
    P->>AH: "sana-ryudai-handson" を検索
    AH-->>P: DCR リスティング一覧を表示
    P->>AH: リスティングをサブスクライブ
    AH->>GCP: Linked Dataset を作成<br/>（sana_meetup8）
    P->>GCP: BigQuery でクエリ実行<br/>（Gemini / 手動 SQL）
    GCP->>PJ: クエリがプロバイダーの<br/>ビュー/テーブルを参照
    PJ-->>GCP: 結果を返却<br/>（エグレス制御適用）
    GCP-->>P: クエリ結果を表示

    Note over P,PJ: クエリコストは参加者の<br/>Project に課金される
```
