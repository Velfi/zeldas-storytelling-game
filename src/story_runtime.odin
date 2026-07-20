package main

STORY_MAX_SCENE_STACK :: 64

Story_Scene_Frame :: struct {
	scene_id, return_node: string,
}
Story_Capability_State :: struct {
	id, version: string,
	state:       rawptr,
}

Story_Runtime :: struct {
	compiled:                    ^Compiled_Story,
	spatial:                     ^Story_Spatial_Service,
	state:                       Story_State,
	capability_states:           [STORY_MAX_CAPABILITIES]Story_Capability_State,
	capability_state_count:      int,
	// Compatibility alias for the primary capability while callers migrate to
	// capability_states. It never owns the pointed-to state.
	domain_state:                rawptr,
	current_scene, current_node: string,
	stack:                       [STORY_MAX_SCENE_STACK]Story_Scene_Frame,
	stack_count:                 int,
	pending_input:               Story_Runtime_Input,
	finished:                    bool,
	condition_override_ids:      [64]string,
	condition_override_values:   [64]bool,
	condition_override_count:    int,
}

story_runtime_condition_eval :: proc(
	runtime: ^Story_Runtime,
	id: string,
) -> Story_Condition_Trace {for override_id, i in runtime.condition_override_ids[:runtime.condition_override_count] do if override_id == id do return {runtime.condition_override_values[i], "playtest debugger override"}
	index := story_condition_index(&runtime.compiled.runtime, id)
	if index >= 0 {condition := runtime.compiled.runtime.conditions[index]; if condition.kind ==
		   .Capability_State {for capability in runtime.compiled.runtime.capabilities do if capability.id == condition.entity_id {adapter := story_domain_find(capability.id, capability.version); for state in runtime.capability_states[:runtime.capability_state_count] do if state.id == capability.id && adapter != nil && adapter.condition_eval != nil do return adapter.condition_eval(state.state, condition.content_id)}
			return{false, "capability state is unavailable"}}}
	return story_condition_eval(
		&runtime.compiled.runtime,
		&runtime.state,
		index,
		spatial = runtime.spatial,
	)}
story_runtime_toggle_condition_override :: proc(runtime: ^Story_Runtime, id: string) -> bool {for override_id, i in runtime.condition_override_ids[:runtime.condition_override_count] do if override_id == id {runtime.condition_override_values[i] = !runtime.condition_override_values[i]; return true}
	if runtime.condition_override_count >= len(runtime.condition_override_ids) do return false
	trace := story_runtime_condition_eval(runtime, id)
	runtime.condition_override_ids[runtime.condition_override_count] = id
	runtime.condition_override_values[runtime.condition_override_count] = !trace.value
	runtime.condition_override_count += 1
	return true}

Story_Runtime_Step :: struct {
	ok, presented, finished:                                                         bool,
	message, scene_id, node_id, line_id, speaker_id, text:                           string,
	kind:                                                                            Story_Node_Kind,
	expected:                                                                        Story_Runtime_Input,
	choices:                                                                         [STORY_MAX_NODE_CHOICES]Story_Choice,
	choice_count:                                                                    int,
	ui, camera, actor, actor_mark, animation, summary, ending, domain_ref, event_id: string,
	duration, transition:                                                            f32,
	blocking:                                                                        bool,
	trace:                                                                           Story_Trace,
}

Story_Runtime_Input :: enum {
	None,
	Advance,
	Choice,
	Resolution,
	Signal,
}

Story_Runtime_Save :: struct {
	content_identity, schema_identity: u64,
	state:                             Story_State,
	capability_states:                 [STORY_MAX_CAPABILITIES]Story_Capability_State,
	capability_state_count:            int,
	current_scene, current_node:       string,
	stack:                             [STORY_MAX_SCENE_STACK]Story_Scene_Frame,
	stack_count:                       int,
	pending_input:                     Story_Runtime_Input,
	finished:                          bool,
}

