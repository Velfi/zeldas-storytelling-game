package main

import "core:fmt"
import "core:strings"

Authoring_Recheck_Plan :: struct {
	changed: Authoring_Validation_Domain,
	domains: [len(Authoring_Validation_Domain)]Authoring_Validation_Domain,
	count:   int,
}

Authoring_Navigation_Target :: struct {
	workspace:                       string,
	document, entity_id, field_path: string,
	location:                        Authoring_Diagnostic_Location,
}

Authoring_Fix_Context :: struct {
	story:    ^Story_Project,
	graph:    ^Graph_Document,
	level:    ^Level_Document,
	campaign: ^Campaign_Definition,
	assets:   ^Project_Asset_Registry,
}

Authoring_Project_Validation_Input :: struct {
	story:     ^Story_Project,
	graph:     ^Graph_Document,
	level:     ^Level_Document,
	campaign:  ^Campaign_Definition,
	assets:    ^Project_Asset_Registry,
	pkg:       ^Authoring_Package_Inspection,
	revisions: [len(Authoring_Validation_Domain)]u64,
}

Authoring_Playtest_Snapshot :: struct {
	active:              bool,
	story:               Story_Project,
	story_present:       bool,
	runtime:             Story_Runtime_Save,
	runtime_present:     bool,
	level:               Level_Document,
	level_present:       bool,
	graph:               Graph_Document,
	graph_present:       bool,
	campaign:            Campaign_Definition,
	campaign_present:    bool,
	playthrough:         Campaign_Playthrough,
	authoring_revisions: [len(Authoring_Validation_Domain)]u64,
}

Authoring_Creator_Knowledge_Kind :: enum {
	Clue,
	Claim,
	Topic,
}
Authoring_Creator_Knowledge :: struct {
	kind:    Authoring_Creator_Knowledge_Kind,
	id:      string,
	present: bool,
}
Authoring_Creator_Variable :: struct {
	id:    string,
	value: Story_Value,
}
Authoring_Creator_Campaign_Value :: struct {
	id:    string,
	value: Campaign_Value,
}
Authoring_Creator_Objective :: struct {
	id:     string,
	status: Story_Objective_Status,
	stage:  int,
}
Authoring_Creator_Mystery_Progress_Kind :: enum {
	Deduction,
	Investigation,
	Question,
}
Authoring_Creator_Mystery_Progress :: struct {
	kind:  Authoring_Creator_Mystery_Progress_Kind,
	id:    string,
	state: int,
}
Authoring_Creator_State_Setup :: struct {
	variables:                      [dynamic]Authoring_Creator_Variable,
	knowledge:                      [dynamic]Authoring_Creator_Knowledge,
	objectives:                     [dynamic]Authoring_Creator_Objective,
	events:                         [dynamic]string,
	mystery_progress:               [dynamic]Authoring_Creator_Mystery_Progress,
	campaign_values:                [dynamic]Authoring_Creator_Campaign_Value,
	started_cases, completed_cases: [dynamic]string,
	action_budget:                  int,
	time_minutes:                   int,
}

Authoring_Scenario_Record :: struct {
	id, description: string,
	actions:         [dynamic]Scenario_Step,
}
Authoring_Scenario_Failure :: struct {
	failed:                     bool,
	action_index:               int,
	action:                     Scenario_Step,
	message, scene_id, node_id: string,
}
Authoring_Scenario_Replay_Result :: struct {
	ok:       bool,
	executed: int,
	failure:  Authoring_Scenario_Failure,
}

authoring_story_severity :: proc(
	severity: Story_Diagnostic_Severity,
) -> Authoring_Diagnostic_Severity {switch severity {case .Info:
		return .Info; case .Warning:
		return .Warning; case .Error:
		return .Error}; return .Error}

authoring_story_is_mystery_diagnostic :: proc(message: string) -> bool {
	return(
		strings.has_prefix(message, "[affordability]") ||
		strings.has_prefix(message, "[routes]") ||
		strings.has_prefix(message, "[dependencies]") ||
		strings.has_prefix(message, "[spatial]") ||
		strings.has_prefix(message, "[exclusion]") ||
		strings.has_prefix(message, "[dialogue]") \
	)
}

