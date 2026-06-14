{{ config(materialized='table') }}

-- SILVER: cleaned & validated, one row per reading. Dedupes on reading_id
-- keeping the most recently ingested copy, casts types, normalises, and assigns
-- a quality_flag. reading_id is minted at INGEST (md5(measure|dateTime)) and
-- carried UNCHANGED through bronze -> silver -> gold; we SELECT it here, never
-- regenerate it, so Feature C can trace a point across layers exactly.

with raw as (
    select
        reading_id,
        measure,
        station_reference,
        station_label,
        parameter,
        qualifier,
        unit_name,
        cast(date_time as timestamp) as date_time_utc,
        try_cast(value as double) as value,
        cast(_ingested_at as timestamp) as ingested_at,
        _source_batch_id as source_batch_id
    from {{ source('bronze', 'readings') }}
    where
        measure is not null
        and date_time is not null
),

deduped as (
    select
        *,
        row_number() over (
            partition by reading_id
            order by ingested_at desc
        ) as _rn
    from raw
),

flagged as (
    select
        reading_id,
        measure,
        station_reference,
        station_label,
        parameter,
        qualifier,
        unit_name,
        date_time_utc,
        value,
        case
            when value is null then 'missing'
            when value < -50 or value > 50 then 'out_of_range'  -- mASD/mAOD sanity bound
            else 'ok'
        end as quality_flag,
        ingested_at,
        source_batch_id,
        current_timestamp as silver_built_at
    from deduped
    where _rn = 1
)

select * from flagged
