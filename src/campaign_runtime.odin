package main

import "core:fmt"

campaign_clone :: proc(source: ^Campaign_Definition) -> Campaign_Definition {
	result := source^
	result.variables = nil; result.conditions = nil; result.effects = nil; result.cases = nil
	append(
		&result.variables,
		..source.variables[:],
	); append(&result.conditions, ..source.conditions[:]); append(&result.effects, ..source.effects[:]); append(&result.cases, ..source.cases[:])
	return result
}
campaign_destroy :: proc(doc: ^Campaign_Definition) {if doc == nil do return; delete(doc.variables)
	delete(doc.conditions)
	delete(doc.effects)
	delete(doc.cases)
	doc^ = {}}
campaign_history_clear_stack :: proc(
	items: ^[CAMPAIGN_HISTORY_LIMIT]Campaign_Definition,
	count: ^int,
) {for i in 0 ..< count^ do campaign_destroy(&items[i]); count^ = 0}
campaign_workspace_history_initialize :: proc() {h := &campaign_workspace.history
	campaign_history_clear_stack(&h.undo, &h.undo_count)
	campaign_history_clear_stack(&h.redo, &h.redo_count)
	campaign_destroy(&h.current)
	h.current = campaign_clone(&campaign_workspace.draft)
	h.ready = true}
campaign_workspace_history_record :: proc() {h := &campaign_workspace.history
	if !h.ready {campaign_workspace_history_initialize(); return}
	if h.undo_count ==
	   CAMPAIGN_HISTORY_LIMIT {campaign_destroy(&h.undo[0]); for i in 1 ..< h.undo_count do h.undo[i - 1] = h.undo[i]
		h.undo_count -= 1}
	h.undo[h.undo_count] = h.current
	h.undo_count += 1
	h.current = campaign_clone(&campaign_workspace.draft)
	campaign_history_clear_stack(&h.redo, &h.redo_count)}
campaign_workspace_history_restore :: proc(undo: bool) -> bool {h := &campaign_workspace.history
	source_count := undo ? &h.undo_count : &h.redo_count
	destination := undo ? &h.redo : &h.undo
	destination_count := undo ? &h.redo_count : &h.undo_count
	if source_count^ <= 0 do return false
	if destination_count^ ==
	   CAMPAIGN_HISTORY_LIMIT {campaign_destroy(&destination[0]); for i in 1 ..< destination_count^ do destination[i - 1] = destination[i]
		destination_count^ -= 1}
	destination[destination_count^] = campaign_clone(&campaign_workspace.draft)
	destination_count^ += 1
	campaign_destroy(&campaign_workspace.draft)
	source_count^ -= 1
	campaign_workspace.draft = (undo ? &h.undo : &h.redo)[source_count^]
	(undo ? &h.undo : &h.redo)[source_count^] = {}
	campaign_destroy(&h.current)
	h.current = campaign_clone(&campaign_workspace.draft)
	campaign_workspace.dirty = true
	campaign_workspace.diagnostics = campaign_validate(&campaign_workspace.draft)
	campaign_workspace.feedback = undo ? "CAMPAIGN UNDO" : "CAMPAIGN REDO"
	revision :=
		authoring_production_revisions(nil, nil, nil, &campaign_workspace.draft, nil)[int(Authoring_Validation_Domain.Campaign)] +
		1
	_ = authoring_invalidate_after_edit(.Campaign, revision)
	return true}
campaign_workspace_undo :: proc() -> bool {return campaign_workspace_history_restore(true)}
campaign_workspace_redo :: proc() -> bool {return campaign_workspace_history_restore(false)}

campaign_case_index :: proc(c: ^Campaign_Definition, id: string) -> int {for item, i in c.cases do if item.id == id do return i
	return -1}
campaign_first_unlocked_case :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
) -> int {for _, i in c.cases do if campaign_case_unlocked(c, p, i) do return i; return -1}
campaign_can_continue :: proc() -> bool {i := campaign_playthrough.active_case; return(
		i >= 0 &&
		i < len(campaign_document.cases) &&
		campaign_case_unlocked(&campaign_document, &campaign_playthrough, i) \
	)}
