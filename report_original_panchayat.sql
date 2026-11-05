SELECT
    gds.district_name AS District,
    gds.block_name AS Block_name,
    gds.VillageName AS panchayat_name,
    gds.villageId AS PanchayatId,

    CASE
    WHEN survey.cplo_village_code IS NOT NULL THEN 'Yes' ELSE 'No'
	END AS `Survey Started (Yes/No)`,

    COALESCE(cd.total_assets, 0)
        AS `Total assets uploaded`,

    COALESCE(cd.all_building_assets, 0)
        AS `All_Building_assets`,

    COALESCE(cd.street_assets, 0)
        AS `Street_assets`,

    COALESCE(cd.other_assets, 0)
        AS `Other_assets`,

    COALESCE(cd.All_assets_for_ranking, 0)
        AS `All_assets_for_ranking (Building & Other_Assets)`,

--      Now pulls only assets that are active (Status = 1) and ranked by GS
--     COALESCE(rk.GS_ranked_available_only, 0) AS `aseet ranked by gs`,
    
    COALESCE(rk.GS_ranked, 0)
        AS `Assets Ranked by GS`,

    COALESCE(rk.Bdpo_ranked, 0)
        AS `Assets Ranked by BDPO`,

    COALESCE(cd.All_assets_for_ranking, 0)
        - COALESCE(rk.GS_ranked, 0)
        AS `Pending assets for Ranking by Gram sachiv`,

    COALESCE(rk.building_ranked, 0)
        AS `Building ranked`,

    COALESCE(rk.other_asset_ranked, 0)
        AS `Other asset ranked`,

    COALESCE(rk.excellent_iconic, 0)
        AS `Excellent/Iconic GS`,

    COALESCE(rk.excellent_iconic_bdpo, 0)
        AS `Excellent/Iconic Bdpo`

FROM gp_data_sfc gds

