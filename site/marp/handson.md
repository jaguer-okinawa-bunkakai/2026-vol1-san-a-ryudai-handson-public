---
marp: true
theme: default
paginate: true
size: 16:9
style: |
  /* Jagu'e'r Okinawa カスタムテーマ */
  :root {
    --color-primary: #4285F4;
    --color-primary-dark: #3367D6;
    --color-accent: #EA4335;
    --color-accent-orange: #F5A623;
    --color-bg: #ffffff;
    --color-text: #333333;
    --color-text-light: #666666;
  }

  /* 通常スライド: 花柄背景 */
  section {
    font-family: 'Noto Sans JP', 'Hiragino Kaku Gothic ProN', sans-serif;
    color: var(--color-text);
    background-image: url('./assets/bg.png');
    background-size: cover;
    background-position: center;
    padding: 60px 80px;
  }

  /* セクション区切りスライド */
  section.section {
    background-image: url('./assets/section.png');
    background-size: cover;
    background-position: center;
    color: white;
    padding: 80px 100px;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  section.section h1 {
    color: white;
    font-size: 2.5em;
    font-weight: bold;
    border-bottom: none;
    text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
  }
  section.section h2 {
    color: rgba(255,255,255,0.9);
    font-size: 1.5em;
    border-bottom: none;
    text-shadow: 1px 1px 3px rgba(0,0,0,0.2);
  }

  /* 見出し */
  h1 {
    color: var(--color-primary);
    font-weight: bold;
    font-size: 1.8em;
  }
  h2 {
    color: var(--color-primary-dark);
    border-bottom: 3px solid var(--color-primary);
    padding-bottom: 8px;
    font-size: 1.3em;
  }

  /* テーブル */
  table {
    font-size: 0.72em;
    width: 100%;
    border-collapse: collapse;
  }
  th {
    background-color: var(--color-primary);
    color: white;
    padding: 8px 12px;
  }
  td {
    padding: 6px 12px;
    border-bottom: 1px solid #e0e0e0;
  }

  /* コードブロック */
  pre {
    background-color: #f5f5f5;
    border-left: 4px solid var(--color-primary);
    font-size: 0.7em;
  }

  /* blockquote */
  blockquote {
    border-left: 4px solid var(--color-accent-orange);
    background-color: rgba(245, 166, 35, 0.08);
    padding: 8px 16px;
    font-size: 0.85em;
  }

  /* ページ番号 */
  section::after {
    font-size: 0.6em;
    color: #999;
  }
---

<!-- _class: section -->

# 環境セットアップ

---

<!-- ※ Step 1（バウチャー有効化）& Step 2（プロジェクト作成）は全体スライド p.28 で実施 -->

<!-- S3-1: Analytics Hub 概要 -->

# Analytics Hub でデータを取得しよう

<br>

**BigQuery**（Google Cloud のデータ分析基盤）に、
サンエー様のデータを追加するための手順です。

**Analytics Hub** を使って、共有されたデータセットを自分のプロジェクトに取得します。

<br>

| やること | 内容 |
|---------|------|
| **検索** | Analytics Hub でリスティングを検索 |
| **サブスクライブ** | リスティングを選んで自分のプロジェクトに追加 |
| **結果** | BigQuery にデータセットが作成される |

---

<!-- S3-2: Analytics Hub 手順① -->

# Analytics Hub: リスティングを検索

<br>

**1. BigQuery コンソールから Analytics Hub を開く**

<br>

**2. 検索ボックスで `sana-ryudai-handson` を検索**

<!-- ⚠️ TODO: リスティング名を要確認（sana-ryudai-handson） -->

<br>

**3. リスティング一覧が表示される**

サブスクライブするリスティングは **全部で9個** あります

<!-- ⚠️ TODO: リスティング検索〜一覧のスクリーンショットを挿入 -->

---

<!-- S3-3: Analytics Hub 手順② -->

# Analytics Hub: サブスクライブ

<br>

**4. リスティングを選択 →「サブスクライブ」をクリック**

<br>

**5. プロジェクトを選択 → データセット名はそのままでOK**

<br>

**6. 9個すべてのリスティングをサブスクライブ**

完了すると、BigQuery のエクスプローラにデータセットが表示されます

<!-- ⚠️ TODO: サブスクライブ画面のスクリーンショットを挿入 -->

---

<!-- S3-4: Analytics Hub 完了確認 -->

# サブスクライブの確認

BigQuery コンソール → エクスプローラで以下が表示されていればOK

| テーブル名 | 内容 |
|----------|------|
| `customer_sales_details` | 顧客売上明細 |
| `shop_item_daily_performance` | 店別単品別実績（日別） |
| `card_master` / `customer_master` / `food_item_master` | 各種マスター |
| `mart_daily_sales` | 日別×店舗別売上 |
| `mart_customer_summary` / `mart_product_ranking` / `mart_basket_analysis` | 集計マート |

> 全部で **9個** 表示されていればOK。表示されない場合はTAに声をかけてください！

---

<!-- S3-5: テーブル概要 -->

# 今日使うデータの全体像

サンエー様のPOSデータ（2025年8〜9月・匿名化済み）

| テーブル | 内容 | 件数 |
|---------|------|------|
| `customer_sales_details` | 顧客ごとの売上明細（日付・商品・金額） | 約7,500万件 |
| `shop_item_daily_performance` | 店舗×商品の日別実績 | 約5,800万件 |
| `card_master` | ポイントカード情報 | 約258万件 |
| `customer_master` | 顧客属性 | 約141万件 |
| `food_item_master` | 食品商品マスター | 約63万件 |
| `mart_daily_sales` | 日別×店舗別の売上集計 | 約5,400件 |
| `mart_customer_summary` | 顧客ごとの購買サマリー | 約59万件 |
| `mart_product_ranking` | 商品ランキング | 約29万件 |
| `mart_basket_analysis` | 買い物かご分析 | 約960万件 |

---

<!-- S4-1: エージェント構築 概要 -->

# エージェントを構築しよう

<br>

**Conversational Analytics** で自然言語分析をするには、
**エージェント（Data Agent）** の構築が必要です。

<br>

| やること | 内容 |
|---------|------|
| **① SELECT 1 を実行** | テーブルを「最近使用したアイテム」に表示させる |
| **② 会話を作成** | テーブルからエージェントを作成 |
| **③ ナレッジソース追加** | 他のテーブルもエージェントに追加 |

<br>

> エージェントは他の人と共有できないため、**各自で構築**する必要があります

---

<!-- S4-2: エージェント構築 手順① -->

# エージェント構築: SELECT 1 を実行

<br>

**BigQuery のクエリエディタで以下を実行してください：**

```sql
SELECT 1 FROM `{プロジェクトID}.{データセット名}.mart_daily_sales` LIMIT 1;
```

<br>

これを **各テーブルに対して実行** します
→ 「最近使用したアイテム」に表示されるようになります

<br>

> 9テーブルすべてに実行してください

<!-- ⚠️ TODO: スクリーンショットを挿入 -->

---

<!-- S4-3: エージェント構築 手順② -->

# エージェント構築: 会話を作成

<br>

1. エクスプローラでテーブルを選択
2. **「会話を作成」** をクリック
3. エージェントが作成されます

<!-- ⚠️ TODO: 「会話を作成」ボタンのスクリーンショットを挿入 -->

---

<!-- S4-4: エージェント構築 手順③ -->

# エージェント構築: ナレッジソースを追加

<br>

1. エージェント画面で **「ナレッジソースを追加」** をクリック
2. **「最近使用したアイテム」** からテーブルを選択
3. 分析に使いたいテーブルを **すべて追加**

<br>

> 複数のテーブルを追加することで、テーブル間の結合分析も可能になります！

<!-- ⚠️ TODO: ナレッジソース追加画面のスクリーンショットを挿入 -->

---

<!-- S4-5: エージェント構築 完了 -->

# セットアップ完了！

<br>

これで **Conversational Analytics** を使って
自然言語でサンエー様のデータを分析できるようになりました！

<br>

> うまくいかない場合はTAに声をかけてください
> お昼休憩中もサポートします

---

<!-- _class: section -->

# Conversational Analytics を体験しよう

---

<!-- S5: デモ -->

# Conversational Analytics を体験

<br>

セットアップが完了したら、実際にデータにアクセスしてみましょう！

<br>

**Conversational Analytics** に何か聞いてみてください：

<br>

> 例: _「どんなテーブルがありますか？」_
> 例: _「売上データの件数は？」_
> 例: _「店舗は何店舗ある？」_

<br>

結果が出たら周りの人と見比べてみてください。

---

<!-- S7: ルール説明・チーム確認 -->

# 午後のハンズオン

## 1. まず共通課題を全員で

「売上が一番高かった日はいつ？その日に何があった？」に取り組みます

## 2. 次にチーム課題

チームごとに指定されたテーマで自由に分析・深堀り

## 3. 最後にチーム発表

チーム課題の分析結果を発表（発表時間：**3分**）

> 困ったらTAに声をかけてください！

---

<!-- _class: section -->

# 共通課題

---

<!-- S8: 共通課題 Q1 -->

# 売上が一番高かった日はいつ？

## その日に何があった？

<br>

**Conversational Analytics** に聞いてみましょう：

<br>

> _「売上が一番高かった日はいつですか？」_

<br>

結果が出たら周りの人と見比べてみてください。

---

<!-- S8-2: Q1 答え -->

# 共通課題の答え

## 9月6日（土） 売上 **8.6億円**

<br>

この日は **旧盆ウークイ（送り盆）** でした！

<br>

| 日付 | 曜日 | 売上 | イベント |
|------|------|------|---------|
| 9/3 (水) | 水 | 7.4億 | 買い出しピーク |
| 9/4 (木) | 木 | 6.1億 | **ウンケー（迎え盆）** |
| 9/5 (金) | 金 | 5.4億 | ナカヌヒー（中日） |
| **9/6 (土)** | **土** | **8.6億** | **ウークイ（送り盆）** |
| 9/7 (日) | 日 | 4.2億 | 急落 |

---

<!-- S8-3: Q1 解説 -->

# 旧盆の3日間がデータに刻まれている

<br>

**2025年の旧盆（旧暦7月13〜15日）**

- **9/4 ウンケー（迎え盆）**: ご先祖様をお迎えする日
- **9/5 ナカヌヒー（中日）**: 親戚が集まる日
- **9/6 ウークイ（送り盆）**: ご先祖様をお送りする日 ← **最高売上日！**

<br>

沖縄最大の行事。帰省・お供え・食料品の需要が集中
→ データを見ると、文化が見える！

---

<!-- _class: section -->

# チーム課題

---

<!-- S9: チーム課題一覧 -->

# チーム課題テーマ

<br>

チームごとに指定されたテーマで **自由に分析・深堀り** してください。

| チーム | テーマ |
|--------|-------|
| A | **旧盆に何が売れた？通常の何倍？** |
| B | **曜日で売上に差はある？「日曜が一番売れる」は本当？** |
| C | **一番売れている商品は？時期で変わる？** |
| D | **台風が来ると何が売れる？（8/14前後）** |
| E | **旧盆が4日間ある店舗は？** |
| F | **営業時間が早く終わる日は？** |

<br>

> 答えは1つではありません。データから何が見えたか、チームで議論してください。
> 早く終わったら他のテーマにも挑戦！

---

<!-- S10: 発表準備リマインド -->

# 発表準備タイム

## 残り15分です！

<br>

チームで発表内容をまとめてください（発表時間：**3分**）

<br>

**発表のポイント:**

1. どんな問いを立てたか
2. データから何が見えたか
3. 気づき・発見・感想

<!-- ⚠️ TODO: 発表フォーマットのテンプレートリンク or QRコード -->

---

<!-- _class: section -->

# 成果発表

---

<!-- S11: 発表タイム -->

# チーム発表（各チーム3分）

<br>

<!-- ⚠️ TODO: タイマー表示の仕組みを検討 -->

| 順番 | チーム | テーマ |
|------|--------|-------|
| 1 | A | 旧盆に何が売れた？通常の何倍？ |
| 2 | B | 曜日で売上に差はある？「日曜が一番売れる」は本当？ |
| 3 | C | 一番売れている商品は？時期で変わる？ |
| 4 | D | 台風が来ると何が売れる？（8/14前後） |
| 5 | E | 旧盆が4日間ある店舗は？ |
| 6 | F | 営業時間が早く終わる日は？ |

---

<!-- _class: section -->

# 講評

---

<!-- S12: 講評 -->

# 講評

<br>

**丸山さん**（サンエー）
業務視点からのコメント

<br>

**岡崎先生**（琉球大学）
データサイエンス視点からの講評

<br>

**アイパー隊長**
全体講評

---

<!-- _class: section -->

# クロージング

---

<!-- S13: クロージング -->

# 本日はありがとうございました！

<br>

## 回答・解説資料

> 全問の回答・解説は以下からアクセスできます

<!-- ⚠️ TODO: 当日までに必ず差し替え — 回答・解説資料の QRコード or URL -->

<br>

## BBQへ移動！

- **会場**: 西原きらきらビーチ
- **時間**: 16:00〜19:00（20:00 完全撤収）
- **場所詳細**: バーベキューエリア「東8（あがりはち）」
- **参加費**: 社会人 3,000円 ／ 学生 無料
