/* The {{V:column}} markers are filled in by app.py. For one page of results they become
   "AND column IN (<the active page's village ids>)", so all heavy subqueries are reduced to
   the current page before the expensive asset/ranking aggregation runs. Inline derived tables
   are used instead of CTEs for compatibility with older MySQL versions. */
SELECT
    gds.district_name AS District,
    gds.block_name    AS Block_name,
    gds.VillageName   AS panchayat_name,
    gds.villageId     AS PanchayatId,

    CASE WHEN cd.surveyed = 1 THEN 'Yes' ELSE 'No' END AS `Survey Started (Yes/No)`,

    COALESCE(cd.total_assets, 0)           AS `Total assets uploaded`,
    COALESCE(cd.all_building_assets, 0)    AS `All_Building_assets`,
    COALESCE(cd.street_assets, 0)          AS `Street_assets`,
    COALESCE(cd.other_assets, 0)           AS `Other_assets`,
    COALESCE(cd.All_assets_for_ranking, 0) AS `All_assets_for_ranking (Building & Other_Assets)`,

    COALESCE(rk.GS_ranked, 0)   AS `Assets Ranked by GS`,
    COALESCE(rk.Bdpo_ranked, 0) AS `Assets Ranked by BDPO`,

    COALESCE(cd.All_assets_for_ranking, 0) - COALESCE(rk.GS_ranked, 0)
                                           AS `Pending assets for Ranking by Gram sachiv`,

    COALESCE(rk.building_ranked, 0)        AS `Building ranked`,
    COALESCE(rk.other_asset_ranked, 0)     AS `Other asset ranked`,
    COALESCE(rk.excellent_iconic, 0)       AS `Excellent/Iconic GS`,
    COALESCE(rk.excellent_iconic_bdpo, 0)  AS `Excellent/Iconic Bdpo`

FROM gp_data_sfc gds
JOIN (
    SELECT gds.villageId
    FROM gp_data_sfc gds
    WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}
) pv ON pv.villageId = gds.villageId