authoring_adapt_story_validation :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	project: ^Story_Project,
) {
	if project == nil do return
	validated := story_project_validate(project); defer story_validation_destroy(&validated)
	for item in validated.diagnostics {
		domain: Authoring_Validation_Domain = .Story_Core; if authoring_story_is_mystery_diagnostic(item.message) do domain = .Mystery
		diagnostic := authoring_diagnostic_init(
			domain,
			"story",
			item.id,
			"",
			authoring_story_severity(item.severity),
			item.message,
		)
		authoring_validation_add(snapshot, diagnostic)
	}
}

authoring_adapt_graph_validation :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	doc: ^Graph_Document,
) {
	if doc == nil do return; _ = graph_validate(doc)
	for item in doc.diagnostics[:doc.diagnostic_count] {
		severity: Authoring_Diagnostic_Severity = .Warning; if item.severity == .Error do severity = .Error
		diagnostic := authoring_diagnostic_init(
			.Graph,
			"graph",
			item.node_id,
			"node",
			severity,
			item.message,
		); _ = authoring_diagnostic_add_related(&diagnostic, "graph", item.scene_id, "scene")
		authoring_validation_add(snapshot, diagnostic)
	}
}

authoring_adapt_level_validation :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	doc: ^Level_Document,
	project: ^Story_Project = nil,
) {
	if doc == nil do return; _ = level_validate(doc)
	for item in doc.diagnostics {
		severity: Authoring_Diagnostic_Severity = .Info; if item.severity == .Warning do severity = .Warning
		else if item.severity == .Error do severity = .Error
		field := authoring_level_diagnostic_field(item.message)
		diagnostic := authoring_diagnostic_init(
			.Level,
			"level",
			item.entity_id,
			field,
			severity,
			item.message,
		); authoring_diagnostic_set_location(&diagnostic, doc.id, item.story, item.position); authoring_validation_add(snapshot, diagnostic)
	}
	spatial := authoring_spatial_validate_level(
		doc,
		project,
	); defer delete(spatial); authoring_validation_merge(snapshot, spatial[:])
}

authoring_level_diagnostic_field :: proc(message: string) -> string {
	lower := strings.to_lower(message)
	if strings.contains(lower, "destination") do return "destination"
	if strings.contains(lower, "spawn radius") do return "radius"
	if strings.contains(lower, "camera") || strings.contains(lower, "height") do return "camera_height"
	if strings.contains(lower, "story") do return "story"
	if strings.contains(lower, "condition") do return "condition_id"
	if strings.contains(lower, "effect") do return "effect_ids"
	if strings.contains(lower, "scene") do return "focused_scene"
	if strings.contains(lower, "catalog") do return "catalog_id"
	if strings.contains(lower, "support") do return "support_id"
	if strings.contains(lower, "position") || strings.contains(lower, "outside") do return "position"
	return "entity"
}

authoring_adapt_campaign_validation :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	doc: ^Campaign_Definition,
) {
	if doc == nil do return; checked := campaign_validate(doc); if checked.ok do return
	diagnostic := authoring_diagnostic_init(
		.Campaign,
		"campaign",
		doc.id,
		"",
		.Error,
		checked.message,
	)
	if strings.contains(checked.message, "condition") do diagnostic.fix_id = "campaign.compact_conditions"
	authoring_validation_add(snapshot, diagnostic)
}

authoring_adapt_asset_validation :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	registry: ^Project_Asset_Registry,
) {if registry == nil do return; items := project_asset_registry_diagnostics(registry)
	defer delete(items)
	authoring_validation_merge(snapshot, items[:])}

authoring_adapt_package_validation :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	inspection: ^Authoring_Package_Inspection,
) {
	if inspection == nil do return; authoring_package_inspection_finalize(inspection); authoring_validation_merge(snapshot, inspection.diagnostics[:])
}