campaign_playthrough_unused :: proc(p: ^Campaign_Playthrough) -> bool {if p.completion_count != 0 do return false
	for result in p.results do if result.started || result.present do return false
	return true}
campaign_variable_index :: proc(c: ^Campaign_Definition, id: string) -> int {for item, i in c.variables do if item.id == id do return i
	return -1}
campaign_result_index :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	id: string,
) -> int {index := campaign_case_index(c, id); if index >= 0 && p.results[index].present do return index
	return -1}
campaign_enum_valid :: proc(variable: Campaign_Variable, value: string) -> bool {for i in 0 ..< clamp(variable.enum_value_count, 0, len(variable.enum_values)) do if variable.enum_values[i] == value do return true
	return false}

// Structural authoring helpers keep the flat campaign arrays internally
// consistent. They intentionally do not touch workspace selection or UI state.
campaign_variable_remove :: proc(c: ^Campaign_Definition, index: int) -> Validation {
	if c == nil || index < 0 || index >= len(c.variables) do return {false, "campaign variable index is invalid"}
	id := c.variables[index].id
	for node in c.conditions do if node.variable_id == id do return {false, fmt.tprintf("variable %s is still referenced by a condition", id)}
	for effect in c.effects do if effect.variable_id == id do return {false, fmt.tprintf("variable %s is still referenced by an effect", id)}
	ordered_remove(&c.variables, index); return {true, "CAMPAIGN VARIABLE REMOVED"}
}

campaign_variable_reorder :: proc(c: ^Campaign_Definition, from, to: int) -> bool {
	if c == nil || from < 0 || to < 0 || from >= len(c.variables) || to >= len(c.variables) do return false
	if from == to do return true
	item := c.variables[from]
	if from <
	   to {for i in from ..< to do c.variables[i] = c.variables[i + 1]} else {for i := from; i > to; i -= 1 do c.variables[i] = c.variables[i - 1]}
	c.variables[to] = item; return true
}

campaign_variable_conversion_boolean :: proc(variable: Campaign_Variable) -> bool {switch
	variable.kind {case .Boolean:
		return variable.default_boolean; case .Integer:
		return variable.default_integer != 0; case .Enumeration:
		return variable.default_enum != ""}
	return false}
campaign_variable_conversion_integer :: proc(variable: Campaign_Variable) -> int {switch
	variable.kind {case .Boolean:
		return variable.default_boolean ? 1 : 0; case .Integer:
		return variable.default_integer; case .Enumeration:
		for i in 0 ..< variable.enum_value_count do if variable.enum_values[i] == variable.default_enum do return i}
	return 0}

// Replacement carries the target type, defaults, and enum values. Its ID must
// remain stable. When repair_references is false, a type change with users is
// rejected; when true, condition/effect kinds and values are converted.
campaign_variable_convert :: proc(
	c: ^Campaign_Definition,
	index: int,
	replacement: Campaign_Variable,
	repair_references: bool,
) -> Validation {
	if c == nil || index < 0 || index >= len(c.variables) do return {false, "campaign variable index is invalid"}
	old :=
		c.variables[index]; if replacement.id != old.id do return {false, "campaign variable conversion cannot rename the variable"}
	if replacement.kind == .Enumeration && (replacement.enum_value_count <= 0 || !campaign_enum_valid(replacement, replacement.default_enum)) do return {false, "campaign enum conversion requires a valid default"}
	if !repair_references {
		if old.kind !=
		   replacement.kind {for node in c.conditions do if node.variable_id == old.id do return {false, "variable type conversion would invalidate a condition"}; for effect in c.effects do if effect.variable_id == old.id do return {false, "variable type conversion would invalidate an effect"}}
		if replacement.kind ==
		   .Enumeration {for node in c.conditions do if node.variable_id == old.id && !campaign_enum_valid(replacement, node.enum_value) do return {false, "enum conversion would invalidate a condition value"}; for effect in c.effects do if effect.variable_id == old.id && !campaign_enum_valid(replacement, effect.enum_value) do return {false, "enum conversion would invalidate an effect value"}}
	}
	for &node in c.conditions do if node.variable_id == old.id {
		switch replacement.kind {
		case .Boolean:
			if node.kind != .Boolean_Equals {node.kind = .Boolean_Equals; node.boolean_value = campaign_variable_conversion_boolean(old)}
		case .Integer:
			if node.kind != .Integer_Compare {node.kind = .Integer_Compare; node.integer_value = campaign_variable_conversion_integer(old); node.integer_comparison = .Equal}
		case .Enumeration:
			node.kind = .Enum_Equals; if !campaign_enum_valid(replacement, node.enum_value) do node.enum_value = replacement.default_enum
		}
	}
	for &effect in c.effects do if effect.variable_id == old.id {
		switch replacement.kind {
		case .Boolean:
			effect.kind = .Set_Boolean; effect.boolean_value = campaign_variable_conversion_boolean(old)
		case .Integer:
			if effect.kind != .Set_Integer && effect.kind != .Add_Integer do effect.kind = .Set_Integer; effect.integer_value = campaign_variable_conversion_integer(old)
		case .Enumeration:
			effect.kind = .Set_Enum; if !campaign_enum_valid(replacement, effect.enum_value) do effect.enum_value = replacement.default_enum
		}
	}
	c.variables[index] = replacement; return {true, "CAMPAIGN VARIABLE TYPE CONVERTED"}
}

