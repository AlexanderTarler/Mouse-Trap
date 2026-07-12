# Task Progress

- [x] Read and analyze all affected files (notebook_ui.gd, entity_director.gd, entity_ai.gd, entity_controller.gd)
- [x] Confirm understanding of all three issues
- [x] **Issue 1**: Add Conclusion lines to NEST_LORE in notebook_ui.gd
- [x] **Issue 2**: Add STALK cabin-entry interrupt to entity_director.gd (above state lock guards)
- [x] **Issue 3**: Refactor notebook_ui.gd for proper chapter structure
  - [x] 3a: Add chapter tracking variables (`_nest_data_start_page`, `_notes_start_page`)
  - [x] 3b: Restructure `_initialize_pages()` with credentials (LUND/PASSKEY1)
  - [x] 3c: Rewrite `add_documentation()` → uses `_insert_text_before_notes()` for chapter insertion
  - [x] 3d: Rewrite `add_note()` → always appends, updates `_notes_start_page`
  - [x] 3e: Add dynamic `_rebuild_index()` helper (live page numbers in TOC)
  - [x] 3f: Add `_split_into_pages()` utility extracted from `_append_text()`