authoring_domain_depends_on :: proc(candidate, changed: Authoring_Validation_Domain) -> bool {
	if candidate == changed do return true
	switch changed {
	case .Story_Core:
		return(
			candidate == .Mystery ||
			candidate == .Graph ||
			candidate == .Packaging ||
			candidate == .Compatibility \
		)
	case .Mystery:
		return candidate == .Packaging || candidate == .Compatibility
	case .Graph:
		return candidate == .Story_Core || candidate == .Mystery || candidate == .Packaging
	case .Level:
		return candidate == .Story_Core || candidate == .Mystery || candidate == .Packaging
	case .Campaign:
		return candidate == .Packaging || candidate == .Compatibility
	case .Assets:
		return candidate == .Packaging || candidate == .Compatibility
	case .Packaging:
		return candidate == .Compatibility
	case .Compatibility:
	}
	return false
}

authoring_recheck_plan :: proc(
	changed: Authoring_Validation_Domain,
) -> Authoring_Recheck_Plan {result := Authoring_Recheck_Plan {
		changed = changed,
	}; for domain in Authoring_Validation_Domain {if authoring_domain_depends_on(
			domain,
			changed,
		) {result.domains[result.count] = domain; result.count += 1}}; return result}

authoring_apply_invalidation :: proc(
	snapshot: ^Authoring_Validation_Snapshot,
	changed: Authoring_Validation_Domain,
	revision: u64,
) -> Authoring_Recheck_Plan {plan := authoring_recheck_plan(changed); for 	domain in plan.domains[:plan.count] {authoring_validation_invalidate_domain(snapshot, domain); _ =
			authoring_validation_touch_domain(snapshot, domain, revision)}
	return plan}

authoring_invalidate_after_edit :: proc(
	changed: Authoring_Validation_Domain,
	revision: u64,
) -> Authoring_Recheck_Plan {
	if authoring_workspace.production_validation.domain_count == 0 do return authoring_recheck_plan(changed)
	return authoring_apply_invalidation(
		&authoring_workspace.production_validation,
		changed,
		revision,
	)
}

authoring_validate_project :: proc(
	input: Authoring_Project_Validation_Input,
	profile: Authoring_Validation_Profile,
	revision: u64,
) -> Authoring_Validation_Snapshot {
	result := authoring_validation_snapshot_init(profile, revision)
	for domain in Authoring_Validation_Domain do _ = authoring_validation_touch_domain(&result, domain, input.revisions[domain])
	authoring_adapt_story_validation(
		&result,
		input.story,
	); authoring_adapt_graph_validation(&result, input.graph); authoring_adapt_level_validation(&result, input.level, input.story); authoring_adapt_campaign_validation(&result, input.campaign); authoring_adapt_asset_validation(&result, input.assets); authoring_adapt_package_validation(&result, input.pkg)
	for domain in Authoring_Validation_Domain do _ = authoring_validation_mark_domain_valid(&result, domain, input.revisions[domain]); authoring_validation_sort(&result); return result
}

authoring_diagnostic_navigation :: proc(
	diagnostic: Authoring_Diagnostic,
) -> Authoring_Navigation_Target {
	workspace := "diagnostics"; switch diagnostic.domain {case .Campaign:
		workspace = "campaign"; case .Story_Core:
		workspace = "story"; case .Mystery:
		workspace = "mystery"; case .Graph:
		workspace = "graph"; case .Level:
		workspace = "build"; case .Assets:
		workspace = "assets"; case .Packaging:
		workspace = "export"; case .Compatibility:
		workspace = "library"}
	return {
		workspace = workspace,
		document = diagnostic.document,
		entity_id = diagnostic.entity_id,
		field_path = diagnostic.field_path,
		location = diagnostic.location,
	}
}

authoring_dispatch_safe_fix :: proc(fix_id: string, ctx: ^Authoring_Fix_Context) -> Validation {
	if ctx == nil do return {false, "safe-fix context is required"}
	switch fix_id {case "campaign.compact_conditions":
		if ctx.campaign == nil do return {false, "campaign is required for this safe fix"}
		return campaign_condition_compact(ctx.campaign)}
	return {false, "unknown or non-safe fix ID"}
}

