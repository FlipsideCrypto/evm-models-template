DBT_TARGET ?= dev

deploy_streamline_functions:
	rm -f package-lock.yml && dbt clean && dbt deps
	dbt run -s livequery_models.deploy.core --vars '{"UPDATE_UDFS_AND_SPS":True}' -t $(DBT_TARGET)
	dbt run-operation fsc_evm.create_evm_streamline_udfs --vars '{"UPDATE_UDFS_AND_SPS":True}' -t $(DBT_TARGET)

cleanup_time:
	rm -f package-lock.yml && dbt clean && dbt deps

deploy_streamline_tables:
	rm -f package-lock.yml && dbt clean && dbt deps
ifeq ($(findstring dev,$(DBT_TARGET)),dev)
	dbt run -m "fsc_evm,tag:bronze_external" --vars '{"STREAMLINE_USE_DEV_FOR_EXTERNAL_TABLES":True}' -t $(DBT_TARGET)
else
	dbt run -m "fsc_evm,tag:bronze_external" -t $(DBT_TARGET)
endif
	dbt run -m "fsc_evm,tag:streamline_core_complete" "fsc_evm,tag:streamline_core_realtime" "fsc_evm,tag:utils" --full-refresh -t $(DBT_TARGET)

deploy_streamline_requests:
	rm -f package-lock.yml && dbt clean && dbt deps
	dbt run -m "fsc_evm,tag:streamline_core_complete" "fsc_evm,tag:streamline_core_realtime" --vars '{"STREAMLINE_INVOKE_STREAMS":True}' -t $(DBT_TARGET)

deploy_github_actions:
	dbt run -s livequery_models.deploy.marketplace.github --vars '{"UPDATE_UDFS_AND_SPS":True}' -t $(DBT_TARGET)
	dbt run -m "fsc_evm,tag:gha_tasks" --full-refresh -t $(DBT_TARGET)
ifeq ($(findstring dev,$(DBT_TARGET)),dev)
	dbt run-operation fsc_evm.create_gha_tasks --vars '{"START_GHA_TASKS":False}' -t $(DBT_TARGET)
else
	dbt run-operation fsc_evm.create_gha_tasks --vars '{"START_GHA_TASKS":True}' -t $(DBT_TARGET)
endif

deploy_new_github_action:
	dbt run-operation fsc_evm.drop_github_actions_schema -t $(DBT_TARGET)
	dbt run -m "fsc_evm,tag:gha_tasks" --full-refresh -t $(DBT_TARGET)
	dbt run-operation fsc_evm.create_gha_tasks --vars '{"START_GHA_TASKS": false}' -t $(DBT_TARGET)

release_main_package:
	dbt run-operation fsc_evm.release_chain --args '{"schema_name": "core", "role_name": "internal_dev"}' -t $(DBT_TARGET)
	dbt run-operation fsc_evm.release_chain --args '{"schema_name": "price", "role_name": "internal_dev"}' -t $(DBT_TARGET)
	dbt run-operation fsc_evm.release_chain --args '{"schema_name": "nft", "role_name": "internal_dev"}' -t $(DBT_TARGET)
	dbt run-operation fsc_evm.release_chain --args '{"schema_name": "core", "role_name": "velocity_ethereum"}' -t $(DBT_TARGET)
	dbt run-operation fsc_evm.release_chain --args '{"schema_name": "price", "role_name": "velocity_ethereum"}' -t $(DBT_TARGET)
	dbt run-operation fsc_evm.release_chain --args '{"schema_name": "nft", "role_name": "velocity_ethereum"}' -t $(DBT_TARGET)

deploy_chain_phase_1:
	dbt run -m livequery_models.deploy.core --vars '{UPDATE_UDFS_AND_SPS: true}' -t $(DBT_TARGET)
	dbt run-operation fsc_evm.livequery_grants -t $(DBT_TARGET)
	dbt run-operation fsc_evm.create_evm_streamline_udfs --vars '{UPDATE_UDFS_AND_SPS: true}' -t $(DBT_TARGET)
    dbt run -m "fsc_evm,tag:phase_1" --full-refresh --vars '{"GLOBAL_STREAMLINE_FR_ENABLED": true}' -t $(DBT_TARGET)
	# kick chainhead workflow
	# wait ~10 minutes
	# run deploy_chain_phase_2

deploy_chain_phase_2:
    dbt run -m "fsc_evm,tag:phase_2" --full-refresh --vars '{"GLOBAL_STREAMLINE_FR_ENABLED": true, "GLOBAL_BRONZE_FR_ENABLED": true, "GLOBAL_SILVER_FR_ENABLED": true, "GLOBAL_GOLD_FR_ENABLED": true}' -t $(DBT_TARGET)
	make deploy_github_actions -t $(DBT_TARGET)
	# tasks set to SUSPEND by default
	# kick alter_gha_task workflow to RESUME individual tasks, as needed

deploy_chain_phase_3:
    dbt run -m "fsc_evm,tag:phase_3" --full-refresh --vars '{"GLOBAL_BRONZE_FR_ENABLED": true, "GLOBAL_SILVER_FR_ENABLED": true, "GLOBAL_GOLD_FR_ENABLED": true}' -t $(DBT_TARGET)
	# kick alter_gha_task workflow to RESUME individual tasks, as needed
	
.PHONY: deploy_streamline_functions deploy_streamline_tables deploy_streamline_requests deploy_github_actions cleanup_time deploy_new_github_action release_main_package