campaign_effect_mapping_contains :: proc(
	mapping: Campaign_Outcome_Effects,
	index: int,
) -> bool {return(
		index >= mapping.first_effect &&
		index < mapping.first_effect + mapping.effect_count \
	)}

campaign_effect_remove :: proc(c: ^Campaign_Definition, index: int) -> bool {
	if c == nil || index < 0 || index >= len(c.effects) do return false
	for &item in c.cases do for mapping_index in 0 ..< item.outcome_effect_count {
		mapping := &item.outcome_effects[mapping_index]
		if index < mapping.first_effect {mapping.first_effect -= 1} else if campaign_effect_mapping_contains(mapping^, index) {mapping.effect_count -= 1}
	}
	ordered_remove(&c.effects, index); return true
}

campaign_effect_membership_equal :: proc(c: ^Campaign_Definition, a, b: int) -> bool {
	for item in c.cases do for mapping_index in 0 ..< item.outcome_effect_count {mapping := item.outcome_effects[mapping_index]; if campaign_effect_mapping_contains(mapping, a) != campaign_effect_mapping_contains(mapping, b) do return false}
	return true
}

// Moving across an outcome boundary would change which outcome owns an effect.
// Such moves are blocked; callers can remove and explicitly re-add instead.
campaign_effect_reorder :: proc(c: ^Campaign_Definition, from, to: int) -> Validation {
	if c == nil || from < 0 || to < 0 || from >= len(c.effects) || to >= len(c.effects) do return {false, "campaign effect index is invalid"}
	if from == to do return {true, "CAMPAIGN EFFECT ORDER UNCHANGED"}
	low, high :=
		min(from, to),
		max(
			from,
			to,
		); for i in low ..= high do if !campaign_effect_membership_equal(c, from, i) do return {false, "effect move crosses an outcome mapping boundary"}
	item :=
		c.effects[from]; if from < to {for i in from ..< to do c.effects[i] = c.effects[i + 1]} else {for i := from; i > to; i -= 1 do c.effects[i] = c.effects[i - 1]}; c.effects[to] = item
	return {true, "CAMPAIGN EFFECT ORDER UPDATED"}
}

campaign_condition_mark_subtree :: proc(
	c: ^Campaign_Definition,
	index: int,
	marked: []bool,
	depth: int,
) -> bool {
	if index < 0 || index >= len(c.conditions) || depth > CAMPAIGN_MAX_CONDITIONS do return false
	if marked[index] do return true; marked[index] = true; node := c.conditions[index]
	if node.kind == .All ||
	   node.kind == .Any ||
	   node.kind ==
		   .Not {if node.first_child < 0 || node.first_child + node.child_count > len(c.conditions) do return false; for child in node.first_child ..< node.first_child + node.child_count do if !campaign_condition_mark_subtree(c, child, marked, depth + 1) do return false}
	return true
}

