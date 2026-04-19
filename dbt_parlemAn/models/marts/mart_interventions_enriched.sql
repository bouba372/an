{{ config(
  materialized='incremental',
  unique_key='intervention_id',
  incremental_strategy='merge',
  partition_by={"field": "date_seance", "data_type": "date"},
  cluster_by=['depute_uid', 'legislature']
) }}

select
  intervention_id,
  compte_rendu_uid,
  point_id,
  point_valeur_ptsodj,
  date_seance,
  legislature,
  session,
  num_seance,
  roledebat,
  depute_uid,
  orateur_nom,
  trigramme,
  profession_categorie,
  profession_famille,
  texte
from {{ ref('int_interventions_enriched') }}
{% if is_incremental() %}
where date_seance >= date_sub(
  coalesce((select max(date_seance) from {{ this }}), date('1900-01-01')),
  interval 2 day
)
{% endif %}
