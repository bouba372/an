{{ config(
  materialized='incremental',
  unique_key='scrutin_uid',
  incremental_strategy='merge',
  partition_by={"field": "date_scrutin", "data_type": "date"},
  cluster_by=['legislature', 'organe_ref']
) }}

select
  uid as scrutin_uid,
  numero,
  legislature,
  organe_ref,
  session_ref,
  seance_ref,
  date_scrutin,
  quantieme_jour_seance,
  type_vote_code,
  type_vote_libelle,
  type_majorite,
  sort_code,
  sort_libelle,
  titre,
  demandeur_texte,
  demandeur_reference_legislative,
  objet_libelle,
  objet_dossier_legislatif,
  objet_reference_legislative,
  mode_publication_votes,
  lieu_vote,
  synthese_nombre_votants,
  synthese_suffrages_exprimes,
  synthese_nbr_suffrages_requis,
  synthese_annonce,
  synthese_non_votants,
  synthese_pour,
  synthese_contre,
  synthese_abstentions,
  synthese_non_votants_volontaires
from {{ source('raw_parleman', 'scrutins') }}
{% if is_incremental() %}
where date_scrutin >= date_sub(
  coalesce((select max(date_scrutin) from {{ this }}), date('1900-01-01')),
  interval 2 day
)
{% endif %}