campaign_condition_rebuild_without :: proc(c: ^Campaign_Definition, removed: []bool) -> bool {
	if len(removed) != len(c.conditions) do return false
	remap := make([]int, len(c.conditions)); defer delete(remap); for &value in remap do value = -1
	rebuilt := make(
		[dynamic]Campaign_Condition,
		0,
		len(c.conditions),
	); for node, old_index in c.conditions {if removed[old_index] do continue; remap[old_index] = len(rebuilt); append(&rebuilt, node)}
	for &node in rebuilt {if node.kind != .All && node.kind != .Any && node.kind != .Not do continue
		new_first := -1
		new_count := 0
		for old_child in node.first_child ..< node.first_child + node.child_count {if old_child < 0 || old_child >= len(remap) do return false
			if remap[old_child] < 0 do continue
			if new_first < 0 do new_first = remap[old_child]
			if remap[old_child] != new_first + new_count do return false
			new_count += 1}
		node.first_child = new_first
		node.child_count = new_count}
	for &item in c.cases {if item.condition_root < 0 do continue; if item.condition_root >= len(remap) do return false; item.condition_root = remap[item.condition_root]}
	delete(c.conditions); c.conditions = rebuilt; return true
}

campaign_condition_remove_subtree :: proc(c: ^Campaign_Definition, index: int) -> Validation {
	if c == nil || index < 0 || index >= len(c.conditions) do return {false, "campaign condition index is invalid"}
	removed := make(
		[]bool,
		len(c.conditions),
	); defer delete(removed); if !campaign_condition_mark_subtree(c, index, removed, 0) do return {false, "campaign condition subtree is malformed"}
	// A descendant shared from outside the subtree cannot be deleted safely.
	for node, parent in c.conditions {if removed[parent] || node.kind != .All && node.kind != .Any && node.kind != .Not do continue; for child in node.first_child ..< node.first_child + node.child_count do if child >= 0 && child < len(removed) && removed[child] {if child != index do return {false, "condition subtree contains a child shared by another parent"}; if node.kind == .Not || node.child_count <= 1 do return {false, "condition removal would leave its parent invalid"}}}
	for item in c.cases do if item.condition_root >= 0 && item.condition_root < len(removed) && removed[item.condition_root] && item.condition_root != index do return {false, "condition subtree is shared by another case"}
	if !campaign_condition_rebuild_without(c, removed) do return {false, "condition subtree could not be compacted"}
	return {true, "CAMPAIGN CONDITION SUBTREE REMOVED"}
}

campaign_condition_compact :: proc(c: ^Campaign_Definition) -> Validation {
	if c == nil do return {false, "campaign definition is missing"}; reachable := make([]bool, len(c.conditions)); defer delete(reachable)
	for item in c.cases do if item.condition_root >= 0 && !campaign_condition_mark_subtree(c, item.condition_root, reachable, 0) do return {false, "campaign condition tree is malformed"}
	removed := make(
		[]bool,
		len(c.conditions),
	); defer delete(removed); for value, i in reachable do removed[i] = !value
	if !campaign_condition_rebuild_without(c, removed) do return {false, "campaign conditions could not be compacted"}
	return {true, "CAMPAIGN CONDITIONS COMPACTED"}
}

campaign_reset_values :: proc(c: ^Campaign_Definition, p: ^Campaign_Playthrough) {
	for variable, i in c.variables {if i >= len(p.values) do break; p.values[i] = {
			kind          = variable.kind,
			boolean_value = variable.default_boolean,
			integer_value = variable.default_integer,
			enum_value    = variable.default_enum,
		}}
}

campaign_compare_integer :: proc(
	actual, expected: int,
	comparison: Campaign_Integer_Comparison,
) -> bool {switch comparison {case .Equal:
		return actual == expected; case .Not_Equal:
		return actual != expected; case .Less:
		return actual < expected; case .Less_Equal:
		return actual <= expected; case .Greater:
		return actual > expected; case .Greater_Equal:
		return actual >= expected}; return false}