LEFT JOIN
(
    SELECT
        cplo_village_code,
        MAX(surveyed)         AS surveyed,
        SUM(b + s + o + l + g) AS total_assets,
        SUM(b + o + l + g)     AS All_assets_for_ranking,
        SUM(b + l + g)         AS all_building_assets,
        SUM(s)                 AS street_assets,
        SUM(o)                 AS other_assets
    FROM
    (
        SELECT b.cplo_village_code, 1 AS surveyed,
               COUNT(DISTINCT CASE
                   WHEN LOWER(TRIM(COALESCE(b.gs_approved_status, ''))) <> 'rejected'
                    AND LOWER(TRIM(COALESCE(b.it_approved_status, ''))) <> 'rejected'
                    AND (b.aracm_id <> 15 OR (b.aracm_id = 15 AND b.is_shop_available = 1))
                   THEN b.buid_id END) AS b,
               0 AS s, 0 AS o, 0 AS l, 0 AS g
        FROM sfc_live_test.rad_building_form_tbl b
        JOIN (
            SELECT gds.villageId FROM gp_data_sfc gds
            WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}
        ) pv ON pv.villageId = b.cplo_village_code
        WHERE b.cplo_user_id IS NOT NULL
        GROUP BY b.cplo_village_code

        UNION ALL

        SELECT s.cplo_village_code, 0,
               0,
               COUNT(DISTINCT s.st_id),
               0, 0, 0
        FROM sfc_live_test.rad_street_form_tbl s
        JOIN (
            SELECT gds.villageId FROM gp_data_sfc gds
            WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}
        ) pv ON pv.villageId = s.cplo_village_code
        WHERE s.cplo_user_id IS NOT NULL
        GROUP BY s.cplo_village_code

        UNION ALL

        SELECT o.cplo_village_code, 1, 0, 0,
               COUNT(DISTINCT CASE
                   WHEN LOWER(TRIM(COALESCE(o.gs_approved_status, ''))) <> 'rejected'
                    AND LOWER(TRIM(COALESCE(o.it_approved_status, ''))) <> 'rejected'
                    AND o.oth_asset_id IN (14, 15, 16, 17, 18, 19)
                   THEN o.oth_id END),
               0, 0
        FROM sfc_live_test.rad_other_assets_form_tbl o
        JOIN (
            SELECT gds.villageId FROM gp_data_sfc gds
            WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}
        ) pv ON pv.villageId = o.cplo_village_code
        WHERE o.cplo_user_id IS NOT NULL AND o.oth_avail_stat = 1
        GROUP BY o.cplo_village_code

        UNION ALL

        SELECT l.cplo_village_code, 1, 0, 0, 0,
               COUNT(DISTINCT CASE
                   WHEN LOWER(TRIM(COALESCE(l.gs_approved_status, ''))) <> 'rejected'
                    AND LOWER(TRIM(COALESCE(l.it_approved_status, ''))) <> 'rejected'
                   THEN l.id END),
               0
        FROM sfc_live_test.rad_library_form_tbl l
        JOIN (
            SELECT gds.villageId FROM gp_data_sfc gds
            WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}
        ) pv ON pv.villageId = l.cplo_village_code
        WHERE l.cplo_user_id IS NOT NULL AND l.is_library_available = 1
        GROUP BY l.cplo_village_code

        UNION ALL

        SELECT g.cplo_village_code, 1, 0, 0, 0, 0,
               COUNT(DISTINCT CASE
                   WHEN LOWER(TRIM(COALESCE(g.gs_approved_status, ''))) <> 'rejected'
                    AND LOWER(TRIM(COALESCE(g.it_approved_status, ''))) <> 'rejected'
                   THEN g.id END)
        FROM sfc_live_test.rad_gym_form_tbl g
        JOIN (
            SELECT gds.villageId FROM gp_data_sfc gds
            WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}
        ) pv ON pv.villageId = g.cplo_village_code
        WHERE g.cplo_user_id IS NOT NULL AND g.is_gym_available = 1
        GROUP BY g.cplo_village_code
    ) x
    GROUP BY cplo_village_code
) cd
    ON cd.cplo_village_code = gds.villageId

