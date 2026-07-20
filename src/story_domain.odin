package main

STORY_MAX_DOMAIN_ADAPTERS :: 16
STORY_MAX_CAPABILITIES :: 16

Story_Domain_Adapter :: struct {
	id, version:    string,
	validate:       proc(project: ^Story_Project, result: ^Story_Validation),
	compile:        proc(project: ^Story_Project) -> bool,
	hash:           proc(project: ^Story_Project, seed: u64) -> u64,
	// Domain source ownership hooks. Parsers may attach an opaque payload once
	// domain records are present; core never interprets it.
	parse:          proc(source: rawptr, project: ^Story_Project) -> bool,
	clone:          proc(source: rawptr) -> rawptr,
	destroy:        proc(payload: rawptr),
	serialize:      proc(payload: rawptr) -> string,
	state_create:   proc(project: ^Story_Project) -> rawptr,
	state_clone:    proc(state: rawptr) -> rawptr,
	state_destroy:  proc(state: rawptr),
	condition_eval: proc(state: rawptr, query: string) -> Story_Condition_Trace,
}

story_domain_adapters: [STORY_MAX_DOMAIN_ADAPTERS]Story_Domain_Adapter
story_domain_adapter_count: int

story_domain_adapter_complete :: proc(adapter: Story_Domain_Adapter) -> bool {
	if adapter.id == STORY_DOMAIN_CORE do return true
	return(
		adapter.parse != nil &&
		adapter.clone != nil &&
		adapter.destroy != nil &&
		adapter.validate != nil &&
		adapter.compile != nil &&
		adapter.hash != nil &&
		adapter.serialize != nil &&
		adapter.state_create != nil &&
		adapter.state_clone != nil &&
		adapter.state_destroy != nil \
	)
}

story_domain_register :: proc(adapter: Story_Domain_Adapter) -> bool {
	if adapter.id == "" || adapter.version == "" || !story_domain_adapter_complete(adapter) do return false
	for existing in story_domain_adapters[:story_domain_adapter_count] do if existing.id == adapter.id && existing.version == adapter.version do return false
	if story_domain_adapter_count >= len(story_domain_adapters) do return false
	story_domain_adapters[story_domain_adapter_count] =
		adapter; story_domain_adapter_count += 1; return true
}

story_domain_find :: proc(id, version: string) -> ^Story_Domain_Adapter {
	for &adapter in story_domain_adapters[:story_domain_adapter_count] do if adapter.id == id && adapter.version == version do return &adapter
	return nil
}

story_capability_index :: proc(project: ^Story_Project, id, version: string) -> int {
	if project == nil do return -1
	for item, i in project.capabilities do if item.id == id && item.version == version do return i
	return -1
}

story_capability_payload :: proc(project: ^Story_Project, id, version: string) -> rawptr {
	i := story_capability_index(
		project,
		id,
		version,
	); if i < 0 do return nil; return project.capabilities[i].payload
}

story_domain_register_core :: proc() {
	if story_domain_find(STORY_DOMAIN_CORE, "1") != nil do return
	_ = story_domain_register({id = STORY_DOMAIN_CORE, version = "1"})
}

story_domains_initialize :: proc() {story_domain_register_core(); mystery_domain_register()}
