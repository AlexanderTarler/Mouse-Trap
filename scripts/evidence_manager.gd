extends Node


## EvidenceManager — Global singleton tracking physical evidence the player
## has collected in the environment. This feeds into the FIELD_LOG.EXE
## correlation terminal on the computer.
##
## Evidence Types:
##   - eco_survey:  Completed when all 3 nests are documented (Day 1)
##   - fluid_sample: Collected from black fluid puddles on window sills
##   - claw_sample:  Scraped from gouge marks on trees/machinery
##   - track_scan:   Scanned from bipedal ground compressions

signal evidence_collected(evidence_id: String)
signal evidence_removed(evidence_id: String)

## Dictionary of all collected evidence flags.
## Key = evidence_id string, Value = true
var collected_evidence: Dictionary = {}


func _ready() -> void:
	print("[EvidenceManager] Initialized.")


## Marks a piece of evidence as collected.
## Returns true if it was newly collected, false if already collected.
func collect_evidence(evidence_id: String) -> bool:
	if collected_evidence.has(evidence_id):
		print("[EvidenceManager] Evidence '%s' already collected." % evidence_id)
		return false
	
	collected_evidence[evidence_id] = true
	evidence_collected.emit(evidence_id)
	print("[EvidenceManager] Evidence collected: %s" % evidence_id)
	return true


## Checks if a specific piece of evidence has been collected.
func has_evidence(evidence_id: String) -> bool:
	return collected_evidence.has(evidence_id)