story_runtime_capability_state :: proc(
	runtime: ^Story_Runtime,
	id, version: string,
) -> rawptr {if runtime == nil do return nil; for item in runtime.capability_states[:runtime.capability_state_count] do if item.id == id && item.version == version do return item.state
	return nil}

story_runtime_new :: proc(
	compiled: ^Compiled_Story,
	spatial: ^Story_Spatial_Service = nil,
) -> Story_Runtime {
	result := Story_Runtime {
		compiled = compiled,
		spatial  = spatial,
		state    = story_state_new(&compiled.runtime),
	}; for capability in compiled.runtime.capabilities {if result.capability_state_count >= len(result.capability_states) do break; adapter := story_domain_find(capability.id, capability.version); state: rawptr; if adapter != nil && adapter.state_create != nil do state = adapter.state_create(&compiled.runtime); result.capability_states[result.capability_state_count] = {capability.id, capability.version, state}; if result.domain_state == nil do result.domain_state = state; result.capability_state_count += 1}; return result
}

story_runtime_destroy :: proc(runtime: ^Story_Runtime) {
	for item in runtime.capability_states[:runtime.capability_state_count] {
		adapter := story_domain_find(item.id, item.version)
		if item.state != nil && adapter != nil && adapter.state_destroy != nil do adapter.state_destroy(item.state)
	}
	story_state_destroy(&runtime.state)
	runtime^ = {}}

story_runtime_node :: proc(runtime: ^Story_Runtime) -> ^Story_Node {
	if runtime.compiled == nil do return nil
	i := story_node_index(&runtime.compiled.runtime, runtime.current_scene, runtime.current_node)
	if i < 0 do return nil
	return &runtime.compiled.runtime.nodes[i]
}

story_runtime_enter_scene :: proc(
	runtime: ^Story_Runtime,
	scene_id: string,
	return_node: string = "",
) -> Story_Runtime_Step {
	if runtime.compiled == nil do return {message = "runtime has no compiled story"}
	i := story_scene_index(
		&runtime.compiled.runtime,
		scene_id,
	); if i < 0 do return {message = "scene does not exist"}
	entry :=
		runtime.compiled.runtime.scenes[i].entry_node; if entry == "" do return {message = "scene has no entry node"}
	if return_node != "" {
		if runtime.stack_count >= len(runtime.stack) do return {message = "scene stack limit exceeded"}
		runtime.stack[runtime.stack_count] = {
			scene_id    = runtime.current_scene,
			return_node = return_node,
		}; runtime.stack_count += 1
	}
	runtime.current_scene = scene_id; runtime.current_node = entry; runtime.finished = false
	return story_runtime_present(runtime)
}

story_runtime_present :: proc(runtime: ^Story_Runtime) -> Story_Runtime_Step {
	node := story_runtime_node(
		runtime,
	); if node == nil do return {message = "current node does not exist"}
	if node.condition_id != "" {
		condition := story_runtime_condition_eval(runtime, node.condition_id)
		if !condition.value do return {message = condition.explanation, scene_id = runtime.current_scene, node_id = runtime.current_node, kind = node.kind}
	}
	if node.kind ==
	   .Selector {for choice in node.choices[:node.choice_count] {if choice.condition_id != "" && !story_runtime_condition_eval(runtime, choice.condition_id).value do continue; runtime.current_node = choice.target; return story_runtime_present(runtime)}; return {message = "selector has no eligible authored route", scene_id = runtime.current_scene, node_id = node.id, kind = node.kind}}
	result := Story_Runtime_Step {
		ok         = true,
		presented  = true,
		scene_id   = runtime.current_scene,
		node_id    = node.id,
		line_id    = node.line_id,
		speaker_id = node.speaker_id,
		text       = node.text,
		kind       = node.kind,
		expected   = .Advance,
		ui         = node.ui,
		camera     = node.camera,
		actor      = node.actor,
		actor_mark = node.actor_mark,
		animation  = node.animation,
		summary    = node.summary,
		ending     = node.ending,
		domain_ref = node.domain_ref,
		event_id   = node.event_id,
		duration   = node.duration,
		transition = node.transition,
		blocking   = node.blocking,
	}
	#partial switch node.kind {case .Choice:
		result.expected = .Choice; case .Interaction:
		result.expected = .Resolution; case .Wait_Event:
		result.expected = .Signal; case:}
	for choice in node.choices[:node.choice_count] {if choice.condition_id != "" {condition := story_runtime_condition_eval(runtime, choice.condition_id); if !condition.value do continue}; if result.choice_count < len(result.choices) {result.choices[result.choice_count] = choice; result.choice_count += 1}}; runtime.pending_input = result.expected
	return result
}

