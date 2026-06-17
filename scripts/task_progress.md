# Deep-Trace Debugging: INDOOR_SEARCH Transition

## Todo List

- [ ] Instrument `_indoor_search_state()` in entity_ai.gd with entry/exit/breach-gate trace logs
- [ ] Instrument `process_state_logic()` in entity_ai.gd with Director override audit
- [ ] Instrument `evaluate_master_state()` in entity_director.gd with tier-by-tier trace for INDOOR_SEARCH
- [ ] Instrument stuck detection in entity_controller.gd with pre-fade_and_relocate() condition dump
- [ ] Verify all trace logs are properly placed and non-duplicating
- [ ] Report findings with root cause analysis
