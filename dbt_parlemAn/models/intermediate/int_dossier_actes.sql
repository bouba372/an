{{ config(
    materialized='incremental',
    unique_key='dossier_uid',
    incremental_strategy='merge',
    partition_by={"field": "date_dernier_acte", "data_type": "date"},
    cluster_by=['dossier_uid', 'est_adopte']
) }}

with actes as (
    select
        dossier_uid,
        acte_uid,
        date_acte,
        type_acte,
        acte_code
    from {{ ref('stg_dossier_actes_legislatifs') }}
    {% if is_incremental() %}
    where date_acte >= date_sub(
      coalesce((select max(date_dernier_acte) from {{ this }}), date('1900-01-01')),
      interval 2 day
    )
    {% endif %}
)

select
    dossier_uid,
    min(date_acte) as date_premier_acte,
    max(date_acte) as date_dernier_acte,
    count(distinct acte_uid) as nombre_actes_total,
    countif(acte_code like 'PROM%') > 0 as est_adopte
from actes
where dossier_uid is not null
group by 1