authoring_graph_document_destroy :: proc(doc: ^Graph_Document) {delete(doc.conditions); delete(
		doc.effects,
	)
	for 	&node in doc.nodes[:doc.node_count] {delete(node.beat.choice_ids); delete(node.beat.choice_labels)
		delete(node.beat.choice_targets)
		delete(node.beat.choice_conditions)
		delete(node.beat.effect_ids)
		delete(node.beat.requires_clues)
		delete(node.beat.requires_claims)
		delete(node.beat.requires_topics)
		delete(node.beat.unlock_clues)
		delete(node.beat.unlock_claims)
		delete(node.beat.unlock_topics)}
	doc^ = {}}

authoring_level_document_destroy :: proc(doc: ^Level_Document) {delete(doc.stories); for &item in doc.rooms do delete(item.points)
	for &item in doc.paths do delete(item.points)
	delete(doc.openings)
	delete(doc.objects)
	delete(doc.lights)
	delete(doc.roofs)
	for &item in doc.waters do delete(item.points)
	for &item in doc.foundations do delete(item.points)
	delete(doc.vertical_links)
	delete(doc.markers)
	delete(doc.terrain)
	delete(doc.diagnostics)
	doc^ = {}}

authoring_playtest_snapshot_create :: proc(
	story: ^Story_Project,
	runtime: ^Story_Runtime,
	level: ^Level_Document,
	graph: ^Graph_Document,
	campaign: ^Campaign_Definition,
	playthrough: ^Campaign_Playthrough,
	revisions: [len(Authoring_Validation_Domain)]u64,
) -> Authoring_Playtest_Snapshot {
	result := new(
		Authoring_Playtest_Snapshot,
	); defer free(result); result.active = true; result.authoring_revisions = revisions; if story != nil {result.story = story_project_clone(story); result.story_present = true}; if runtime != nil && runtime.compiled != nil {result.runtime = story_runtime_save(runtime); result.runtime_present = true}; if level != nil {result.level = level_clone_document(level); result.level_present = true}; if graph != nil {result.graph = graph_document_clone(graph); result.graph_present = true}; if campaign != nil {result.campaign = campaign_clone(campaign); result.campaign_present = true}; if playthrough != nil do result.playthrough = playthrough^; return result^
}

authoring_playtest_snapshot_restore_runtime :: proc(
	snapshot: ^Authoring_Playtest_Snapshot,
	runtime: ^Story_Runtime,
) -> bool {return(
		snapshot != nil &&
		snapshot.active &&
		snapshot.runtime_present &&
		runtime != nil &&
		story_runtime_restore(runtime, &snapshot.runtime) \
	)}

authoring_playtest_snapshot_source_unchanged :: proc(
	snapshot: ^Authoring_Playtest_Snapshot,
	story: ^Story_Project,
	level: ^Level_Document,
	graph: ^Graph_Document,
	campaign: ^Campaign_Definition,
) -> bool {
	if snapshot == nil || !snapshot.active do return false; if snapshot.story_present && (story == nil || story.revision != snapshot.story.revision) do return false; if snapshot.level_present && (level == nil || level.revision != snapshot.level.revision) do return false; if snapshot.graph_present && (graph == nil || graph.revision != snapshot.graph.revision) do return false; if snapshot.campaign_present && campaign == nil do return false; return true
}

authoring_playtest_snapshot_destroy :: proc(
	snapshot: ^Authoring_Playtest_Snapshot,
) {if snapshot.story_present do story_project_destroy(&snapshot.story)
	if snapshot.runtime_present do story_runtime_save_destroy(&snapshot.runtime)
	if snapshot.level_present do authoring_level_document_destroy(&snapshot.level)
	if snapshot.graph_present do authoring_graph_document_destroy(&snapshot.graph)
	if snapshot.campaign_present {delete(snapshot.campaign.variables); delete(snapshot.campaign.conditions)
		delete(snapshot.campaign.effects)
		delete(snapshot.campaign.cases)}
	snapshot^ = {}}

authoring_creator_setup_destroy :: proc(setup: ^Authoring_Creator_State_Setup) {delete(
		setup.variables,
	)
	delete(setup.knowledge)
	delete(setup.objectives)
	delete(setup.events)
	delete(setup.mystery_progress)
	delete(setup.campaign_values)
	delete(setup.started_cases)
	delete(setup.completed_cases)
	setup^ = {}}