/* Uploaded assets: each source table is scanned once here */
LEFT JOIN
(
    SELECT
        a.cplo_village_code,

        COUNT(DISTINCT CONCAT(
            a.asset_type, '-', a.asset_id
        )) AS total_assets,

        COUNT(DISTINCT CASE
            WHEN a.asset_type IN ('Building', 'Library', 'Gym')
            THEN CONCAT(a.asset_type, '-', a.asset_id)
        END) AS all_building_assets,

        COUNT(DISTINCT CASE
            WHEN a.asset_type = 'Street'
            THEN a.asset_id
        END) AS street_assets,

        COUNT(DISTINCT CASE
            WHEN a.asset_type = 'Other Asset'
            THEN a.asset_id
        END) AS other_assets,

        COUNT(DISTINCT CASE
            WHEN a.asset_type IN (
                'Building', 'Library', 'Gym', 'Other Asset'
            )
            THEN CONCAT(a.asset_type, '-', a.asset_id)
        END) AS All_assets_for_ranking
        
--         Fixed: tracking rows matching the positive availability status flag
--         SUM(CASE WHEN a.Asset_available_status = 1 THEN 1 ELSE 0 END) AS active_assets_count

    FROM
    (
        SELECT
            b.cplo_village_code,
            'Building' AS asset_type,
            b.buid_id AS asset_id -- , b.is_shop_available AS Asset_available_status
        FROM sfc_live_test.rad_building_form_tbl b
        WHERE b.cplo_user_id IS NOT NULL
          AND LOWER(TRIM(CONVERT(
              COALESCE(b.gs_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND LOWER(TRIM(CONVERT(
              COALESCE(b.it_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND (
		    b.aracm_id <> 15
		    OR (
		        b.aracm_id = 15
		        AND b.is_shop_available = 1
		    ))

		    UNION ALL
 
        SELECT DISTINCT
            s.cplo_village_code, 'Street' AS asset_type, s.st_id AS asset_id
        
        FROM sfc_live_test.rad_street_form_tbl s
        WHERE s.cplo_user_id IS NOT NULL
        
        UNION ALL

        SELECT
            oa.cplo_village_code,
            'Other Asset',
            oa.oth_id -- , oa.oth_avail_stat AS Asset_available_status
        FROM sfc_live_test.rad_other_assets_form_tbl oa
        WHERE oa.cplo_user_id IS NOT NULL
          AND LOWER(TRIM(CONVERT(
              COALESCE(oa.gs_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND LOWER(TRIM(CONVERT(
              COALESCE(oa.it_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND oa.oth_avail_stat = 1
          AND oa.oth_asset_id IN (14, 15, 16, 17, 18, 19)
          
--           SELECT
-- 			    CAST(TRIM(oa.cplo_village_code) AS UNSIGNED) AS cplo_village_code,
-- 			    'Other Asset' AS asset_type,
-- 			    oa.oth_id AS asset_id
-- 			FROM sfc_live_test.rad_other_assets_form_tbl oa
-- 			WHERE oa.cplo_user_id IS NOT NULL
-- 			  AND TRIM(oa.cplo_village_code) REGEXP '^[0-9]+$'
-- 			  AND LOWER(TRIM(CONVERT(
-- 			      COALESCE(oa.gs_approved_status, '') USING utf8mb4
-- 			  ))) COLLATE utf8mb4_general_ci <> 'rejected'
-- 			  AND LOWER(TRIM(CONVERT(
-- 			      COALESCE(oa.it_approved_status, '') USING utf8mb4
-- 			  ))) COLLATE utf8mb4_general_ci <> 'rejected'
-- 			  AND oa.oth_avail_stat = 1
-- 			  AND oa.oth_asset_id IN (14, 15, 16, 17, 18, 19)

        UNION ALL

        SELECT
            l.cplo_village_code,
            'Library',
            l.id -- , l.is_library_available as Asset_available_status
        FROM sfc_live_test.rad_library_form_tbl l
        WHERE l.cplo_user_id IS NOT NULL
          AND LOWER(TRIM(CONVERT(
              COALESCE(l.gs_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND LOWER(TRIM(CONVERT(
              COALESCE(l.it_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND l.is_library_available = 1

        UNION ALL

        SELECT
            gm.cplo_village_code,
            'Gym', gm.id -- , gm.is_gym_available as Asset_available_status
        FROM sfc_live_test.rad_gym_form_tbl gm
        WHERE gm.cplo_user_id IS NOT NULL
          AND LOWER(TRIM(CONVERT(
              COALESCE(gm.gs_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND LOWER(TRIM(CONVERT(
              COALESCE(gm.it_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND gm.is_gym_available = 1

    ) a
    GROUP BY a.cplo_village_code

	) cd
	    ON cd.cplo_village_code = gds.villageId

LEFT JOIN
	(
    SELECT DISTINCT cplo_village_code
    FROM
    (
        SELECT cplo_village_code
        FROM sfc_live_test.rad_building_form_tbl
        WHERE cplo_user_id IS NOT NULL

        UNION ALL

        SELECT cplo_village_code
        FROM sfc_live_test.rad_other_assets_form_tbl
        WHERE cplo_user_id IS NOT NULL
          AND oth_avail_stat = 1

        UNION ALL

        SELECT cplo_village_code
        FROM sfc_live_test.rad_library_form_tbl
        WHERE cplo_user_id IS NOT NULL
          AND is_library_available = 1

        UNION ALL

        SELECT cplo_village_code
        FROM sfc_live_test.rad_gym_form_tbl
        WHERE cplo_user_id IS NOT NULL
          AND is_gym_available = 1
    ) uploaded_assets
) survey
    ON survey.cplo_village_code = gds.villageId
    
/* Ranking totals, filtered against eligible source assets */
LEFT JOIN
(
    SELECT
        r.village_code,

        COUNT(DISTINCT CASE
            WHEN r.gs_rank IS NOT NULL
            THEN CONCAT(r.asset_type, '-', r.asset_id)
        END) AS GS_ranked,

--         New Condition: Count only if gs_rank is present AND Asset_available_status = 1
--         COUNT(DISTINCT CASE 
--             WHEN r.gs_rank IS NOT NULL AND src.Asset_available_status = 1 
--             THEN CONCAT(r.asset_type, '-', r.asset_id) 
--         END) AS GS_ranked_available_only,
        
        COUNT(DISTINCT CASE
            WHEN r.bdpo_user_id IS NOT NULL
             AND r.bdpo_rank IS NOT NULL
            THEN CONCAT(r.asset_type, '-', r.asset_id)
        END) AS Bdpo_ranked,

        COUNT(DISTINCT CASE
            WHEN LOWER(TRIM(CONVERT(
                r.asset_type USING utf8mb4
            ))) COLLATE utf8mb4_general_ci
                IN ('building', 'library', 'gym')
             AND r.gs_rank IS NOT NULL
            THEN CONCAT(r.asset_type, '-', r.asset_id)
        END) AS building_ranked,

        COUNT(DISTINCT CASE
            WHEN LOWER(TRIM(CONVERT(
                r.asset_type USING utf8mb4
            ))) COLLATE utf8mb4_general_ci = 'other asset'
             AND r.gs_rank IS NOT NULL
            THEN CONCAT(r.asset_type, '-', r.asset_id)
        END) AS other_asset_ranked,

        COUNT(DISTINCT CASE
            WHEN r.sub_category_id NOT IN (14, 15, 21)
             AND CONVERT(r.gs_rank USING utf8mb4)
                 COLLATE utf8mb4_general_ci = _utf8mb4'Excellent/Iconic'
            THEN CONCAT(r.asset_type, '-', r.asset_id)
        END) AS excellent_iconic,

        COUNT(DISTINCT CASE
            WHEN r.sub_category_id NOT IN (14, 15, 21)
             AND r.bdpo_user_id IS NOT NULL
             AND CONVERT(r.bdpo_rank USING utf8mb4)
                 COLLATE utf8mb4_general_ci = _utf8mb4'Excellent/Iconic'
            THEN CONCAT(r.asset_type, '-', r.asset_id)
        END) AS excellent_iconic_bdpo

    FROM rad_asset_ranking_tbl r
    
    WHERE EXISTS
    (
        SELECT 1
        FROM sfc_live_test.rad_building_form_tbl b
        WHERE b.cplo_village_code = r.village_code
          AND b.buid_id = r.asset_id
          AND CONVERT(r.asset_type USING utf8mb4)
              COLLATE utf8mb4_general_ci = _utf8mb4'Building'
          AND b.cplo_user_id IS NOT NULL
          AND LOWER(TRIM(CONVERT(
              COALESCE(b.gs_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND LOWER(TRIM(CONVERT(
              COALESCE(b.it_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          -- Apply the same shop availability rule as the uploaded assets
	      AND (
	          b.aracm_id <> 15
	          OR (
	              b.aracm_id = 15
	              AND b.is_shop_available = 1
	          ))
    )

    OR EXISTS
    (
        SELECT 1
        FROM sfc_live_test.rad_other_assets_form_tbl oa
        WHERE oa.cplo_village_code = r.village_code
          AND oa.oth_id = r.asset_id
          AND CONVERT(r.asset_type USING utf8mb4)
              COLLATE utf8mb4_general_ci = _utf8mb4'Other Asset'
          AND oa.cplo_user_id IS NOT NULL
          AND oa.oth_avail_stat = 1
          AND oa.oth_asset_id IN (14, 15, 16, 17, 18, 19)
          AND LOWER(TRIM(CONVERT(
              COALESCE(oa.gs_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND LOWER(TRIM(CONVERT(
              COALESCE(oa.it_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
    )

    OR EXISTS
    (
        SELECT 1
        FROM sfc_live_test.rad_library_form_tbl l
        WHERE l.cplo_village_code = r.village_code
          AND l.id = r.asset_id
          AND CONVERT(r.asset_type USING utf8mb4)
              COLLATE utf8mb4_general_ci = _utf8mb4'Library'
          AND l.cplo_user_id IS NOT NULL
          AND l.is_library_available = 1
          AND LOWER(TRIM(CONVERT(
              COALESCE(l.gs_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND LOWER(TRIM(CONVERT(
              COALESCE(l.it_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
    )

    OR EXISTS
    (
        SELECT 1
        FROM sfc_live_test.rad_gym_form_tbl gm
        WHERE gm.cplo_village_code = r.village_code
          AND gm.id = r.asset_id
          AND CONVERT(r.asset_type USING utf8mb4)
              COLLATE utf8mb4_general_ci = _utf8mb4'Gym'
          AND gm.cplo_user_id IS NOT NULL
          AND gm.is_gym_available = 1
          AND LOWER(TRIM(CONVERT(
              COALESCE(gm.gs_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
          AND LOWER(TRIM(CONVERT(
              COALESCE(gm.it_approved_status, '') USING utf8mb4
          ))) COLLATE utf8mb4_general_ci <> 'rejected'
    )

    GROUP BY r.village_code

) rk
    ON rk.village_code = gds.villageId

WHERE gds.villageId NOT IN (299841)

ORDER BY
    gds.district_name,
    gds.block_name,
    gds.VillageName;