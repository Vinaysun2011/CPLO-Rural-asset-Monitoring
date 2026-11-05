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

LEFT JOIN
(
    SELECT
        cplo_village_code,

        COUNT(DISTINCT CONCAT(asset_type, '-', asset_id)) AS total_assets,
        COUNT(DISTINCT CASE
                WHEN asset_type IN ('Building', 'Library', 'Gym', 'Other Asset') THEN CONCAT(asset_type, '-', asset_id)
            END) AS All_assets_for_ranking,
        COUNT(DISTINCT CASE
                WHEN asset_type IN ('Building', 'Library', 'Gym') THEN CONCAT(asset_type, '-', asset_id)
            END) AS all_building_assets,
        COUNT(DISTINCT CASE WHEN asset_type = 'Street' THEN asset_id END) AS street_assets,
        COUNT(DISTINCT CASE WHEN asset_type = 'Other Asset' THEN asset_id END) AS other_assets

    FROM
    (
        SELECT DISTINCT
            b.cplo_village_code, 'Building' AS asset_type, b.buid_id AS asset_id
        FROM sfc_live_test.rad_building_form_tbl b
        WHERE b.cplo_user_id IS NOT NULL

        UNION ALL

        SELECT DISTINCT
            s.cplo_village_code, 'Street' AS asset_type, s.st_id AS asset_id
        FROM sfc_live_test.rad_street_form_tbl s
        WHERE s.cplo_user_id IS NOT NULL

        UNION ALL

        SELECT DISTINCT
            oa.cplo_village_code, 'Other Asset' AS asset_type,
            CASE WHEN oa.oth_avail_stat = 1 AND oa.oth_asset_id IN (14,15,16,17,18,19) THEN oa.oth_id END AS asset_id
        FROM sfc_live_test.rad_other_assets_form_tbl oa
        WHERE oa.cplo_user_id IS NOT NULL
          AND oa.oth_avail_stat = 1

        UNION ALL

        SELECT DISTINCT
            rlft.cplo_village_code, 'Library' AS asset_type,
            CASE WHEN rlft.is_library_available = 1 THEN rlft.id END AS asset_id
        FROM sfc_live_test.rad_library_form_tbl rlft
        WHERE rlft.cplo_user_id IS NOT NULL
          AND rlft.is_library_available = 1

        UNION ALL

        SELECT DISTINCT
            rgft.cplo_village_code, 'Gym' AS asset_type,
            CASE WHEN rgft.is_gym_available = 1 THEN rgft.id END AS asset_id
        FROM sfc_live_test.rad_gym_form_tbl rgft
        WHERE rgft.cplo_user_id IS NOT NULL
          AND rgft.is_gym_available = 1
    ) assets
    GROUP BY cplo_village_code
) cd
    ON cd.cplo_village_code = gds.villageId

/* RANKING COUNTS - VILLAGE WISE */
LEFT JOIN
(
    SELECT
        village_code,
        COUNT(CASE WHEN gs_rank IS NOT NULL THEN gs_rank END) AS GS_ranked,
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
