/* The {{V:column}} markers are filled in by app.py. For one page of results they become
   "AND column IN (<the 25 villages of that page>)", so every table is read only for those
   villages (this is what makes the page fast and lets the indexes work). For the full
   report (Excel / grand total) they become empty. Do not remove them. */
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

/* ---------------------------------------------------------------------------
   UPLOADED ASSETS + "SURVEY STARTED" FLAG
   Each source table is read ONCE and counted per village on its own id column.
   The small per-village counts are then added up. No string building (CONCAT)
   and no DISTINCT over strings, which was the slowest part of the old query.
   --------------------------------------------------------------------------- */
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
        /* Building */
        SELECT cplo_village_code, 1 AS surveyed,
               COUNT(DISTINCT CASE
                   WHEN LOWER(TRIM(COALESCE(gs_approved_status, ''))) <> 'rejected'
                    AND LOWER(TRIM(COALESCE(it_approved_status, ''))) <> 'rejected'
                    AND (aracm_id <> 15 OR (aracm_id = 15 AND is_shop_available = 1))
                   THEN buid_id END) AS b,
               0 AS s, 0 AS o, 0 AS l, 0 AS g
        FROM sfc_live_test.rad_building_form_tbl
        WHERE cplo_user_id IS NOT NULL {{V:cplo_village_code}}
        GROUP BY cplo_village_code

        UNION ALL

        /* Street (no approval rules, not counted for "survey started") */
        SELECT cplo_village_code, 0, 0, COUNT(DISTINCT st_id), 0, 0, 0
        FROM sfc_live_test.rad_street_form_tbl
        WHERE cplo_user_id IS NOT NULL {{V:cplo_village_code}}
        GROUP BY cplo_village_code

        UNION ALL

        /* Other assets */
        SELECT cplo_village_code, 1, 0, 0,
               COUNT(DISTINCT CASE
                   WHEN LOWER(TRIM(COALESCE(gs_approved_status, ''))) <> 'rejected'
                    AND LOWER(TRIM(COALESCE(it_approved_status, ''))) <> 'rejected'
                    AND oth_asset_id IN (14, 15, 16, 17, 18, 19)
                   THEN oth_id END),
               0, 0
        FROM sfc_live_test.rad_other_assets_form_tbl
        WHERE cplo_user_id IS NOT NULL {{V:cplo_village_code}} AND oth_avail_stat = 1
        GROUP BY cplo_village_code

        UNION ALL

        /* Library */
        SELECT cplo_village_code, 1, 0, 0, 0,
               COUNT(DISTINCT CASE
                   WHEN LOWER(TRIM(COALESCE(gs_approved_status, ''))) <> 'rejected'
                    AND LOWER(TRIM(COALESCE(it_approved_status, ''))) <> 'rejected'
                   THEN id END),
               0
        FROM sfc_live_test.rad_library_form_tbl
        WHERE cplo_user_id IS NOT NULL {{V:cplo_village_code}} AND is_library_available = 1
        GROUP BY cplo_village_code

        UNION ALL

        /* Gym */
        SELECT cplo_village_code, 1, 0, 0, 0, 0,
               COUNT(DISTINCT CASE
                   WHEN LOWER(TRIM(COALESCE(gs_approved_status, ''))) <> 'rejected'
                    AND LOWER(TRIM(COALESCE(it_approved_status, ''))) <> 'rejected'
                   THEN id END)
        FROM sfc_live_test.rad_gym_form_tbl
        WHERE cplo_user_id IS NOT NULL {{V:cplo_village_code}} AND is_gym_available = 1
        GROUP BY cplo_village_code
    ) x
    GROUP BY cplo_village_code
) cd
    ON cd.cplo_village_code = gds.villageId

/* ---------------------------------------------------------------------------
   RANKING TOTALS - only for assets that are eligible (same rules as above).
   The old query ran four correlated EXISTS checks for every ranking row.
   Now the eligible assets are listed once (de-duplicated) and joined.
   --------------------------------------------------------------------------- */
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
        SELECT DISTINCT cplo_village_code, buid_id AS asset_id,
               _utf8mb4'building' COLLATE utf8mb4_general_ci AS asset_type
        FROM sfc_live_test.rad_building_form_tbl
        WHERE cplo_user_id IS NOT NULL {{V:cplo_village_code}}
          AND buid_id IS NOT NULL
          AND LOWER(TRIM(COALESCE(gs_approved_status, ''))) <> 'rejected'
          AND LOWER(TRIM(COALESCE(it_approved_status, ''))) <> 'rejected'
          AND (aracm_id <> 15 OR (aracm_id = 15 AND is_shop_available = 1))

        UNION ALL

        SELECT DISTINCT cplo_village_code, oth_id,
               _utf8mb4'other asset' COLLATE utf8mb4_general_ci
        FROM sfc_live_test.rad_other_assets_form_tbl
        WHERE cplo_user_id IS NOT NULL {{V:cplo_village_code}}
          AND oth_id IS NOT NULL
          AND oth_avail_stat = 1
          AND oth_asset_id IN (14, 15, 16, 17, 18, 19)
          AND LOWER(TRIM(COALESCE(gs_approved_status, ''))) <> 'rejected'
          AND LOWER(TRIM(COALESCE(it_approved_status, ''))) <> 'rejected'

        UNION ALL

        SELECT DISTINCT cplo_village_code, id,
               _utf8mb4'library' COLLATE utf8mb4_general_ci
        FROM sfc_live_test.rad_library_form_tbl
        WHERE cplo_user_id IS NOT NULL {{V:cplo_village_code}}
          AND id IS NOT NULL
          AND is_library_available = 1
          AND LOWER(TRIM(COALESCE(gs_approved_status, ''))) <> 'rejected'
          AND LOWER(TRIM(COALESCE(it_approved_status, ''))) <> 'rejected'

        UNION ALL

        SELECT DISTINCT cplo_village_code, id,
               _utf8mb4'gym' COLLATE utf8mb4_general_ci
        FROM sfc_live_test.rad_gym_form_tbl
        WHERE cplo_user_id IS NOT NULL {{V:cplo_village_code}}
          AND id IS NOT NULL
          AND is_gym_available = 1
          AND LOWER(TRIM(COALESCE(gs_approved_status, ''))) <> 'rejected'
          AND LOWER(TRIM(COALESCE(it_approved_status, ''))) <> 'rejected'
    ) e
        ON  e.cplo_village_code = r.village_code
        AND e.asset_id          = r.asset_id
        AND e.asset_type        = CONVERT(r.asset_type USING utf8mb4) COLLATE utf8mb4_general_ci

    WHERE 1 = 1 {{V:r.village_code}}
    GROUP BY r.village_code
) rk
    ON rk.village_code = gds.villageId

WHERE gds.villageId NOT IN (299841) {{V:gds.villageId}}

ORDER BY
    gds.district_name,
    gds.block_name,
    gds.VillageName
