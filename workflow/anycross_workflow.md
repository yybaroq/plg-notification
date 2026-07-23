# Anycross Workflow — digest delivery (11:00)

Platform: Feishu 集成平台 (anycross.feishu.cn)
Workflow: **APAC GTM Daily Digest** — integration `7661478093248285654`,
workflow `7661478774365522886`.

Three nodes, linear:

## 1. Cron trigger — `cronjob_trigger-1`
Daily 11:00 (GMT+8).

## 2. MySQL — `mysql-1`
- Credential: **TiDB APAC RO** (read-only). Default DB is `information_schema`,
  so the source table is fully qualified: `regional_support.apac_active_tenants`.
- Operation: custom SQL = [`sql/plg_daily_digest.sql`](../sql/plg_daily_digest.sql).
- Output: a single field `digest_text` (one preformatted message string).

## 3. Feishu custom bot — `custom-robot-1`
- Type: 飞书自定义机器人 (custom bot, webhook-based — **not** the Timoc app node).
- Bot / webhook ID: `c4914675-f48f-4913-b062-7e37c105857f`
  (full: `https://open.feishu.cn/open-apis/bot/v2/hook/c4914675-f48f-4913-b062-7e37c105857f`).
- Message type: text.
- Message content: expression pill `$.mysql-1.result[0].digest_text`.
- **Keyword filter:** the target group's bot requires the keyword `TiDB` — the
  digest title starts with "📊 TiDB APAC PLG Daily Digest" to satisfy it.

Target group: "TiDB Bots" `oc_e31cc48f07e15c78d8f544068284d69d`.

---

## Editing notes (the canvas is a `<canvas>` render — hover toolbars don't take synthetic clicks)

- **Enter edit mode:** in preview, click a node to open its panel, then click
  「编辑」. In edit mode, clicking a node only selects it (no panel).
- **Delete a node:** select it, then **Cmd+X** → a confirm dialog appears →
  「删除」. The trash icon and Delete/Backspace keys do nothing.
- **Edit SQL programmatically (CodeMirror 6):**
  `document.querySelector('.cm-content').cmView.view.dispatch({changes:{from,to,insert}})`
  — precise replacement beats retyping the whole statement.
- **Expression field (e.g. bot message):** switch the field type to `expression`
  (Aa▾ menu — switching clears the field); type `$` to get the `$.` prefix chip,
  then the path **without a leading dot** (`mysql-1.result[0].digest_text`), and
  click the "使用选项" row to confirm it into a pill.
- **Save / test / publish:** 「完成」saves → 「调试」(generate default output →
  run; three nodes green sends a real test message to the group) → 「发布」.
  Publish takes effect immediately. Old test messages can't be deleted (they're
  from the webhook app identity).

## To English-ify the digest text
Edit the `CONCAT(...)` label strings in `sql/plg_daily_digest.sql`
(`队列` → `Queue`, `名称 | 分 | 级 | 域名 | 原因 | tenant_id` → `Name | Score | Tier | Domain | Reason | tenant_id`,
and the reason labels `低QPS/24h新注册/48h新注册/集群/绑卡/报错` → English), save,
and re-publish. The enrichment task parses positionally, so keep the column
order and the `·` reason separator.
