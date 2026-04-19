{{ config(
  materialized='incremental',
  unique_key='acte_uid',
  incremental_strategy='merge',
  partition_by={"field": "date_acte", "data_type": "date"},
  cluster_by=['dossier_uid', 'acte_code']
) }}

select
  dossier_uid,
  acte_uid,
  acte_code,
  acte_libelle_canonique,
  acte_libelle_court,
  organe_ref,
  safe_cast(date_acte as date) as date_acte,
  type_acte,
  texte_associe,
  vote_ref
from {{ source('raw_parleman', 'dossier_actes_legislatifs') }}
{% if is_incremental() %}
where safe_cast(date_acte as date) >= date_sub(
  coalesce((select max(date_acte) from {{ this }}), date('1900-01-01')),
  interval 2 day
)
{% endif %}