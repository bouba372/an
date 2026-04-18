{{ config(materialized='view') }}

{% set raw_relation = adapter.get_relation(
  database=env_var('GCP_PROJECT'),
  schema=env_var('BQ_DATASET'),
  identifier='amendements'
) %}

{% if raw_relation is none %}
  {{ log('raw_parleman.amendements is missing; stg_amendements will be an empty view for this run.', info=True) }}

select
  cast(null as string) as amendement_uid,
  cast(null as string) as legislature,
  cast(null as string) as numero_long,
  cast(null as string) as numero_ordre_depot,
  cast(null as string) as prefixe_organe_examen,
  cast(null as string) as examen_ref,
  cast(null as string) as texte_legislatif_ref,
  cast(null as string) as dossier_legislatif_ref,
  cast(null as string) as division_titre,
  cast(null as string) as article_designation_courte,
  cast(null as string) as division_type,
  cast(null as date) as date_depot,
  cast(null as date) as date_publication,
  cast(null as string) as etat_code,
  cast(null as string) as etat_libelle,
  cast(null as string) as sous_etat_code,
  cast(null as string) as sous_etat_libelle,
  cast(null as string) as sort,
  cast(null as string) as auteur_type,
  cast(null as string) as auteur_acteur_ref,
  cast(null as string) as auteur_groupe_politique_ref
where false

{% else %}

select
  uid as amendement_uid,
  legislature,
  numero_long,
  numero_ordre_depot,
  prefixe_organe_examen,
  examen_ref,
  texte_legislatif_ref,
  dossier_legislatif_ref,
  division_titre,
  article_designation_courte,
  division_type,
  -- We don't bring in large text fields like dispositif/expose_sommaire unless needed for NLP, 
  -- but let's leave them out for analytical staging unless specified.
  date_depot,
  date_publication,
  etat_code,
  etat_libelle,
  sous_etat_code,
  sous_etat_libelle,
  sort,
  auteur_type,
  auteur_acteur_ref,
  auteur_groupe_politique_ref
from {{ source('raw_parleman', 'amendements') }}

{% endif %}
