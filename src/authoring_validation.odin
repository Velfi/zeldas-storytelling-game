package main

import "core:strings"

AUTHORING_DIAGNOSTIC_MAX_RELATED :: 8
AUTHORING_VALIDATION_MAX_DOMAINS :: 16

Authoring_Validation_Profile :: enum {
	Draft,
	Playable,
	Exportable,
	Player_Safe,
}

Authoring_Diagnostic_Severity :: enum {
	Info,
	Warning,
	Error,
	Blocking,
}

Authoring_Validation_Domain :: enum {
	Campaign,
	Story_Core,
	Mystery,
	Graph,
	Level,
	Assets,
	Packaging,
	Compatibility,
}

Authoring_Diagnostic_Location :: struct {
	present:  bool,
	space_id: string,
	story:    int,
	position: Vec2,
}

Authoring_Diagnostic_Related_Record :: struct {
	document:   string,
	entity_id:  string,
	field_path: string,
}

Authoring_Diagnostic :: struct {
	domain:        Authoring_Validation_Domain,
	document:      string,
	entity_id:     string,
	field_path:    string,
	severity:      Authoring_Diagnostic_Severity,
	message:       string,
	related:       [AUTHORING_DIAGNOSTIC_MAX_RELATED]Authoring_Diagnostic_Related_Record,
	related_count: int,
	location:      Authoring_Diagnostic_Location,
	fix_id:        string,
}

Authoring_Domain_Freshness :: struct {
	domain:             Authoring_Validation_Domain,
	source_revision:    u64,
	validated_revision: u64,
	valid:              bool,
}

Authoring_Validation_Snapshot :: struct {
	revision:     u64,
	profile:      Authoring_Validation_Profile,
	diagnostics:  [dynamic]Authoring_Diagnostic,
	domains:      [AUTHORING_VALIDATION_MAX_DOMAINS]Authoring_Domain_Freshness,
	domain_count: int,
}

Authoring_Diagnostic_Filter :: struct {
	minimum_severity: Authoring_Diagnostic_Severity,
	domain_enabled:   [len(Authoring_Validation_Domain)]bool,
	search:           string,
}

authoring_diagnostic_init :: proc(
	domain: Authoring_Validation_Domain,
	document, entity_id, field_path: string,
	severity: Authoring_Diagnostic_Severity,
	message: string,
) -> Authoring_Diagnostic {
	return {
		domain = domain,
		document = document,
		entity_id = entity_id,
		field_path = field_path,
		severity = severity,
		message = message,
	}
}

authoring_diagnostic_add_related :: proc(
	diagnostic: ^Authoring_Diagnostic,
	document, entity_id, field_path: string,
) -> bool {
	if diagnostic.related_count >= len(diagnostic.related) do return false
	diagnostic.related[diagnostic.related_count] = {document, entity_id, field_path}
	diagnostic.related_count += 1
	return true
}

authoring_diagnostic_set_location :: proc(
	diagnostic: ^Authoring_Diagnostic,
	space_id: string,
	story: int,
	position: Vec2,
) {
	diagnostic.location = {
		present  = true,
		space_id = space_id,
		story    = story,
		position = position,
	}
}

authoring_validation_snapshot_init :: proc(
	profile: Authoring_Validation_Profile,
	revision: u64,
) -> Authoring_Validation_Snapshot {
	return {profile = profile, revision = revision}
}

authoring_validation_snapshot_destroy :: proc(snapshot: ^Authoring_Validation_Snapshot) {
	delete(snapshot.diagnostics)
	snapshot^ = {}
}

authoring_validation_domain_index :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	domain: Authoring_Validation_Domain,
) -> int {
	for item, index in snapshot.domains[:snapshot.domain_count] do if item.domain == domain do return index
	return -1
}

authoring_validation_touch_domain :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	domain: Authoring_Validation_Domain,
	source_revision: u64,
) -> bool {
	index := authoring_validation_domain_index(snapshot, domain)
	if index < 0 {
		if snapshot.domain_count >= len(snapshot.domains) do return false
		index = snapshot.domain_count
		snapshot.domain_count += 1
		snapshot.domains[index].domain = domain
	}
	item := &snapshot.domains[index]
	if item.source_revision != source_revision {
		item.source_revision = source_revision
		item.valid = false
	}
	return true
}

authoring_validation_mark_domain_valid :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	domain: Authoring_Validation_Domain,
	validated_revision: u64,
) -> bool {
	index := authoring_validation_domain_index(snapshot, domain)
	if index < 0 do return false
	item := &snapshot.domains[index]
	item.validated_revision = validated_revision
	item.valid = validated_revision == item.source_revision
	return item.valid
}