authoring_apply_creator_setup :: proc(
	setup: ^Authoring_Creator_State_Setup,
	scenario: ^Scenario_Context,
	campaign: ^Campaign_Definition,
	playthrough: ^Campaign_Playthrough,
) -> Validation {
	if setup == nil do return {false, "creator state setup is required"}
	if scenario !=
	   nil {for variable in setup.variables {index := story_state_value_index(&scenario.runtime.state, variable.id); if index < 0 do return {false, fmt.tprintf("unknown story variable %s", variable.id)}; scenario.runtime.state.values[index].value = variable.value}; if setup.time_minutes >= 0 {time_index := story_state_value_index(&scenario.runtime.state, "time_minutes"); if time_index >= 0 do scenario.runtime.state.values[time_index].value = story_value_integer(setup.time_minutes)}; for item in setup.knowledge {if !item.present do continue; kind := "clue"; if item.kind == .Claim do kind = "claim"
			else if item.kind == .Topic do kind = "topic"; if !scenario_set_known(scenario, kind, item.id) do return {false, fmt.tprintf("could not establish %s", item.id)}}; for item in setup.objectives {index := story_state_objective_index(&scenario.runtime.state, item.id); if index < 0 do return {false, fmt.tprintf("unknown story objective %s", item.id)}; scenario.runtime.state.objectives[index].status = item.status; scenario.runtime.state.objectives[index].stage = item.stage}; for id in setup.events {if story_event_index(&scenario.compiled.runtime, id) < 0 do return {false, fmt.tprintf("unknown story event %s", id)}; present := false; for existing in scenario.runtime.state.emitted_events do if existing == id do present = true; if !present do append(&scenario.runtime.state.emitted_events, id)}; state := scenario_mystery(scenario); if state != nil {if setup.action_budget >= 0 do state.action_budget_remaining = setup.action_budget; for item in setup.mystery_progress {switch item.kind {case .Deduction:
					if mystery_deduction_index(mystery_payload(&scenario.compiled.runtime), item.id) < 0 do return {false, fmt.tprintf("unknown deduction %s", item.id)}
					_ = mystery_string_set_add(
						&state.earned_deductions,
						item.id,
					); case .Investigation:
					_ = mystery_string_set_add(
						&state.completed_investigations,
						item.id,
					); case .Question:
					if mystery_question_index(mystery_payload(&scenario.compiled.runtime), item.id) < 0 do return {false, fmt.tprintf("unknown question %s", item.id)}
					found := false
					for &progress in state.question_progress do if progress.question_id == item.id {progress.state = item.state; found = true}
					if !found do append(&state.question_progress, Mystery_Question_Progress{question_id = item.id, state = item.state})}}}}
	if campaign != nil &&
	   playthrough !=
		   nil {for item in setup.campaign_values {index := campaign_variable_index(campaign, item.id); if index < 0 do return {false, fmt.tprintf("unknown campaign variable %s", item.id)}; playthrough.values[index] = item.value}; for id in setup.started_cases {index := campaign_case_index(campaign, id); if index < 0 do return {false, fmt.tprintf("unknown campaign case %s", id)}; playthrough.results[index].started = true; playthrough.results[index].case_id = id}; for id in setup.completed_cases {index := campaign_case_index(campaign, id); if index < 0 do return {false, fmt.tprintf("unknown campaign case %s", id)}; playthrough.results[index].started = true; playthrough.results[index].present = true; playthrough.results[index].case_id = id}; _ = campaign_recalculate(campaign, playthrough)}
	return {true, "CREATOR STATE APPLIED TO PLAYTEST COPY"}
}

authoring_scenario_record_init :: proc(
	id, description: string,
) -> Authoring_Scenario_Record {return {id = id, description = description}}
authoring_scenario_record_action :: proc(
	record: ^Authoring_Scenario_Record,
	step: Scenario_Step,
) -> bool {if record == nil || step.action == "" do return false; append(&record.actions, step)
	return true}
authoring_scenario_record_destroy :: proc(record: ^Authoring_Scenario_Record) {delete(
		record.actions,
	)
	record^ = {}}

