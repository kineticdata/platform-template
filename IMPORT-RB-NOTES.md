# import.rb — field notes & enhancement candidates

Observations from a real cross-space deployment (hanford-dev 6.1.7 → servicecatalog-dev 6.0.7).
Intended to help whoever next enhances `import.rb`. **Line numbers are from the version in this
repo as of mid-2026 and will drift — confirm against the actual file.** Several items below are
marked ⚠ UNCONFIRMED: observed behavior that may be a version-specific quirk rather than intended
design. Verify before relying on them.

---

## Status update (2026-06-24)

- **Item 2 (definition-level methods never called) — ADDRESSED.** `import_space()` now calls
  `update_space_attributes`, `update_user_attributes`, `update_user_profile_attributes`,
  `update_team_attributes`, `update_security_policy`, `import_space_teams`,
  `update_datastore_attributes`, and (per-kapp) `import_kapp_category_definitions`, plus
  `import_datastore_data` for datastore submissions. These methods also previously referenced the
  local `vars` without taking it as a parameter (a latent `NameError`); they now take `vars`.
  Users and routine response templates still have no import path (manual).
- **Skip-if-unchanged for forms — ADDRESSED.** The old `updatedAt` comparison was dead (exports
  carry no `updatedAt`); replaced with a content deep-equality comparison, on by default.
- **Item 1 (routine layout) — STILL OPEN.** Routines under `task/sources/*/trees/` vs
  `task/routines/` remains version/export-format dependent; a layout-agnostic routine import
  (route by the XML `<type>` element) is still a candidate enhancement.

---

## 1. ⚠ UNCONFIRMED — Global Routines import only from `task/routines/`

`import.rb` ingests Global Routines via `import_routines_threaded` (≈ line 384) and identifies them
for delete-reconciliation from `Dir["#{task_path}/routines/*.xml"]` (≈ line 462). Source-group
**Trees** are read separately from `Dir["#{task_path}/sources/*/trees/*.xml"]` (≈ line 473).

**Observed problem:** a bundle that stored Global Routines under `task/sources/<source>/trees/`
(the layout one space's `export.rb` produced) had those routines **silently not import** — forms
landed, but new routines never appeared and existing ones were never overwritten. Moving them to
`task/routines/` (or importing them another way) fixed it.

**Why this is marked UNCONFIRMED / possible version issue:**
- The standard Kinetic `export.rb` appears to write Global Routines to `task/routines/` with
  lowercase-hyphenated filenames. One source space instead exported them under
  `task/sources/kinetic-task/trees/` with Title-Case filenames. It's unclear whether that
  alternate layout is an older/newer export-format variant, a custom task source, or an anomaly.
- So the "bug" may be on the **export** side (non-standard placement) rather than import. Either
  way, the failure mode is real: routine files outside `task/routines/` don't import.

**Enhancement candidate:** make routine import layout-agnostic — scan all task `*.xml`, read the
`<type>` element, and route any `<type>Global Routine</type>` through the routine importer
regardless of folder. That would make import.rb tolerant of either export layout.

**Reliable workaround (no import.rb change):** push trees + routines via the Task component API,
multipart `POST /app/components/task/app/api/v2/trees?force=true`, form field name `content`. The
endpoint reads `<type>`/`<definitionId>` from the XML, so it imports a routine or a tree correctly
regardless of source folder. (A working Ruby/stdlib importer doing exactly this was built for the
delegation deployment — see the HMIS_IMPORT bundle's `servicecatalog_import.rb`.)

---

## 2. Definition-level methods are defined but NOT called from `import_space()`

These exist in import.rb but are never invoked by the main `import_space()` path, so the
corresponding artifacts do **not** import on a normal run:
- space attribute definitions
- team attribute definitions
- space-level security policy definitions
- teams (`import_space_teams`)

And these have **no import path at all**:
- users (service accounts etc.)
- source-group routine **response templates** (the `.response.erb` — console-paste only; no API)

**Enhancement candidate:** call the existing `update_space_attributes` / `update_team_attributes`
/ `update_security_policy` / `import_space_teams` methods from `import_space()` (a known ~5-line
patch), guarded by a config flag. Users + response templates still need a separate path or remain
documented manual steps.

Until then, a deployment needs a manual/scripted companion for those (we used a direct-API script;
the API endpoints are `/spaceAttributeDefinitions`, `/teamAttributeDefinitions`,
`/securityPolicyDefinitions`, `/teams`, `/users`).

---

## 3. Datastore forms import via the normal kapp loop

The modern `datastore` kapp is a normal kapp; its forms import through the same `import_forms`
path as `services` forms. The legacy `import_datastore_forms` / `add_datastore_form` methods are
for the deprecated datastore type and don't apply. Don't treat datastore forms as a special case.

---

## 4. `options.delete` reconciliation

Import reconciles destination vs source and can delete trees/routines/forms not present in the
source data. For an additive cross-space deployment set `options.delete: false` (or equivalent) so
destination-only artifacts aren't culled. The delete-identification for routines reads
`task/routines/*.xml` — see item 1; if routines are mislaid the reconciler also can't see them.

---

## 5. Folder the script actually reads

`import.rb` reads `core/` and `task/` from `exports/<folderName>/`, where `<folderName>` derives
from config `old_space_slug` → `space_slug` → `space_name`. A bundle in a differently-named folder
is ignored — symptom is an import that finishes in seconds with no `Adding new form` lines. Confirm
the config folder name matches where the files actually are before running.

---

## 6. Cross-version form keys (6.1.x → 6.0.x)

6.1.x adds form-element keys `defaultDataSource`, `choicesDataSource`, and
`renderAttributes.width` that 6.0.x **rejects on import**. API `export=true` omits them;
`export.rb` includes them. Strip them before importing a 6.1 export into 6.0. Task-tree XML is
otherwise version-identical between 6.0 and 6.1.

---

## Suggested verification before enhancing import.rb elsewhere

1. Export a space that has Global Routines; note whether they land in `task/routines/` or under
   `task/sources/*/trees/`. That tells you if item 1 affects your export-format version.
2. Grep `import.rb` for which `import_*` / `update_*` methods are actually called inside
   `import_space()` vs merely defined — item 2 may differ by version.
3. Dry-run against a sandbox space with `delete:false` and diff before/after.
