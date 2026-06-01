# Day 1 Hasselmus Nest Documentation System

## Todo List

### 1. Create photo_camera.gd ✅

- [x] Create a camera tool script that detects nest objects via raycast
- [x] Store photographed nest IDs to prevent duplicate documentation
- [x] On successful photo: mark nest as documented, notify RoutineManager
- [x] Each nest requires exactly ONE unique photo

### 2. Update hasselmus_nest.gd ✅

- [x] Add `is_photographed` flag (separate from old `is_documented`)
- [x] Add `photograph()` method called by the camera
- [x] Keep old `interact()` for backward compatibility but deprecate it
- [x] Add group "photographable_nests" for camera detection

### 3. Update computer_ui.gd — Pre-check Guard ✅

- [x] Add `_all_nests_photographed()` check before allowing correlation
- [x] If not all nests photographed: show error about "FLOATING FIELD SAMPLES"
- [x] Keep `nest_data_uploaded = false` until guard passes
- [x] Only Profile A (eco-survey) uses the nest guard

### 4. Update routine_manager.gd ✅

- [x] Already compatible — `document_nest()` called by camera photo
- [x] Keep existing step advancement logic (3 nests → Step 1)

### 5. Verify Integration

- [ ] Test: photograph 3 nests → computer shows eco-survey → correct correlation → phone drop
- [ ] Test: try correlating without all nests photographed → error message
- [ ] Test: wrong dropdown selections → Win98 error
