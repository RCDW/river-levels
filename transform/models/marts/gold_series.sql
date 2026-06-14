{{ config(materialized='table') }}

-- GOLD: the plotted chart series for the visible window. Retains reading_id so
-- a clicked point on the chart resolves straight back to silver and bronze.

select
    s.reading_id,
    s.station_reference,
    s.station_label,
    s.parameter,
    s.qualifier,
    s.date_time_utc,
    s.value,
    s.unit_name
from {{ ref('stg_river_readings') }} s
where s.parameter = 'level'
  and s.qualifier = 'Stage'
  and s.quality_flag = 'ok'
  and s.date_time_utc >= current_timestamp - interval 30 day
order by s.station_reference, s.date_time_utc
