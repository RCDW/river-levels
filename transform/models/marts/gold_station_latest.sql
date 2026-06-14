{{ config(materialized='table') }}

-- GOLD: one row per station/measure, with latest value, 24h change, and the
-- above_threshold flag (Features A & B). Threshold = configured value, else
-- the station's typicalRangeHigh (level exceeded only ~5% of the time).

with stage as (
    select *
    from {{ ref('stg_river_readings') }}
    where parameter = 'level' and qualifier = 'Stage' and quality_flag = 'ok'
),

latest as (
    select *,
        row_number() over (partition by measure order by date_time_utc desc) as rn
    from stage
),

value_24h_ago as (
    select
        l.measure,
        (
            select s2.value
            from stage s2
            where s2.measure = l.measure
              and s2.date_time_utc <= l.date_time_utc - interval 24 hour
            order by s2.date_time_utc desc
            limit 1
        ) as value_24h_ago
    from latest l
    where l.rn = 1
)

select
    l.reading_id,                         -- trace key of the latest point
    l.station_reference,
    l.station_label,
    l.measure,
    l.unit_name,
    l.date_time_utc                        as latest_at,
    l.value                                as latest_value,
    v.value_24h_ago,
    round(l.value - v.value_24h_ago, 3)    as change_24h,
    coalesce(d.threshold_m, d.typical_range_high) as threshold,
    (l.value > coalesce(d.threshold_m, d.typical_range_high)) as above_threshold
from latest l
left join value_24h_ago v on v.measure = l.measure
left join {{ ref('dim_stations') }} d on d.station_reference = l.station_reference
where l.rn = 1