campaign_evaluate_condition_at :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	index, depth: int,
) -> Campaign_Condition_Trace {
	if index < 0 || index >= len(c.conditions) do return {false, "missing condition"}
	if depth > CAMPAIGN_MAX_CONDITIONS do return {false, "condition nesting is too deep"}
	node := c.conditions[index]
	switch node.kind {
	case .Always:
		return {true, "always"}
	case .Never:
		return {false, "never"}
	case .All, .Any:
		if node.child_count <= 0 do return {false, "condition group is empty"}
		value := node.kind == .All; detail := ""
		for child in node.first_child ..< node.first_child + node.child_count {evaluated := campaign_evaluate_condition_at(c, p, child, depth + 1); if node.kind == .All {value = value && evaluated.value; if !evaluated.value && detail == "" do detail = evaluated.message} else {value = value || evaluated.value; if detail == "" do detail = evaluated.message; if evaluated.value do detail = evaluated.message}}
		if detail == "" do detail = node.kind == .All ? "all conditions" : "any condition"
		return {
			value,
			node.kind == .All ? (value ? "all conditions met" : fmt.tprintf("blocked by %s", detail)) : (value ? fmt.tprintf("met by %s", detail) : fmt.tprintf("none met; first check: %s", detail)),
		}
	case .Not:
		if node.child_count != 1 do return {false, "NOT requires one child"}
		child := campaign_evaluate_condition_at(
			c,
			p,
			node.first_child,
			depth + 1,
		); return {!child.value, fmt.tprintf("not (%s)", child.message)}
	case .Boolean_Equals, .Integer_Compare, .Enum_Equals:
		variable := campaign_variable_index(c, node.variable_id)
		if variable < 0 do return {false, fmt.tprintf("unknown variable %s", node.variable_id)}
		actual := p.values[variable]
		if node.kind == .Boolean_Equals do return {actual.boolean_value == node.boolean_value, fmt.tprintf("%s is %t", node.variable_id, node.boolean_value)}
		if node.kind == .Integer_Compare do return {campaign_compare_integer(actual.integer_value, node.integer_value, node.integer_comparison), fmt.tprintf("%s compared with %d", node.variable_id, node.integer_value)}
		return {
			actual.enum_value == node.enum_value,
			fmt.tprintf("%s is %s", node.variable_id, node.enum_value),
		}
	case .Case_Started, .Case_Completed, .Case_Outcome:
		case_index := campaign_case_index(c, node.case_id)
		if case_index < 0 do return {false, fmt.tprintf("unknown case %s", node.case_id)}
		result := p.results[case_index]
		if node.kind == .Case_Started do return {result.started || result.present, fmt.tprintf("%s started", node.case_id)}
		if node.kind == .Case_Completed do return {result.present, fmt.tprintf("%s completed", node.case_id)}
		return {
			result.present && result.outcome == node.outcome,
			fmt.tprintf("%s outcome", node.case_id),
		}
	}
	return {false, "unsupported condition"}
}

campaign_evaluate_condition :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	root: int,
) -> Campaign_Condition_Trace {return campaign_evaluate_condition_at(c, p, root, 0)}
campaign_case_unlocked :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	index: int,
) -> bool {if index < 0 || index >= len(c.cases) do return false; item := c.cases[index]
	if item.condition_root < 0 do return true
	return campaign_evaluate_condition(c, p, item.condition_root).value}

campaign_effect_range :: proc(item: Campaign_Case, outcome: Outcome) -> (int, int) {for 	i in 0 ..< clamp(item.outcome_effect_count, 0, len(item.outcome_effects)) {entry :=
			item.outcome_effects[i]
		if entry.outcome == outcome do return entry.first_effect, entry.effect_count}
	return 0, 0}
campaign_apply_effect :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	effect: Campaign_Effect,
) -> bool {
	index := campaign_variable_index(c, effect.variable_id); if index < 0 do return false
	value := &p.values[index]
	switch effect.kind {case .Set_Boolean:
		value.boolean_value = effect.boolean_value; case .Set_Integer:
		value.integer_value = effect.integer_value; case .Add_Integer:
		value.integer_value += effect.integer_value; case .Set_Enum:
		value.enum_value = effect.enum_value}
	return true
}

