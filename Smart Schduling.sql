-- Part 5 in the quickstart
-- https://quickstarts.snowflake.com/guide/dbt-projects-on-snowflake/index.html?index=..%2F..index#4

USE WAREHOUSE tasty_bytes_dbt_wh;
USE ROLE accountadmin;

CREATE OR REPLACE TASK tasty_bytes_dbt_db.raw.dbt_run_task
	WAREHOUSE=TASTY_BYTES_DBT_WH
	SCHEDULE='60 MINUTES'
	AS EXECUTE DBT PROJECT "TASTY_BYTES_DBT_DB"."RAW"."DBT_PROJECT" args='run --target dev';


CREATE OR REPLACE TASK tasty_bytes_dbt_db.raw.dbt_test_task
	WAREHOUSE=TASTY_BYTES_DBT_WH
	AFTER tasty_bytes_dbt_db.raw.dbt_run_task
	AS
        DECLARE 
            dbt_success BOOLEAN;
            dbt_exception STRING;
            my_exception EXCEPTION (-20002, 'My exception text');
        BEGIN
            EXECUTE DBT PROJECT "TASTY_BYTES_DBT_DB"."RAW"."DBT_PROJECT" args='test --target dev';
            SELECT SUCCESS, EXCEPTION into :dbt_success, :dbt_exception FROM TABLE(result_scan(last_query_id()));
            IF (NOT :dbt_success) THEN
              raise my_exception;
            END IF;
        END;

-- Run the tasks once
ALTER TASK tasty_bytes_dbt_db.raw.dbt_test_task RESUME;
EXECUTE TASK tasty_bytes_dbt_db.raw.dbt_run_task;

-- Optionally create alerts from the task
-- NOTE: you must validate your email and replace it at the bottom of the alert
create or replace alert tasty_bytes_dbt_db.raw.dbt_alert
--- no warehouse selected to run serverless
schedule='60 MINUTES'          
if (exists (
    SELECT 
        NAME,
        SCHEMA_NAME
    FROM 
        TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
            SCHEDULED_TIME_RANGE_START => (greatest(timeadd('DAY', -7, current_timestamp),  SNOWFLAKE.ALERT.LAST_SUCCESSFUL_SCHEDULED_TIME())),
            SCHEDULED_TIME_RANGE_END => SNOWFLAKE.ALERT.SCHEDULED_TIME(),
            ERROR_ONLY => True)) 
    WHERE database_name = 'TASTY_BYTES_DBT_DB'
        )
    ) 
THEN          
    BEGIN
        LET TASK_NAMES string := (
            SELECT
                LISTAGG(DISTINCT(SCHEMA_NAME||'.'||NAME),', ') as FAILED_TASKS
            FROM 
                TABLE(RESULT_SCAN(SNOWFLAKE.ALERT.GET_CONDITION_QUERY_UUID()))); -- results of the condition query above
        CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
            SNOWFLAKE.NOTIFICATION.TEXT_HTML(
                'Tasks '||:TASK_NAMES ||' failed since '||(greatest(timeadd('DAY', -7, current_timestamp), SNOWFLAKE.ALERT.LAST_SUCCESSFUL_SCHEDULED_TIME())
                    )
                ),
            SNOWFLAKE.NOTIFICATION.EMAIL_INTEGRATION_CONFIG(
                'DEMO_EMAIL_NOTIFICATIONS_DBT',                       -- email integration
                'Snowflake DEMO Pipeline Alert',                      -- email header
                array_construct('<YOUR EMAIL HERE>')      -- validated user email addresses
                )      
        );
    END;
;

-- Execute once
EXECUTE ALERT tasty_bytes_dbt_db.raw.dbt_alert;