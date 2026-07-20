package main

import "core:fmt"
import "core:strings"

SCENARIO_FORMAT_VERSION :: "ChicagoScenario v1"

Scenario_Step :: struct {
	action, value, state, outcome: string,
	equals, has_equals:            bool,
	integer:                       int,
	has_integer:                   bool,
}
Scenario_Test :: struct {
	id, description: string,
	enabled:         bool,
	steps:           []Scenario_Step,
}
Scenario_Document :: struct {
	version, story_path, level_path: string,
	tests:                           []Scenario_Test,
}
Scenario_Run_Result :: struct {
	ok:           bool,
	tests, steps: int,
	message:      string,
}

Scenario_Context :: struct {
	compiled:  Compiled_Story,
	runtime:   Story_Runtime,
	registry:  Story_Spatial_Registry,
	service:   Story_Spatial_Service,
	outcome:   Outcome,
	ending_id: string,
}

scenario_datum_has_key :: proc(table: Toml_Datum, key: string) -> bool {return(
		toml_seek_key(table, key).type !=
		.UNKNOWN \
	)}

scenario_load :: proc(path: string, out: ^Scenario_Document) -> Validation {
	cpath, err := strings.clone_to_cstring(
		path,
		context.temp_allocator,
	); if err != nil do return {false, "invalid scenario path"}
	parsed := toml_parse_file_ex(
		cpath,
	); defer toml_free(parsed); if !parsed.ok do return toml_parse_diagnostic(path, "scenario", &parsed)
	top := parsed.toptab; doc := Scenario_Document {
		version    = toml_case_string(top, "version"),
		story_path = toml_case_string(top, "story_path"),
		level_path = toml_case_string(top, "level_path"),
	}
	if doc.version != SCENARIO_FORMAT_VERSION do return {false, "unsupported scenario format"}
	if doc.story_path == "" || doc.level_path == "" do return {false, "scenario story_path and level_path are required"}
	tables := toml_tables(top, "scenarios"); doc.tests = make([]Scenario_Test, len(tables))
	for table, i in tables {
		enabled :=
			!scenario_datum_has_key(table, "enabled") ||
			toml_case_bool(
				table,
				"enabled",
			); step_tables := toml_tables(table, "steps"); steps := make([]Scenario_Step, len(step_tables))
		for step, j in step_tables do steps[j] = {
			action      = toml_case_string(step, "action"),
			value       = toml_case_string(step, "value"),
			state       = toml_case_string(step, "state"),
			outcome     = toml_case_string(step, "outcome"),
			equals      = toml_case_bool(step, "equals"),
			has_equals  = scenario_datum_has_key(step, "equals"),
			integer     = toml_case_int(step, "integer"),
			has_integer = scenario_datum_has_key(step, "integer"),
		}
		doc.tests[i] = {
			id          = toml_case_string(table, "id"),
			description = toml_case_string(table, "description"),
			enabled     = enabled,
			steps       = steps,
		}
		if doc.tests[i].id == "" do return {false, "scenario ID is required"}; if len(steps) == 0 do return {false, fmt.tprintf("scenario %s has no steps", doc.tests[i].id)}
	}
	if len(doc.tests) == 0 do return {false, "scenario file contains no scenarios"}; out^ = doc; return {true, "SCENARIOS LOADED"}
}

scenario_context_init :: proc(
	story_path, level_path: string,
	out: ^Scenario_Context,
) -> Validation {
	project: Story_Project; if loaded := load_story_project(story_path, &project); !loaded.ok do return loaded
	compiled := compile_story_project(
		&project,
	); story_project_destroy(&project); if !compiled.ok {message := compiled.message; story_compile_result_destroy(&compiled); return {false, message}}
	level: Level_Document; if loaded := level_load(level_path, &level); !loaded.ok {story_compile_result_destroy(&compiled); return loaded}
	result := Scenario_Context {
		compiled = compiled.story,
	}; compiled.story = {}; story_validation_destroy(&compiled.validation)
	if !story_spatial_registry_register(&result.registry, story_level_space(&level)) ||
	   !story_spatial_registry_register(
			   &result.registry,
			   story_city_space(),
		   ) {compiled_story_destroy(&result.compiled); story_spatial_registry_destroy(&result.registry); return {false, "scenario spaces could not be registered"}}
	spatial_validation := story_spatial_validate_project(
		&result.compiled.runtime,
		&result.registry,
	); if !spatial_validation.ok {message := len(spatial_validation.diagnostics) > 0 ? spatial_validation.diagnostics[0].message : "scenario spatial validation failed"; story_validation_destroy(&spatial_validation); compiled_story_destroy(&result.compiled); story_spatial_registry_destroy(&result.registry); return {false, message}}; story_validation_destroy(&spatial_validation)
	result.service = story_spatial_registry_service(
		&result.registry,
	); result.runtime = story_runtime_new(&result.compiled, &result.service); out^ = result
	// The context is returned by value, so repair the two internal pointers to
	// address the caller-owned copy rather than this stack-local assembly value.
	out.service = story_spatial_registry_service(
		&out.registry,
	); out.runtime.compiled = &out.compiled; out.runtime.spatial = &out.service
	return {true, "SCENARIO RUNTIME READY"}
}