story_runtime_follow :: proc(runtime: ^Story_Runtime, target: string) -> Story_Runtime_Step {
	if target == "" do return {message = "node has no continuation"}
	runtime.current_node = target
	return story_runtime_present(runtime)
}

story_runtime_apply_node_effects :: proc(
	runtime: ^Story_Runtime,
	node: ^Story_Node,
) -> (
	Story_Trace,
	bool,
	string,
) {
	if node == nil || node.effect_id_count == 0 do return {}, true, ""
	indices := make([]int, node.effect_id_count, context.temp_allocator)
	for i in 0 ..< node.effect_id_count do indices[i] = story_effect_index(&runtime.compiled.runtime, node.effect_ids[i])
	transaction := story_apply_transaction(
		&runtime.compiled.runtime,
		&runtime.state,
		indices,
		runtime.spatial,
	)
	return transaction.trace, transaction.ok, transaction.message
}

story_runtime_choose :: proc(runtime: ^Story_Runtime, choice_id: string) -> Story_Runtime_Step {
	node := story_runtime_node(
		runtime,
	); if node == nil || node.kind != .Choice do return {message = "runtime is not waiting for a choice"}
	for choice in node.choices[:node.choice_count] do if choice.id == choice_id {if choice.condition_id != "" {condition := story_runtime_condition_eval(runtime, choice.condition_id); if !condition.value do return {message = condition.explanation}}; trace, ok, message := story_runtime_apply_node_effects(runtime, node); if !ok do return {message = message}; result := story_runtime_follow(runtime, choice.target); result.trace = trace; return result}
	return {message = "choice does not exist"}
}

story_runtime_resolve :: proc(runtime: ^Story_Runtime, result_id: string) -> Story_Runtime_Step {
	node := story_runtime_node(
		runtime,
	); if node == nil || (node.kind != .Interaction && node.kind != .Check) do return {message = "runtime is not waiting for a resolution"}
	target := ""; switch result_id {case "success":
		target = node.success; case "failure":
		target = node.failure; case "cancel":
		target = node.cancel; case:
		return {message = "unknown resolution"}}
	trace, ok, message := story_runtime_apply_node_effects(
		runtime,
		node,
	); if !ok do return {message = message}; result := story_runtime_follow(runtime, target); result.trace = trace; return result
}

story_runtime_signal :: proc(runtime: ^Story_Runtime, event_id: string) -> Story_Runtime_Step {
	node := story_runtime_node(
		runtime,
	); if node == nil || node.kind != .Wait_Event do return {message = "runtime is not waiting for a signal"}
	if node.event_id != "" && node.event_id != event_id do return {message = "signal does not match the awaited event"}
	trace, ok, message := story_runtime_apply_node_effects(
		runtime,
		node,
	); if !ok do return {message = message}; result := story_runtime_follow(runtime, node.next); result.trace = trace; return result
}

