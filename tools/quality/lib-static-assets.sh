#!/usr/bin/env bash
# lib-static-assets.sh — docs/ files that are static assets, not narrative docs (idea#308).
# Sourced by quality-scan.sh and selftest.sh.
#
# A static asset is skipped by docs.missing_from_index and staleness.doc: it does not track
# the source tree, so "older than the source tip" says nothing, and listing every image or
# stylesheet in docs/INDEX.md adds no value. Static means:
#   - stylesheets and fonts:            *.css *.scss *.woff *.woff2 *.ttf
#   - images and rendered documents:    *.png *.jpg *.jpeg *.gif *.svg *.webp *.ico *.pdf
#   - sample / static data files:       *.json *.yaml *.yml *.csv *.tsv (under docs/ only)
#   - anything under a styles/, assets/, images/, screenshots/, static/ or superseded/ folder
# Markdown (*.md) and other text docs are never static and are always checked.
is_static_doc_asset() {
  local p="$1"
  case "$p" in
    *.md|*.markdown) return 1 ;;
  esac
  case "/$p" in
    */styles/*|*/assets/*|*/images/*|*/screenshots/*|*/static/*|*/superseded/*) return 0 ;;
  esac
  case "${p,,}" in
    *.css|*.scss|*.woff|*.woff2|*.ttf) return 0 ;;
    *.png|*.jpg|*.jpeg|*.gif|*.svg|*.webp|*.ico|*.pdf) return 0 ;;
    *.json|*.yaml|*.yml|*.csv|*.tsv) return 0 ;;
  esac
  return 1
}
