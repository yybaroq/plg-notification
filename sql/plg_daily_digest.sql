-- ============================================================================
-- PLG Daily Digest — scoring + digest-text builder
-- ----------------------------------------------------------------------------
-- Runs in the Anycross workflow MySQL node (credential "TiDB APAC RO").
-- Reads product telemetry from regional_support.apac_active_tenants, scores
-- every active APAC tenant on the PQL Signal Model (Activity/Fit/Urgency),
-- assigns P0/P1/P2, and emits ONE column `digest_text`: a preformatted Feishu
-- message (queue counts + Top-10 P0/P1 rows with the reason breakdown).
--
-- The single-string output is intentional: the downstream custom-bot node just
-- forwards $.mysql-1.result[0].digest_text to the group webhook.
--
-- NOTE ON TABLE NAME: the credential's default DB is information_schema, so the
-- source table is fully qualified as regional_support.apac_active_tenants.
--
-- NOTE ON SET_VAR HINT: GROUP_CONCAT truncates at group_concat_max_len (default
-- 1024). Ten rows with the reason + tenant_id columns exceed that, so we raise
-- it to 4096 via an optimizer hint on the outer SELECT.
--
-- Scoring reference: docs/scoring_model.md
-- ============================================================================

WITH base AS (
  SELECT
    x.*,
    (act + fit + urg) AS my_score,
    CASE
      -- P0: strong production usage OR AI-core with recency/POC OR very high total
      WHEN qps >= 50
        OR (qps >= 10 AND cat = 'company_ai_core')
        OR (n24 = 1 AND cat = 'company_ai_core')
        OR (pl = 'poc' AND cat IN ('company_ai_core', 'company_ai_related'))
        OR ((act + fit + urg) >= 75 AND cat <> 'individual')
        THEN 'P0'
      -- P1: meaningful total OR AI-related recency OR enterprise new OR multi-cluster no-card OR error
      WHEN (act + fit + urg) >= 45
        OR (n48 = 1 AND cat = 'company_ai_related')
        OR (n24 = 1 AND cat = 'company_non_ai' AND ent = 1)
        OR (cc >= 3 AND card = 0 AND cat <> 'individual')
        OR err = 1
        THEN 'P1'
      ELSE 'P2'
    END AS my_priority
  FROM (
    -- ---- layer 2: score the three dimensions ----
    SELECT
      y.*,
      -- Activity (cap 40): QPS tier + cluster bands + card + qps-without-card
      LEAST(40,
        (CASE WHEN qps >= 1 THEN 25 WHEN qps >= 0.001 THEN 12 ELSE 0 END)
        + (CASE WHEN cc >= 1  THEN 10 ELSE 0 END)
        + (CASE WHEN cc >= 3  THEN 8  ELSE 0 END)
        + (CASE WHEN cc >= 10 THEN 5  ELSE 0 END)
        + (CASE WHEN card = 1 THEN 10 ELSE 0 END)
        + (CASE WHEN qps >= 1 AND card = 0 THEN 5 ELSE 0 END)
      ) AS act,
      -- Fit (cap 30): AI category, enterprise vs freemail for non-AI companies
      (CASE cat
        WHEN 'company_ai_core'    THEN 30
        WHEN 'company_ai_related' THEN 20
        WHEN 'institution_non_ai' THEN 8
        WHEN 'individual'         THEN 0
        WHEN 'company_non_ai'     THEN (CASE WHEN ent = 1 THEN 15 WHEN freem = 1 THEN 5 ELSE 3 END)
        ELSE 3
      END) AS fit,
      -- Urgency (cap 30): recency×AI, POC, high QPS, multi-cluster no-card, error
      LEAST(30,
        (CASE WHEN n24 = 1 AND cat = 'company_ai_core'    THEN 20 ELSE 0 END)
        + (CASE WHEN n48 = 1 AND cat = 'company_ai_related' THEN 15 ELSE 0 END)
        + (CASE WHEN pl = 'poc' THEN 15 ELSE 0 END)
        + (CASE WHEN qps >= 50  THEN 15 ELSE 0 END)
        + (CASE WHEN cc >= 3 AND card = 0 AND cat <> 'individual' THEN 12 ELSE 0 END)
        + (CASE WHEN err = 1 THEN 10 ELSE 0 END)
      ) AS urg
    FROM (
      -- ---- layer 1: normalize raw columns into scoring inputs ----
      SELECT
        tenant_id,
        name,
        email_domain,
        LOWER(TRIM(COALESCE(entity_ai_category, 'unknown'))) AS cat,
        COALESCE(tenant_avg_qps, 0)    AS qps,
        COALESCE(cluster_count, 0)     AS cc,
        COALESCE(has_credit_card, 0)   AS card,
        LOWER(TRIM(COALESCE(plan, ''))) AS pl,
        CASE WHEN TRIM(COALESCE(error_message, '')) <> '' THEN 1 ELSE 0 END AS err,
        CASE WHEN created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR) THEN 1 ELSE 0 END AS n24,
        CASE WHEN created_at >= DATE_SUB(NOW(), INTERVAL 48 HOUR) THEN 1 ELSE 0 END AS n48,
        -- ent: corporate (non-freemail) domain
        CASE WHEN LOWER(TRIM(COALESCE(email_domain, ''))) <> ''
              AND LOWER(TRIM(COALESCE(email_domain, ''))) NOT IN (
                'gmail.com','googlemail.com','hotmail.com','outlook.com','live.com',
                'msn.com','icloud.com','me.com','mac.com','yahoo.com','ymail.com',
                'aol.com','proton.me','protonmail.com','qq.com','163.com','126.com')
             THEN 1 ELSE 0 END AS ent,
        -- freem: known free-mail domain
        CASE WHEN LOWER(TRIM(COALESCE(email_domain, ''))) IN (
                'gmail.com','googlemail.com','hotmail.com','outlook.com','live.com',
                'msn.com','icloud.com','me.com','mac.com','yahoo.com','ymail.com',
                'aol.com','proton.me','protonmail.com','qq.com','163.com','126.com')
             THEN 1 ELSE 0 END AS freem
      FROM regional_support.apac_active_tenants
    ) y
  ) x
)
SELECT /*+ SET_VAR(group_concat_max_len=4096) */
  CONCAT(
    '📊 TiDB APAC PLG Daily Digest\n',
    '队列：P0 ', CAST(SUM(my_priority = 'P0') AS CHAR),
    ' | P1 ',    CAST(SUM(my_priority = 'P1') AS CHAR),
    ' | P2 ',    CAST(SUM(my_priority = 'P2') AS CHAR),
    ' | 总 ',    CAST(COUNT(*) AS CHAR),
    '\n\nTop P0/P1（名称 | 分 | 级 | 域名 | 原因 | tenant_id）：\n',
    COALESCE((
      SELECT GROUP_CONCAT(line SEPARATOR '\n')
      FROM (
        SELECT CONCAT(
          LEFT(COALESCE(name, '-'), 18), ' | ',
          my_score, ' | ',
          my_priority, ' | ',
          LEFT(COALESCE(email_domain, '-'), 22), ' | ',
          -- reason column: the signals that actually fired, "·"-joined
          COALESCE(NULLIF(CONCAT_WS('·',
            CASE WHEN qps >= 50 THEN CONCAT('QPS', ROUND(qps))
                 WHEN qps >= 1  THEN CONCAT('QPS', ROUND(qps, 1))
                 WHEN qps >= 0.001 THEN '低QPS' ELSE NULL END,
            CASE cat WHEN 'company_ai_core' THEN 'AI-core'
                     WHEN 'company_ai_related' THEN 'AI-rel' ELSE NULL END,
            CASE WHEN n24 = 1 THEN '24h新注册'
                 WHEN n48 = 1 THEN '48h新注册' ELSE NULL END,
            CASE WHEN pl = 'poc' THEN 'POC' ELSE NULL END,
            CASE WHEN cc >= 3 THEN CONCAT(cc, '集群') ELSE NULL END,
            CASE WHEN card = 1 THEN '绑卡' ELSE NULL END,
            CASE WHEN err = 1 THEN '报错' ELSE NULL END
          ), ''), '-'), ' | ',
          COALESCE(tenant_id, '-')
        ) AS line
        FROM base
        WHERE my_priority IN ('P0', 'P1')
        ORDER BY my_score DESC
        LIMIT 10
      ) t
    ), '（今日无 P0/P1）')
  ) AS digest_text
FROM base;