scenario_context_destroy :: proc(s: ^Scenario_Context) {story_runtime_destroy(&s.runtime)
	story_spatial_registry_destroy(&s.registry)
	compiled_story_destroy(&s.compiled)
	s^ = {}}
scenario_mystery :: proc(s: ^Scenario_Context) -> ^Mystery_State {return(
		cast(^Mystery_State)story_runtime_capability_state(
			&s.runtime,
			"mystery",
			MYSTERY_DOMAIN_VERSION,
		) \
	)}
scenario_current_id :: proc(s: ^Scenario_Context) -> string {return s.runtime.current_node}
scenario_apply_current_metadata :: proc(s: ^Scenario_Context) {if s.runtime.current_node != "" do _ = mystery_apply_node_metadata(&s.compiled.runtime, scenario_mystery(s), s.runtime.current_node)}

scenario_step_succeeded :: proc(step: ^Story_Runtime_Step) -> bool {return(
		step.ok ||
		step.presented ||
		step.finished \
	)}
scenario_start :: proc(s: ^Scenario_Context, scene_id: string) -> bool {step :=
		story_runtime_enter_scene(&s.runtime, scene_id)
	return scenario_step_succeeded(&step)}
scenario_advance :: proc(s: ^Scenario_Context) -> bool {
	before :=
		s.runtime.current_node; scenario_apply_current_metadata(s); step := story_runtime_advance(&s.runtime); ok := scenario_step_succeeded(&step) || s.runtime.current_node != before
	node := story_runtime_node(
		&s.runtime,
	); if ok && node != nil && node.kind == .End {scenario_apply_current_metadata(s); step = story_runtime_advance(&s.runtime); ok = scenario_step_succeeded(&step)}
	if !ok do fmt.eprintln("scenario runtime ", s.runtime.current_scene, "/", s.runtime.current_node, ": ", step.message); return ok
}
scenario_choose :: proc(
	s: ^Scenario_Context,
	choice_id: string,
) -> bool {scenario_apply_current_metadata(s); step := story_runtime_choose(&s.runtime, choice_id)
	return scenario_step_succeeded(&step)}
scenario_force_check :: proc(
	s: ^Scenario_Context,
	wanted: bool,
) -> bool {scenario_apply_current_metadata(s); step := story_runtime_resolve(
		&s.runtime,
		wanted ? "success" : "failure",
	)
	return scenario_step_succeeded(&step)}

scenario_set_known :: proc(s: ^Scenario_Context, state, id: string) -> bool {
	state_data := scenario_mystery(s); switch state {case "clue":
		return mystery_acquire_evidence(&s.compiled.runtime, state_data, id); case "claim":
		return mystery_establish_claim(&s.compiled.runtime, state_data, id); case "topic":
		return mystery_string_set_add(&state_data.unlocked_topics, id)}; return false
}
scenario_investigate :: proc(
	s: ^Scenario_Context,
	id: string,
) -> bool {return mystery_acquire_evidence(&s.compiled.runtime, scenario_mystery(s), id)}
scenario_demonstrate :: proc(
	s: ^Scenario_Context,
	id: string,
) -> bool {return mystery_complete_demonstration(&s.compiled.runtime, scenario_mystery(s), id)}
scenario_accuse :: proc(s: ^Scenario_Context, id: string) -> bool {if story_entity_index(&s.compiled.runtime, id) < 0 do return false
	scenario_mystery(s).accusation_id = id
	return true}
scenario_support :: proc(
	s: ^Scenario_Context,
	pillar, id: string,
) -> bool {return mystery_select_theory_support(
		&s.compiled.runtime,
		scenario_mystery(s),
		pillar,
		id,
	)}
scenario_reveal :: proc(s: ^Scenario_Context) -> bool {s.outcome = mystery_evaluate_outcome(
		&s.compiled.runtime,
		scenario_mystery(s),
	)
	s.ending_id = mystery_ending_for_outcome(&s.compiled.runtime, s.outcome)
	return s.ending_id != ""}
