{{ config(
  materialized='incremental',
  unique_key=['date_seance', 'legislature'],
  incremental_strategy='insert_overwrite',
  partition_by={"field": "date_seance", "data_type": "date"},
  cluster_by=['legislature']
) }}

with interventions as (
    select *
    from {{ ref('int_interventions_enriched') }}
    {% if is_incremental() %}
    where date_seance >= date_sub(
      coalesce((select max(date_seance) from {{ this }}), date('1900-01-01')),
      interval 2 day
    )
    {% endif %}
)

select
  date_seance,
  legislature,
  count(distinct intervention_id) as nb_interventions,
  count(distinct depute_uid) as nb_orateurs,
  count(distinct compte_rendu_uid) as nb_comptes_rendus
from interventions
where date_seance is not null
group by date_seance, legislature