authoring_validation_domain_fresh :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	domain: Authoring_Validation_Domain,
) -> bool {
	index := authoring_validation_domain_index(snapshot, domain)
	if index < 0 do return false
	item := snapshot.domains[index]
	return item.valid && item.validated_revision == item.source_revision
}

authoring_validation_invalidate_domain :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	domain: Authoring_Validation_Domain,
) {
	index := authoring_validation_domain_index(snapshot, domain)
	if index >= 0 do snapshot.domains[index].valid = false
	for index := len(snapshot.diagnostics) - 1; index >= 0; index -= 1 {
		if snapshot.diagnostics[index].domain == domain do ordered_remove(&snapshot.diagnostics, index)
	}
}

authoring_validation_add :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	diagnostic: Authoring_Diagnostic,
) {
	item := diagnostic
	item.related_count = clamp(item.related_count, 0, len(item.related))
	append(&snapshot.diagnostics, item)
}

authoring_validation_merge :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	diagnostics: []Authoring_Diagnostic,
) {
	for diagnostic in diagnostics do authoring_validation_add(snapshot, diagnostic)
}

authoring_diagnostic_less :: proc(a, b: Authoring_Diagnostic) -> bool {
	if a.domain != b.domain do return int(a.domain) < int(b.domain)
	if a.document != b.document do return strings.compare(a.document, b.document) < 0
	if a.entity_id != b.entity_id do return strings.compare(a.entity_id, b.entity_id) < 0
	if a.field_path != b.field_path do return strings.compare(a.field_path, b.field_path) < 0
	if a.severity != b.severity do return int(a.severity) > int(b.severity)
	if a.message != b.message do return strings.compare(a.message, b.message) < 0
	return strings.compare(a.fix_id, b.fix_id) < 0
}

authoring_validation_sort :: proc(snapshot: ^Authoring_Validation_Snapshot) {
	for index in 1 ..< len(snapshot.diagnostics) {
		item := snapshot.diagnostics[index]
		position := index
		for position > 0 && authoring_diagnostic_less(item, snapshot.diagnostics[position - 1]) {
			snapshot.diagnostics[position] = snapshot.diagnostics[position - 1]
			position -= 1
		}
		snapshot.diagnostics[position] = item
	}
}

authoring_validation_profile_blocks :: proc(
	profile: Authoring_Validation_Profile,
	severity: Authoring_Diagnostic_Severity,
) -> bool {
	switch profile {
	case .Draft:
		return severity == .Blocking
	case .Playable:
		return severity >= .Error
	case .Exportable, .Player_Safe:
		return severity >= .Warning
	}
	return true
}

authoring_validation_is_blocked :: proc(snapshot: ^Authoring_Validation_Snapshot) -> bool {
	for item in snapshot.domains[:snapshot.domain_count] do if !authoring_validation_domain_fresh(snapshot, item.domain) do return true
	for diagnostic in snapshot.diagnostics do if authoring_validation_profile_blocks(snapshot.profile, diagnostic.severity) do return true
	return false
}

authoring_diagnostic_filter_all :: proc() -> Authoring_Diagnostic_Filter {
	result := Authoring_Diagnostic_Filter {
		minimum_severity = .Info,
	}
	for &enabled in result.domain_enabled do enabled = true
	return result
}

authoring_diagnostic_matches :: proc(
	diagnostic: Authoring_Diagnostic,
	filter: ^Authoring_Diagnostic_Filter,
) -> bool {
	if diagnostic.severity < filter.minimum_severity || !filter.domain_enabled[diagnostic.domain] do return false
	if filter.search == "" do return true
	needle := strings.to_lower(filter.search)
	return(
		strings.contains(strings.to_lower(diagnostic.document), needle) ||
		strings.contains(strings.to_lower(diagnostic.entity_id), needle) ||
		strings.contains(strings.to_lower(diagnostic.field_path), needle) ||
		strings.contains(strings.to_lower(diagnostic.message), needle) \
	)
}

authoring_validation_filtered_indices :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	filter: ^Authoring_Diagnostic_Filter,
	allocator := context.allocator,
) -> [dynamic]int {
	result := make([dynamic]int, 0, len(snapshot.diagnostics), allocator)
	for diagnostic, index in snapshot.diagnostics do if authoring_diagnostic_matches(diagnostic, filter) do append(&result, index)
	return result
}