scenario_timeout :: proc(s: ^Scenario_Context) -> bool {payload := mystery_payload(
		&s.compiled.runtime,
	)
	if payload == nil do return false
	for ending in payload.endings do if ending.ending_id == "night_overtakes_the_inquiry" || ending.trigger == "out_of_time" {s.ending_id = ending.ending_id; s.outcome = .Unresolved; return true}
	return false}

scenario_boolean_state :: proc(s: ^Scenario_Context, state, value: string) -> (bool, bool) {
	state_data := scenario_mystery(s); switch state {case "active":
		return !s.runtime.finished && s.runtime.current_node != "", true; case "clue":
		return mystery_string_set_has(state_data.acquired_evidence[:], value), true; case "claim":
		return mystery_string_set_has(state_data.established_claims[:], value), true; case "topic":
		return mystery_string_set_has(state_data.unlocked_topics[:], value),
			true}; return false, false
}

scenario_expect :: proc(s: ^Scenario_Context, step: Scenario_Step) -> (bool, string) {
	if step.state ==
	   "beat" {actual := scenario_current_id(s); return actual == step.value, fmt.tprintf("expected node %q, got %q", step.value, actual)}
	if step.state ==
	   "scene" {actual := s.runtime.current_scene; return actual == step.value, fmt.tprintf("expected scene %q, got %q", step.value, actual)}
	if step.state ==
	   "ap" {state_data := scenario_mystery(s); if !step.has_integer do return false, "AP expectation needs integer"; return state_data.action_budget_remaining == step.integer, fmt.tprintf("expected AP %d, got %d", step.integer, state_data.action_budget_remaining)}
	if step.state == "ending" do return s.ending_id == step.value, fmt.tprintf("expected ending %q, got %q", step.value, s.ending_id)
	if step.state ==
	   "outcome" {actual := campaign_outcome_text(s.outcome); return actual == step.value, fmt.tprintf("expected outcome %q, got %q", step.value, actual)}
	actual, known := scenario_boolean_state(
		s,
		step.state,
		step.value,
	); if !known do return false, fmt.tprintf("unknown expectation state %q or value %q", step.state, step.value); wanted := step.has_equals ? step.equals : true; return actual == wanted, fmt.tprintf("expected %s %q to be %v, got %v", step.state, step.value, wanted, actual)
}

scenario_execute_step :: proc(s: ^Scenario_Context, step: Scenario_Step) -> (bool, string) {
	switch step.action {
	case "start":
		if scenario_start(s, step.value) do return true, ""
		return false, fmt.tprintf("could not start scene %q", step.value)
	case "advance":
		if scenario_advance(s) do return true, ""
		return false, fmt.tprintf("cannot advance node %q", scenario_current_id(s))
	case "choose":
		if scenario_choose(s, step.value) do return true, ""
		return false, fmt.tprintf(
			"choice ID %q is unavailable at node %q",
			step.value,
			scenario_current_id(s),
		)
	case "check":
		wanted := step.outcome == "success"
		if step.outcome != "success" && step.outcome != "failure" do return false, "check outcome must be success or failure"
		if scenario_force_check(s, wanted) do return true, ""
		return false, fmt.tprintf(
			"could not resolve %s at node %q",
			step.outcome,
			scenario_current_id(s),
		)
	case "know":
		if scenario_set_known(s, step.state, step.value) do return true, ""
		return false, fmt.tprintf("could not establish %s %q", step.state, step.value)
	case "investigate":
		if scenario_investigate(s, step.value) do return true, ""
		return false, fmt.tprintf("could not investigate clue %q", step.value)
	case "demonstrate":
		if scenario_demonstrate(s, step.value) do return true, ""
		return false, fmt.tprintf("could not demonstrate question %q", step.value)
	case "accuse":
		if scenario_accuse(s, step.value) do return true, ""
		return false, fmt.tprintf("unknown suspect %q", step.value)
	case "support":
		if scenario_support(s, step.state, step.value) do return true, ""
		return false, fmt.tprintf("deduction %q does not support %s", step.value, step.state)
	case "reveal":
		if scenario_reveal(s) do return true, ""
		return false, "no authored ending matches the reconstruction outcome"
	case "timeout":
		if scenario_timeout(s) do return true, ""
		return false, "could not enter the authored out-of-time ending"
	case "expect":
		return scenario_expect(s, step)
	}; return false, fmt.tprintf("unknown scenario action %q", step.action)
}

