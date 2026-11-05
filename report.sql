SELECT
    gds.district_name AS District,

    COUNT(DISTINCT gds.villageId) AS Total_panchayats,

    COUNT(DISTINCT gds.villageId)
    -
    COUNT(DISTINCT CASE WHEN cd.cplo_village_code IS NOT NULL THEN gds.villageId END) AS `GPs_who_Not_Uploaded_any_assets`,

    CONCAT(
        ROUND(
            COUNT(DISTINCT CASE WHEN cd.cplo_village_code IS NOT NULL THEN gds.villageId END)
            / NULLIF(COUNT(DISTINCT gds.villageId), 0) * 100, 1), '%') AS `%age of GPs`,

    SUM(COALESCE(cd.total_assets, 0)) AS `Total assets uploaded`,
    SUM(COALESCE(cd.all_building_assets, 0)) AS `All_Building_assets`,
    SUM(COALESCE(cd.street_assets, 0)) AS `Street_assets`,
    SUM(COALESCE(cd.other_assets, 0)) AS `Other_assets`,
    SUM(COALESCE(cd.All_assets_for_ranking, 0)) AS `All_assets_for_ranking (Building & Other_Assets)`,

    SUM(COALESCE(rk.GS_ranked, 0)) AS `Assets Ranked by GS`,
    SUM(COALESCE(rk.Bdpo_ranked, 0)) AS `Assets Ranked by BDPO`,

    SUM(COALESCE(cd.All_assets_for_ranking, 0))
    -
    SUM(COALESCE(rk.GS_ranked, 0)) AS `Pending assets for Ranking by Gram sachiv`,

    SUM(COALESCE(rk.building_ranked, 0)) AS `Building ranked`,
    SUM(COALESCE(rk.other_asset_ranked, 0)) AS `Other asset ranked`,

    SUM(COALESCE(rk.excellent_iconic, 0)) AS `Excellent/Iconic GS`,
    SUM(COALESCE(rk.excellent_iconic_bdpo, 0)) AS `Excellent/Iconic Bdpo`

FROM gp_data_sfc gds

/* ASSETS UPLOADED - each table is counted once per village, then the
   small per-village counts are added up (no DISTINCT over strings, no CONCAT) */
LEFT JOIN
(
    SELECT
        cplo_village_code,
        SUM(b + s + o + l + g) AS total_assets,
        SUM(b + o + l + g)     AS All_assets_for_ranking,
        SUM(b + l + g)         AS all_building_assets,
        SUM(s)                 AS street_assets,
        SUM(o)                 AS other_assets
    FROM
    (
        SELECT cplo_village_code, COUNT(DISTINCT buid_id) AS b, 0 AS s, 0 AS o, 0 AS l, 0 AS g
        FROM sfc_live_test.rad_building_form_tbl
        WHERE cplo_user_id IS NOT NULL
        GROUP BY cplo_village_code

        UNION ALL

        SELECT cplo_village_code, 0, COUNT(DISTINCT st_id), 0, 0, 0
        FROM sfc_live_test.rad_street_form_tbl
        WHERE cplo_user_id IS NOT NULL
        GROUP BY cplo_village_code

        UNION ALL

        SELECT cplo_village_code, 0, 0,
               COUNT(DISTINCT CASE WHEN oth_asset_id IN (14,15,16,17,18,19) THEN oth_id END), 0, 0
        FROM sfc_live_test.rad_other_assets_form_tbl
        WHERE cplo_user_id IS NOT NULL AND oth_avail_stat = 1
        GROUP BY cplo_village_code

        UNION ALL

        SELECT cplo_village_code, 0, 0, 0, COUNT(DISTINCT id), 0
        FROM sfc_live_test.rad_library_form_tbl
        WHERE cplo_user_id IS NOT NULL AND is_library_available = 1
        GROUP BY cplo_village_code

        UNION ALL

        SELECT cplo_village_code, 0, 0, 0, 0, COUNT(DISTINCT id)
        FROM sfc_live_test.rad_gym_form_tbl
        WHERE cplo_user_id IS NOT NULL AND is_gym_available = 1
        GROUP BY cplo_village_code
    ) assets
    GROUP BY cplo_village_code
) cd
    ON cd.cplo_village_code = gds.villageId

/* RANKING COUNTS - VILLAGE WISE */
LEFT JOIN
(
    SELECT
        village_code,
        COUNT(gs_rank) AS GS_ranked,
        COUNT(CASE WHEN gs_rank IS NOT NULL AND bdpo_user_id IS NOT NULL THEN bdpo_rank END) AS Bdpo_ranked,

        COUNT(DISTINCT CASE
                WHEN LOWER(asset_type) IN ('building', 'library', 'gym') AND gs_rank IS NOT NULL
                THEN CONCAT(asset_type, '-', asset_id)
            END) AS building_ranked,

        COUNT(DISTINCT CASE
                WHEN LOWER(asset_type) = 'other asset' AND gs_rank IS NOT NULL
                THEN CONCAT(asset_type, '-', asset_id)
            END) AS other_asset_ranked,

        COUNT(CASE WHEN sub_category_id NOT IN (14,15,21) AND gs_rank = 'Excellent/Iconic' THEN 1 END) AS excellent_iconic,
        COUNT(CASE WHEN sub_category_id NOT IN (14,15,21) AND bdpo_rank = 'Excellent/Iconic' THEN 1 END) AS excellent_iconic_bdpo

    FROM rad_asset_ranking_tbl
    GROUP BY village_code
) rk
    ON rk.village_code = gds.villageId

WHERE gds.villageId NOT IN (299841)

GROUP BY gds.district_name

ORDER BY gds.district_name