authoring_scenario_replay :: proc(
	record: ^Authoring_Scenario_Record,
	scenario: ^Scenario_Context,
) -> Authoring_Scenario_Replay_Result {
	result := Authoring_Scenario_Replay_Result {
		ok = true,
	}; if record == nil || scenario == nil {result.ok = false; result.failure = {
			failed  = true,
			message = "scenario record and runtime are required",
		}; return result}
	for step, index in record.actions {ok, message := scenario_execute_step(scenario, step); if !ok {result.ok = false; result.failure = {
				failed       = true,
				action_index = index,
				action       = step,
				message      = message,
				scene_id     = scenario.runtime.current_scene,
				node_id      = scenario.runtime.current_node,
			}; return result}; result.executed += 1}; return result
}

authoring_scenario_quote :: proc(value: string) -> string {result := ""; for 	rune in value {if rune == '\\' do result = fmt.tprintf("%s\\\\", result)
		else if rune == '\"' do result = fmt.tprintf("%s\\\"", result)
		else if rune == '\n' do result = fmt.tprintf("%s\\n", result)
		else do result = fmt.tprintf("%s%c", result, rune)}
	return result}

authoring_scenario_failure_serialize :: proc(
	record: ^Authoring_Scenario_Record,
	result: ^Authoring_Scenario_Replay_Result,
) -> string {if result == nil || !result.failure.failed do return "failure = false\n"; f :=
		result.failure
	return fmt.tprintf(
		"failure = true\nscenario_id = \"%s\"\naction_index = %d\naction = \"%s\"\nvalue = \"%s\"\nstate = \"%s\"\noutcome = \"%s\"\nscene_id = \"%s\"\nnode_id = \"%s\"\nmessage = \"%s\"\n",
		record == nil ? "" : authoring_scenario_quote(record.id),
		f.action_index,
		authoring_scenario_quote(f.action.action),
		authoring_scenario_quote(f.action.value),
		authoring_scenario_quote(f.action.state),
		authoring_scenario_quote(f.action.outcome),
		authoring_scenario_quote(f.scene_id),
		authoring_scenario_quote(f.node_id),
		authoring_scenario_quote(f.message),
	)}

authoring_player_safe_audit :: proc(
	project: ^Story_Project,
	inspection: ^Authoring_Package_Inspection,
	revision: u64,
) -> Authoring_Validation_Snapshot {
	result := authoring_validation_snapshot_init(
		.Player_Safe,
		revision,
	); _ = authoring_validation_touch_domain(&result, .Story_Core, revision); _ = authoring_validation_touch_domain(&result, .Mystery, revision); _ = authoring_validation_touch_domain(&result, .Packaging, revision)
	if project ==
	   nil {authoring_validation_add(&result, authoring_diagnostic_init(.Story_Core, "story", "", "", .Blocking, "player-safe audit requires a story project"))} else {authoring_adapt_story_validation(&result, project); forbidden_terms := [4]string{"canonical truth", "accepted deduction", "solution key", "creator-only"}; for node in project.nodes {surface := strings.to_lower(fmt.tprintf("%s %s %s", node.ui, node.summary, node.ending)); for forbidden in forbidden_terms {if strings.contains(surface, forbidden) {authoring_validation_add(&result, authoring_diagnostic_init(.Story_Core, "story", node.id, "ui", .Blocking, "player-facing node metadata exposes creator-only solution data")); break}}}}
	if inspection !=
	   nil {authoring_adapt_package_validation(&result, inspection); for diagnostic in inspection.diagnostics do if strings.contains(strings.to_lower(diagnostic.message), "creator-only") do authoring_validation_add(&result, authoring_diagnostic_init(.Packaging, "package", inspection.artifact.identity.id, "player_safe", .Blocking, "package inspection reports creator-only exposure"))}
	_ = authoring_validation_mark_domain_valid(
		&result,
		.Story_Core,
		revision,
	); _ = authoring_validation_mark_domain_valid(&result, .Mystery, revision); _ = authoring_validation_mark_domain_valid(&result, .Packaging, revision); authoring_validation_sort(&result); return result
}