LEFT JOIN
(
    SELECT
        r.village_code,
        COUNT(DISTINCT CASE WHEN r.gs_rank IS NOT NULL
                            THEN CONCAT(r.asset_type, '-', r.asset_id) END) AS GS_ranked,
        COUNT(DISTINCT CASE WHEN r.bdpo_user_id IS NOT NULL AND r.bdpo_rank IS NOT NULL
                            THEN CONCAT(r.asset_type, '-', r.asset_id) END) AS Bdpo_ranked,
        COUNT(DISTINCT CASE WHEN e.asset_type IN ('building', 'library', 'gym')
                             AND r.gs_rank IS NOT NULL
                            THEN CONCAT(r.asset_type, '-', r.asset_id) END) AS building_ranked,
        COUNT(DISTINCT CASE WHEN e.asset_type = 'other asset'
                             AND r.gs_rank IS NOT NULL
                            THEN CONCAT(r.asset_type, '-', r.asset_id) END) AS other_asset_ranked,
        COUNT(DISTINCT CASE WHEN r.sub_category_id NOT IN (14, 15, 21)
                             AND CONVERT(r.gs_rank USING utf8mb4)
                                 COLLATE utf8mb4_general_ci = _utf8mb4'Excellent/Iconic'
                            THEN CONCAT(r.asset_type, '-', r.asset_id) END) AS excellent_iconic,
        COUNT(DISTINCT CASE WHEN r.sub_category_id NOT IN (14, 15, 21)
                             AND r.bdpo_user_id IS NOT NULL
                             AND CONVERT(r.bdpo_rank USING utf8mb4)
                                 COLLATE utf8mb4_general_ci = _utf8mb4'Excellent/Iconic'
                            THEN CONCAT(r.asset_type, '-', r.asset_id) END) AS excellent_iconic_bdpo
    FROM rad_asset_ranking_tbl r
    JOIN
    (
        SELECT DISTINCT b.cplo_village_code AS village_code, b.buid_id AS asset_id,
               _utf8mb4'building' COLLATE utf8mb4_general_ci AS asset_type
        FROM sfc_live_test.rad_building_form_tbl b
        JOIN (
            SELECT gds.villageId FROM gp_data_sfc gds
            WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}
        ) pv ON pv.villageId = b.cplo_village_code
        WHERE b.cplo_user_id IS NOT NULL
          AND b.buid_id IS NOT NULL
          AND LOWER(TRIM(COALESCE(b.gs_approved_status, ''))) <> 'rejected'
          AND LOWER(TRIM(COALESCE(b.it_approved_status, ''))) <> 'rejected'
          AND (b.aracm_id <> 15 OR (b.aracm_id = 15 AND b.is_shop_available = 1))

        UNION ALL

        SELECT DISTINCT o.cplo_village_code AS village_code, o.oth_id AS asset_id,
               _utf8mb4'other asset' COLLATE utf8mb4_general_ci AS asset_type
        FROM sfc_live_test.rad_other_assets_form_tbl o
        JOIN (
            SELECT gds.villageId FROM gp_data_sfc gds
            WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}
        ) pv ON pv.villageId = o.cplo_village_code
        WHERE o.cplo_user_id IS NOT NULL
          AND o.oth_id IS NOT NULL
          AND o.oth_avail_stat = 1
          AND o.oth_asset_id IN (14, 15, 16, 17, 18, 19)
          AND LOWER(TRIM(COALESCE(o.gs_approved_status, ''))) <> 'rejected'
          AND LOWER(TRIM(COALESCE(o.it_approved_status, ''))) <> 'rejected'

        UNION ALL

        SELECT DISTINCT l.cplo_village_code AS village_code, l.id AS asset_id,
               _utf8mb4'library' COLLATE utf8mb4_general_ci AS asset_type
        FROM sfc_live_test.rad_library_form_tbl l
        JOIN (
            SELECT gds.villageId FROM gp_data_sfc gds
            WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}
        ) pv ON pv.villageId = l.cplo_village_code
        WHERE l.cplo_user_id IS NOT NULL
          AND l.id IS NOT NULL
          AND l.is_library_available = 1
          AND LOWER(TRIM(COALESCE(l.gs_approved_status, ''))) <> 'rejected'
          AND LOWER(TRIM(COALESCE(l.it_approved_status, ''))) <> 'rejected'

        UNION ALL

        SELECT DISTINCT g.cplo_village_code AS village_code, g.id AS asset_id,
               _utf8mb4'gym' COLLATE utf8mb4_general_ci AS asset_type
        FROM sfc_live_test.rad_gym_form_tbl g
        JOIN (
            SELECT gds.villageId FROM gp_data_sfc gds
            WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}
        ) pv ON pv.villageId = g.cplo_village_code
        WHERE g.cplo_user_id IS NOT NULL
          AND g.id IS NOT NULL
          AND g.is_gym_available = 1
          AND LOWER(TRIM(COALESCE(g.gs_approved_status, ''))) <> 'rejected'
          AND LOWER(TRIM(COALESCE(g.it_approved_status, ''))) <> 'rejected'
    ) e
        ON e.village_code = r.village_code
       AND e.asset_id = r.asset_id
       AND e.asset_type = CONVERT(r.asset_type USING utf8mb4) COLLATE utf8mb4_general_ci
    WHERE 1 = 1 {{V:r.village_code}}
    GROUP BY r.village_code
) rk
    ON rk.village_code = gds.villageId

WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}

ORDER BY
    gds.district_name,
    gds.block_name,
    gds.VillageName