campaign_rebuild_values :: proc(c: ^Campaign_Definition, p: ^Campaign_Playthrough) {
	campaign_reset_values(c, p)
	// Completion sequence makes replay recalculation independent of case display order.
	for sequence in 1 ..< p.next_completion_sequence {for result, i in p.results do if result.present && result.completion_sequence == sequence {first, count := campaign_effect_range(c.cases[i], result.outcome); for effect_index in first ..< first + count do if effect_index >= 0 && effect_index < len(c.effects) do _ = campaign_apply_effect(c, p, c.effects[effect_index])}}
}

campaign_recalculate :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
) -> Campaign_Recalculation {
	result := Campaign_Recalculation {
		ok      = true,
		message = "CAMPAIGN RECALCULATED",
	}
	for pass in 0 ..< CAMPAIGN_RECALCULATE_LIMIT {
		result.passes = pass + 1; campaign_rebuild_values(c, p); changed := false
		for item, i in c.cases {if p.results[i].present && !campaign_case_unlocked(c, p, i) && item.invalid_result_policy == .Clear {result.cleared[result.cleared_count] = item.id; result.cleared_count += 1; p.results[i] = {}; p.completion_count -= 1; changed = true}}
		if !changed {campaign_rebuild_values(c, p); return result}
	}
	return {ok = false, message = "campaign result invalidation did not stabilize"}
}

campaign_apply_result :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	new_result: Campaign_Case_Result,
) -> Validation {
	result_record := new_result
	index := campaign_case_index(
		c,
		new_result.case_id,
	); if index < 0 do return {false, "result references an unknown campaign case"}
	existing := p.results[index]; item := c.cases[index]
	if new_result.case_content_version != "" && new_result.case_content_version != item.case_content_version do return {false, "case result version is incompatible with the campaign"}
	if existing.present && item.replay_mode != .Replace_Outcome do return item.replay_mode == .Effectless ? Validation{true, "REPLAY HAS NO CAMPAIGN EFFECT"} : Validation{false, "campaign case cannot replace its result"}
	if !existing.present && !campaign_case_unlocked(c, p, index) do return {false, "case result cannot be applied before the case unlocks"}
	before := p^
	if !existing.present {p.completion_count += 1; result_record.completion_sequence = p.next_completion_sequence; p.next_completion_sequence += 1} else do result_record.completion_sequence = existing.completion_sequence
	result_record.present =
		true; result_record.started = true; if result_record.case_content_version == "" do result_record.case_content_version = item.case_content_version; p.results[index] = result_record
	recalculated := campaign_recalculate(
		c,
		p,
	); if !recalculated.ok {p^ = before; return {false, recalculated.message}}
	return {true, "RESULT APPLIED"}
}

campaign_validate_condition :: proc(c: ^Campaign_Definition, index, depth: int) -> Validation {
	if index < 0 || index >= len(c.conditions) do return {false, "case has a missing unlock condition"}; if depth > CAMPAIGN_MAX_CONDITIONS do return {false, "campaign condition nesting is too deep"}; node := c.conditions[index]
	if node.kind == .All ||
	   node.kind ==
		   .Any {if node.child_count <= 0 do return {false, "campaign condition group is empty"}}
	if node.kind == .Not && node.child_count != 1 do return {false, "campaign NOT condition requires one child"}
	if node.kind == .All ||
	   node.kind == .Any ||
	   node.kind ==
		   .Not {if node.first_child < 0 || node.first_child + node.child_count > len(c.conditions) do return {false, "campaign condition child range is invalid"}; for child in node.first_child ..< node.first_child + node.child_count {valid := campaign_validate_condition(c, child, depth + 1); if !valid.ok do return valid}}
	if node.kind == .Boolean_Equals ||
	   node.kind == .Integer_Compare ||
	   node.kind ==
		   .Enum_Equals {variable_index := campaign_variable_index(c, node.variable_id); if variable_index < 0 do return {false, fmt.tprintf("condition references unknown variable %s", node.variable_id)}; variable := c.variables[variable_index]; expected: Campaign_Value_Kind = .Boolean; if node.kind == .Integer_Compare do expected = .Integer
		else if node.kind == .Enum_Equals do expected = .Enumeration; if variable.kind != expected do return {false, fmt.tprintf("condition type does not match variable %s", node.variable_id)}; if expected == .Enumeration && !campaign_enum_valid(variable, node.enum_value) do return {false, "condition uses an invalid enum value"}}
	if node.kind == .Case_Started ||
	   node.kind == .Case_Completed ||
	   node.kind ==
		   .Case_Outcome {if campaign_case_index(c, node.case_id) < 0 do return {false, fmt.tprintf("condition references unknown case %s", node.case_id)}}
	return {true, ""}
}