run_scenario_file :: proc(path: string, only: string = "") -> Scenario_Run_Result {
	doc: Scenario_Document; loaded := scenario_load(path, &doc); if !loaded.ok do return {message = loaded.message}; result := Scenario_Run_Result {
		ok = true,
	}; matched := only == ""
	for test in doc.tests {if !test.enabled || (only != "" && test.id != only) do continue; matched = true; s: Scenario_Context; if ready := scenario_context_init(doc.story_path, doc.level_path, &s); !ready.ok do return {message = ready.message}; result.tests += 1
		for step, i in test.steps {result.steps += 1; ok, message := scenario_execute_step(&s, step); if !ok {scenario_context_destroy(&s); return {ok = false, tests = result.tests, steps = result.steps, message = fmt.tprintf("%s :: step %d (%s): %s", test.id, i + 1, step.action, message)}}}; scenario_context_destroy(&s)
	}; if !matched do return {message = fmt.tprintf("scenario %q was not found", only)}; result.message = fmt.tprintf("%d scenarios passed (%d steps)", result.tests, result.steps); return result
}

run_campaign_story_scenarios :: proc() -> Scenario_Run_Result {
	paths := [5]string {
		"assets/campaigns/the_marigold_circle.toml",
		"assets/campaigns/the_blackthorn_papers.toml",
		"assets/campaigns/one_more_question.toml",
		"assets/campaigns/bellwether_mysteries.toml",
		"assets/campaigns/unsorted_cases.toml",
	}
	result := Scenario_Run_Result {
		ok = true,
	}
	for path in paths {
		campaign: Campaign_Definition; if loaded := load_campaign_manifest(path, &campaign); !loaded.ok do return {message = loaded.message}
		for item in campaign.cases {
			s: Scenario_Context; if ready := scenario_context_init(item.story_path, item.level_path, &s); !ready.ok do return {message = fmt.tprintf("%s: %s", item.id, ready.message)}
			if len(s.compiled.runtime.scenes) ==
			   0 {scenario_context_destroy(&s); return {message = fmt.tprintf("%s has no authored scene", item.id)}}
			step := story_runtime_enter_scene(
				&s.runtime,
				s.compiled.runtime.scenes[0].id,
			); steps := 0
			for step.ok && !step.finished && steps < 512 {
				scenario_apply_current_metadata(&s); steps += 1
				switch step.expected {
				case .Choice:
					if step.choice_count == 0 {step = {
							message = "choice has no available route",
						}} else {step = story_runtime_choose(&s.runtime, step.choices[0].id)}
				case .Resolution:
					step = story_runtime_resolve(&s.runtime, "success")
				case .Signal:
					step = story_runtime_signal(&s.runtime, step.event_id)
				case .Advance, .None:
					step = story_runtime_advance(&s.runtime)
				}
			}
			if !step.ok ||
			   !step.finished {message := step.message; if steps >= 512 do message = "opening critical route exceeded 512 steps"; scenario_context_destroy(&s); return {message = fmt.tprintf("%s: %s", item.id, message)}}
			result.tests += 1; result.steps += steps; scenario_context_destroy(&s)
		}
	}
	result.message = fmt.tprintf(
		"%d campaign story critical routes passed (%d steps)",
		result.tests,
		result.steps,
	); return result
}

scenario_cli :: proc(args: []string) -> int {if len(args) == 0 {fmt.eprintln(
			"usage: chicago --scenario-test FILE [SCENARIO]",
		)
		return 2}
	if initialized := city_data_initialize(); !initialized.ok {fmt.eprintln(initialized.message)
		return 2}
	story_domains_initialize()
	only := len(args) > 1 ? args[1] : ""
	result := run_scenario_file(args[0], only)
	if !result.ok {fmt.eprintln("SCENARIO FAILED: ", result.message); return 1}
	fmt.println("SCENARIO PASS: ", result.message)
	return 0}
campaign_scenario_cli :: proc() -> int {if initialized := city_data_initialize();
	   !initialized.ok {fmt.eprintln(initialized.message); return 2}
	story_domains_initialize()
	result := run_campaign_story_scenarios()
	if !result.ok {fmt.eprintln("CAMPAIGN SCENARIO FAILED: ", result.message); return 1}
	fmt.println("CAMPAIGN SCENARIO PASS: ", result.message)
	return 0}

scenario_runner_self_test :: proc() {story_domains_initialize(); result := run_scenario_file(
		"assets/scenarios/the_torn_appointment.toml",
		"miriam_alibi_records_claim",
	)
	assert(result.ok)}
