-- Ask your DBA to run these (a read-only user cannot). They speed up the report query.
-- Check column names first and skip any index that already exists.

CREATE INDEX idx_bld_vil  ON sfc_live_test.rad_building_form_tbl     (cplo_village_code, cplo_user_id, buid_id);
CREATE INDEX idx_str_vil  ON sfc_live_test.rad_street_form_tbl       (cplo_village_code, cplo_user_id, st_id);
CREATE INDEX idx_oth_vil  ON sfc_live_test.rad_other_assets_form_tbl (cplo_village_code, cplo_user_id, oth_id);
CREATE INDEX idx_lib_vil  ON sfc_live_test.rad_library_form_tbl      (cplo_village_code, cplo_user_id, id);
CREATE INDEX idx_gym_vil  ON sfc_live_test.rad_gym_form_tbl          (cplo_village_code, cplo_user_id, id);
CREATE INDEX idx_rank_vil ON rad_asset_ranking_tbl (village_code, asset_id);
CREATE INDEX idx_gp_vil   ON gp_data_sfc (villageId);
CREATE INDEX idx_gp_geo   ON gp_data_sfc (district_name, block_name, VillageName, villageId);  -- speeds up the 25-row page lookup