campaign_validate :: proc(c: ^Campaign_Definition) -> Validation {
	if c.version != "MysteryCampaign v2" do return {false, "unsupported campaign version"}
	if c.id == "" || c.title == "" || c.content_version == "" do return {false, "campaign metadata is incomplete"}
	if len(c.cases) == 0 || len(c.cases) > CAMPAIGN_MAX_CASES do return {false, "campaign requires one to sixteen cases"}
	if len(c.variables) > CAMPAIGN_MAX_VARIABLES || len(c.conditions) > CAMPAIGN_MAX_CONDITIONS || len(c.effects) > CAMPAIGN_MAX_EFFECTS do return {false, "campaign exceeds format limits"}
	for variable, i in c.variables {if variable.id == "" || variable.display_name == "" do return {false, "campaign variable metadata is incomplete"}; for prior in 0 ..< i do if c.variables[prior].id == variable.id do return {false, "campaign contains a duplicate variable ID"}; if variable.kind == .Enumeration {if variable.enum_value_count <= 0 || !campaign_enum_valid(variable, variable.default_enum) do return {false, "campaign enum default is invalid"}; for value_index in 0 ..< variable.enum_value_count {if variable.enum_values[value_index] == "" do return {false, "campaign enum value is empty"}; for prior in 0 ..< value_index do if variable.enum_values[prior] == variable.enum_values[value_index] do return {false, "campaign enum values must be unique"}}}}
	for item, i in c.cases {if item.id == "" || item.title == "" || item.story_path == "" || item.case_content_version == "" do return {false, "campaign case metadata is incomplete"}; for prior in 0 ..< i do if c.cases[prior].id == item.id do return {false, "campaign contains a duplicate case ID"}; if item.required == item.optional do return {false, "campaign case must be either required or optional"}; if item.condition_root >= 0 {valid := campaign_validate_condition(c, item.condition_root, 0); if !valid.ok do return valid}; for mapping_index in 0 ..< item.outcome_effect_count {mapping := item.outcome_effects[mapping_index]; if mapping.first_effect < 0 || mapping.effect_count < 0 || mapping.first_effect + mapping.effect_count > len(c.effects) do return {false, "campaign case effect range is invalid"}}}
	for effect in c.effects {variable_index := campaign_variable_index(c, effect.variable_id); if variable_index < 0 do return {false, fmt.tprintf("effect references unknown variable %s", effect.variable_id)}; variable := c.variables[variable_index]; expected: Campaign_Value_Kind = .Integer; if effect.kind == .Set_Boolean do expected = .Boolean
		else if effect.kind == .Set_Enum do expected = .Enumeration; if variable.kind != expected do return {false, "campaign effect type does not match its variable"}; if expected == .Enumeration && !campaign_enum_valid(variable, effect.enum_value) do return {false, "campaign effect uses an invalid enum value"}}
	probe := Campaign_Playthrough {
		campaign_id              = c.id,
		campaign_content_version = c.content_version,
		next_completion_sequence = 1,
	}; campaign_reset_values(
		c,
		&probe,
	); startable := false; for _, i in c.cases do if campaign_case_unlocked(c, &probe, i) do startable = true; if !startable do return {false, "campaign has no initially available case"}
	return {true, "CAMPAIGN VALID"}
}