story_runtime_save :: proc(runtime: ^Story_Runtime) -> Story_Runtime_Save {
	result := Story_Runtime_Save {
		content_identity = runtime.compiled.content_identity,
		schema_identity  = runtime.state.schema_identity,
		state            = story_state_clone(&runtime.state),
		current_scene    = runtime.current_scene,
		current_node     = runtime.current_node,
		stack            = runtime.stack,
		stack_count      = runtime.stack_count,
		pending_input    = runtime.pending_input,
		finished         = runtime.finished,
	}; for item in runtime.capability_states[:runtime.capability_state_count] {adapter := story_domain_find(item.id, item.version); state: rawptr; if item.state != nil && adapter != nil && adapter.state_clone != nil do state = adapter.state_clone(item.state); result.capability_states[result.capability_state_count] = {item.id, item.version, state}; result.capability_state_count += 1}; return result
}

story_runtime_save_destroy :: proc(save: ^Story_Runtime_Save) {
	for item in save.capability_states[:save.capability_state_count] {
		adapter := story_domain_find(item.id, item.version)
		if item.state != nil && adapter != nil && adapter.state_destroy != nil do adapter.state_destroy(item.state)
	}
	story_state_destroy(&save.state)
	save^ = {}}

story_runtime_restore :: proc(runtime: ^Story_Runtime, save: ^Story_Runtime_Save) -> bool {
	if runtime.compiled == nil || save.content_identity != runtime.compiled.content_identity || save.schema_identity != runtime.compiled.schema_identity do return false
	for item in runtime.capability_states[:runtime.capability_state_count] {adapter := story_domain_find(item.id, item.version); if item.state != nil && adapter != nil && adapter.state_destroy != nil do adapter.state_destroy(item.state)}; runtime.capability_state_count = 0; runtime.domain_state = nil; for item in save.capability_states[:save.capability_state_count] {adapter := story_domain_find(item.id, item.version); state: rawptr; if item.state != nil && adapter != nil && adapter.state_clone != nil do state = adapter.state_clone(item.state); runtime.capability_states[runtime.capability_state_count] = {item.id, item.version, state}; if runtime.domain_state == nil do runtime.domain_state = state; runtime.capability_state_count += 1}
	story_state_destroy(
		&runtime.state,
	); runtime.state = story_state_clone(&save.state); runtime.current_scene = save.current_scene; runtime.current_node = save.current_node; runtime.stack = save.stack; runtime.stack_count = save.stack_count; runtime.pending_input = save.pending_input; runtime.finished = save.finished; return true
}

story_runtime_advance :: proc(runtime: ^Story_Runtime) -> Story_Runtime_Step {
	node := story_runtime_node(
		runtime,
	); if node == nil do return {message = "current node does not exist"}
	result := Story_Runtime_Step {
		scene_id = runtime.current_scene,
		node_id  = node.id,
		kind     = node.kind,
	}
	trace, ok, message := story_runtime_apply_node_effects(
		runtime,
		node,
	); if !ok {result.message = message; return result}; result.trace = trace
	switch node.kind {
	case .Check:
		condition := story_runtime_condition_eval(runtime, node.condition_id)
		target := condition.value ? node.success : node.failure
		next := story_runtime_follow(runtime, target)
		next.trace = result.trace
		return next
	case .Choice:
		result.message = "runtime is waiting for a stable choice ID"; return result
	case .Subscene:
		next := story_runtime_enter_scene(runtime, node.subscene_id, node.next)
		next.trace = result.trace
		return next
	case .End:
		runtime.state.sequence += 1
		story_history_mark(
			&runtime.state.completed_scenes,
			runtime.current_scene,
			runtime.state.sequence,
		)
		if runtime.stack_count >
		   0 {runtime.stack_count -= 1; frame := runtime.stack[runtime.stack_count]
			runtime.current_scene = frame.scene_id
			runtime.current_node = frame.return_node
			next := story_runtime_present(runtime)
			next.trace = result.trace
			return next}
		runtime.finished = true
		runtime.pending_input = .None
		result.ok = true
		result.finished = true
		result.message = "story scene completed"
		return result
	case .Line, .Stage, .Interaction, .Effect, .Selector, .Objective, .Wait_Event:
		next := story_runtime_follow(runtime, node.next); next.trace = result.trace; return next
	}
	result.message = "unsupported scene node"; return result
}
