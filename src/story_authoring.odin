package main

import "core:fmt"

// Story authoring is deliberately independent of editor presentation.  The
// command and dependency APIs are suitable for the in-game editor, automation,
// and later domain adapters.
STORY_AUTHORING_HISTORY_LIMIT :: 64
STORY_AUTHORING_MAX_DEPENDENCIES :: 128

Story_Authoring_Record_Kind :: enum {
	Entity,
	Role,
	Variable,
	Fact,
	Proposition,
	Knowledge,
	Relationship,
	Event,
	Objective,
	Ending,
	Storylet_Group,
	Storylet,
	Invariant,
	Condition,
	Effect,
}
Story_Authoring_Command_Kind :: enum {
	Set_Metadata,
	Add_Expansion,
	Update_Expansion,
	Remove_Expansion,
	Reorder_Expansion,
	Add_Capability,
	Update_Capability,
	Remove_Capability,
	Reorder_Capability,
	Add_Entity,
	Update_Entity,
	Add_Variable,
	Update_Variable,
	Add_Proposition,
	Update_Proposition,
	Add,
	Update,
	Duplicate,
	Reorder,
	Rename,
	Remove,
	Insert_Condition_Child,
	Remove_Condition_Child,
	Reorder_Condition_Child,
	Insert_Effect_Reference,
	Remove_Effect_Reference,
	Reorder_Effect_Reference,
}

Story_Authoring_Metadata :: struct {
	id, title, creator, description, content_version, default_space_id: string,
}

Story_Authoring_Command :: struct {
	kind:           Story_Authoring_Command_Kind,
	record_kind:    Story_Authoring_Record_Kind,
	metadata:       Story_Authoring_Metadata,
	expansion:      Story_Expansion_Requirement,
	capability:     Story_Capability_Requirement,
	entity:         Story_Entity,
	role:           Story_Role,
	variable:       Story_Variable,
	fact:           Story_Fact,
	proposition:    Story_Proposition,
	knowledge:      Story_Knowledge,
	relationship:   Story_Relationship,
	event:          Story_Event,
	objective:      Story_Objective,
	ending:         Story_Ending,
	storylet_group: Story_Storylet_Group,
	storylet:       Story_Storylet,
	invariant:      Story_Invariant,
	condition:      Story_Condition,
	effect:         Story_Effect,
	id, new_id:     string,
	owner_id:       string,
	from, to:       int,
}

story_authoring_clone_capability :: proc(
	value: Story_Capability_Requirement,
) -> (
	Story_Capability_Requirement,
	bool,
) {
	copy := value; copy.payload = nil
	adapter := story_domain_find(value.id, value.version)
	if adapter == nil || value.id == STORY_DOMAIN_CORE do return {}, false
	if value.payload != nil {
		if adapter.clone == nil do return {}, false
		copy.payload = adapter.clone(value.payload)
		if copy.payload == nil do return {}, false
	}
	return copy, true
}

story_authoring_destroy_capability_payload :: proc(value: ^Story_Capability_Requirement) {
	if value == nil || value.payload == nil do return
	adapter := story_domain_find(value.id, value.version)
	if adapter != nil && adapter.destroy != nil do adapter.destroy(value.payload)
	value.payload = nil
}

Story_Authoring_Dependency :: struct {
	record_kind, record_id, field: string,
}
Story_Authoring_Dependency_Preview :: struct {
	kind:             Story_Authoring_Record_Kind,
	id:               string,
	dependencies:     [STORY_AUTHORING_MAX_DEPENDENCIES]Story_Authoring_Dependency,
	dependency_count: int,
	truncated:        bool,
}

Story_Authoring_Result :: struct {
	ok:         bool,
	message:    string,
	revision:   u64,
	validation: Story_Validation,
	blocked_by: Story_Authoring_Dependency_Preview,
}

Story_Authoring_History :: struct {
	undo: [dynamic]Story_Project,
	redo: [dynamic]Story_Project,
}

story_authoring_valid_id :: proc(id: string) -> bool {
	if len(id) == 0 do return false
	for c in id {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_' || c == '-' || c == '.' || c == ':') do return false
	}
	return true
}

story_authoring_record_exists :: proc(
	project: ^Story_Project,
	kind: Story_Authoring_Record_Kind,
	id: string,
) -> bool {
	switch kind {
	case .Entity:
		return story_entity_index(project, id) >= 0
	case .Role:
		for item in project.roles do if item.id == id do return true
	case .Variable:
		return story_variable_index(project, id) >= 0
	case .Fact:
		for item in project.facts do if item.id == id do return true
	case .Proposition:
		return story_proposition_index(project, id) >= 0
	case .Knowledge:
		for item in project.initial_knowledge do if fmt.tprintf("%s/%s", item.actor_id, item.proposition_id) == id do return true
	case .Relationship:
		for item in project.relationships do if item.id == id do return true
	case .Event:
		for item in project.events do if item.id == id do return true
	case .Objective:
		for item in project.objectives do if item.id == id do return true
	case .Ending:
		for item in project.endings do if item.id == id do return true
	case .Storylet_Group:
		for item in project.storylet_groups do if item.id == id do return true
	case .Storylet:
		for item in project.storylets do if item.id == id do return true
	case .Invariant:
		for item in project.invariants do if item.id == id do return true
	case .Condition:
		return story_condition_index(project, id) >= 0
	case .Effect:
		return story_effect_index(project, id) >= 0
	}
	return false
}

story_authoring_record_id :: proc(command: ^Story_Authoring_Command) -> string {switch
	command.record_kind {case .Entity:
		return command.entity.id; case .Role:
		return command.role.id; case .Variable:
		return command.variable.id; case .Fact:
		return command.fact.id; case .Proposition:
		return command.proposition.id; case .Knowledge:
		return fmt.tprintf(
			"%s/%s",
			command.knowledge.actor_id,
			command.knowledge.proposition_id,
		); case .Relationship:
		return command.relationship.id; case .Event:
		return command.event.id; case .Objective:
		return command.objective.id; case .Ending:
		return command.ending.id; case .Storylet_Group:
		return command.storylet_group.id; case .Storylet:
		return command.storylet.id; case .Invariant:
		return command.invariant.id; case .Condition:
		return command.condition.id; case .Effect:
		return command.effect.id}
	return ""}

story_authoring_dependency_add :: proc(
	preview: ^Story_Authoring_Dependency_Preview,
	kind, id, field: string,
) {
	if preview.dependency_count >= len(preview.dependencies) {preview.truncated = true; return}
	preview.dependencies[preview.dependency_count] = {kind, id, field}
	preview.dependency_count += 1
}

story_authoring_dependency_preview :: proc(
	project: ^Story_Project,
	kind: Story_Authoring_Record_Kind,
	id: string,
) -> Story_Authoring_Dependency_Preview {
	result := Story_Authoring_Dependency_Preview {
		kind = kind,
		id   = id,
	}
	if project == nil || id == "" do return result
	switch kind {
	case .Entity:
		for item in project.entities {if item.id != id && item.owner_id == id do story_authoring_dependency_add(&result, "entity", item.id, "owner_id"); if item.id != id && item.initial_container_id == id do story_authoring_dependency_add(&result, "entity", item.id, "initial_container_id")}
		for item in project.initial_knowledge do if item.actor_id == id do story_authoring_dependency_add(&result, "knowledge", fmt.tprintf("%s/%s", item.actor_id, item.proposition_id), "actor_id")
		for item in project.relationships {if item.source_id == id do story_authoring_dependency_add(&result, "relationship", item.id, "source_id"); if item.target_id == id do story_authoring_dependency_add(&result, "relationship", item.id, "target_id")}
		for item in project.events {if item.subject_id == id do story_authoring_dependency_add(&result, "event", item.id, "subject_id"); if item.object_id == id do story_authoring_dependency_add(&result, "event", item.id, "object_id"); if item.location_id == id do story_authoring_dependency_add(&result, "event", item.id, "location_id"); for witness_i in 0 ..< item.witness_count do if item.witnesses[witness_i] == id do story_authoring_dependency_add(&result, "event", item.id, "witnesses")}
		for item in project.conditions {if item.entity_id == id do story_authoring_dependency_add(&result, "condition", item.id, "entity_id"); if item.other_entity_id == id do story_authoring_dependency_add(&result, "condition", item.id, "other_entity_id"); if item.value.kind == .Entity && item.value.text_value == id do story_authoring_dependency_add(&result, "condition", item.id, "value")}
		for item in project.effects {if item.actor_id == id do story_authoring_dependency_add(&result, "effect", item.id, "actor_id"); if item.other_actor_id == id do story_authoring_dependency_add(&result, "effect", item.id, "other_actor_id"); if item.value.kind == .Entity && item.value.text_value == id do story_authoring_dependency_add(&result, "effect", item.id, "value")}
		for item in project.scenes do if item.bound_entity == id do story_authoring_dependency_add(&result, "scene", item.id, "bound_entity")
		for item in project.nodes {if item.speaker_id == id do story_authoring_dependency_add(&result, "node", item.id, "speaker_id"); if item.actor == id do story_authoring_dependency_add(&result, "node", item.id, "actor")}
	case .Role:
		for item in project.entities do for role_i in 0 ..< item.role_count do if item.roles[role_i] == id do story_authoring_dependency_add(&result, "entity", item.id, "roles")
		for item in project.conditions do if item.kind == .Entity_Has_Role && item.text_value == id do story_authoring_dependency_add(&result, "condition", item.id, "text_value")
	case .Variable:
		for item in project.facts do if item.variable_id == id do story_authoring_dependency_add(&result, "fact", item.id, "variable_id")
		for item in project.relationships do if item.variable_id == id do story_authoring_dependency_add(&result, "relationship", item.id, "variable_id")
		for item in project.conditions do if item.variable_id == id do story_authoring_dependency_add(&result, "condition", item.id, "variable_id")
		for item in project.effects do if item.variable_id == id do story_authoring_dependency_add(&result, "effect", item.id, "variable_id")
	case .Fact:
	case .Proposition:
		for item in project.facts do if item.proposition == id do story_authoring_dependency_add(&result, "fact", item.id, "proposition")
		for item in project.initial_knowledge do if item.proposition_id == id do story_authoring_dependency_add(&result, "knowledge", fmt.tprintf("%s/%s", item.actor_id, item.proposition_id), "proposition_id")
		for item in project.conditions do if item.proposition_id == id do story_authoring_dependency_add(&result, "condition", item.id, "proposition_id")
		for item in project.effects do if item.proposition_id == id do story_authoring_dependency_add(&result, "effect", item.id, "proposition_id")
	case .Knowledge:
	case .Relationship:
	case .Event:
		for item in project.conditions do if item.event_id == id do story_authoring_dependency_add(&result, "condition", item.id, "event_id")
		for item in project.effects do if item.event_id == id do story_authoring_dependency_add(&result, "effect", item.id, "event_id")
		for item in project.nodes do if item.event_id == id do story_authoring_dependency_add(&result, "node", item.id, "event_id")
	case .Objective:
		for item in project.conditions do if item.objective_id == id do story_authoring_dependency_add(&result, "condition", item.id, "objective_id")
		for item in project.effects do if item.objective_id == id do story_authoring_dependency_add(&result, "effect", item.id, "objective_id")
	case .Ending:
		for item in project.nodes do if item.ending == id do story_authoring_dependency_add(&result, "node", item.id, "ending")
	case .Storylet_Group:
		for item in project.storylets do if item.group == id do story_authoring_dependency_add(&result, "storylet", item.id, "group")
	case .Storylet:
		for item in project.conditions do if item.kind == .Storylet_Seen && item.content_id == id do story_authoring_dependency_add(&result, "condition", item.id, "content_id")
		for item in project.effects do if item.kind == .Mark_Storylet && item.content_id == id do story_authoring_dependency_add(&result, "effect", item.id, "content_id")
	case .Invariant:
	case .Condition:
		for item in project.conditions do for child_i in 0 ..< item.child_id_count do if item.child_ids[child_i] == id do story_authoring_dependency_add(&result, "condition", item.id, "child_ids")
		for item in project.objectives {if item.completion_condition_id == id do story_authoring_dependency_add(&result, "objective", item.id, "completion_condition_id"); if item.failure_condition_id == id do story_authoring_dependency_add(&result, "objective", item.id, "failure_condition_id")}
		for item in project.nodes {if item.condition_id == id do story_authoring_dependency_add(&result, "node", item.id, "condition_id"); for choice_i in 0 ..< item.choice_count do if item.choices[choice_i].condition_id == id do story_authoring_dependency_add(&result, "node", item.id, "choice.condition_id")}
		for item in project.storylets do for child_i in 0 ..< item.condition_count do if item.condition_ids[child_i] == id do story_authoring_dependency_add(&result, "storylet", item.id, "condition_ids")
		for item in project.endings do if item.condition_id == id do story_authoring_dependency_add(&result, "ending", item.id, "condition_id")
		for item in project.invariants do if item.condition_id == id do story_authoring_dependency_add(&result, "invariant", item.id, "condition_id")
	case .Effect:
		for item in project.nodes do for effect_i in 0 ..< item.effect_id_count do if item.effect_ids[effect_i] == id do story_authoring_dependency_add(&result, "node", item.id, "effect_ids")
		for item in project.storylets do for effect_i in 0 ..< item.effect_count do if item.effect_ids[effect_i] == id do story_authoring_dependency_add(&result, "storylet", item.id, "effect_ids")
	}
	mystery_authoring_core_dependency_preview(project, kind, id, &result)
	return result
}

story_authoring_replace_id :: proc(
	project: ^Story_Project,
	kind: Story_Authoring_Record_Kind,
	old, new: string,
) -> bool {
	if !story_authoring_valid_id(new) || old == new || story_authoring_record_exists(project, kind, new) do return false
	switch kind {
	case .Entity:
		index := story_entity_index(project, old); if index < 0 do return false
		project.entities[index].id = new
		for &item in project.entities {if item.owner_id == old do item.owner_id = new; if item.initial_container_id == old do item.initial_container_id = new}
		for &item in project.initial_knowledge do if item.actor_id == old do item.actor_id = new
		for &item in project.relationships {if item.source_id == old do item.source_id = new; if item.target_id == old do item.target_id = new}
		for &item in project.events {if item.subject_id == old do item.subject_id = new; if item.object_id == old do item.object_id = new; if item.location_id == old do item.location_id = new; for &witness in item.witnesses[:item.witness_count] do if witness == old do witness = new}
		for &item in project.conditions {if item.entity_id == old do item.entity_id = new; if item.other_entity_id == old do item.other_entity_id = new; if item.value.kind == .Entity && item.value.text_value == old do item.value.text_value = new}
		for &item in project.effects {if item.actor_id == old do item.actor_id = new; if item.other_actor_id == old do item.other_actor_id = new; if item.value.kind == .Entity && item.value.text_value == old do item.value.text_value = new}
		for &item in project.scenes do if item.bound_entity == old do item.bound_entity = new
		for &item in project.nodes {if item.speaker_id == old do item.speaker_id = new; if item.actor == old do item.actor = new}
	case .Role:
		index := -1; for item, i in project.roles do if item.id == old do index = i
		if index < 0 do return false
		project.roles[index].id = new
		for &item in project.entities do for &role in item.roles[:item.role_count] do if role == old do role = new
		for &item in project.conditions do if item.kind == .Entity_Has_Role && item.text_value == old do item.text_value = new
	case .Variable:
		index := story_variable_index(project, old); if index < 0 do return false
		project.variables[index].id = new
		for &item in project.facts do if item.variable_id == old do item.variable_id = new
		for &item in project.relationships do if item.variable_id == old do item.variable_id = new
		for &item in project.conditions do if item.variable_id == old do item.variable_id = new
		for &item in project.effects do if item.variable_id == old do item.variable_id = new
	case .Fact:
		index := -1; for item, i in project.facts do if item.id == old do index = i
		if index < 0 do return false
		project.facts[index].id = new
	case .Proposition:
		index := story_proposition_index(project, old); if index < 0 do return false
		project.propositions[index].id = new
		for &item in project.facts do if item.proposition == old do item.proposition = new
		for &item in project.initial_knowledge do if item.proposition_id == old do item.proposition_id = new
		for &item in project.conditions do if item.proposition_id == old do item.proposition_id = new
		for &item in project.effects do if item.proposition_id == old do item.proposition_id = new
	case .Knowledge:
		return false
	case .Relationship:
		index := -1; for item, i in project.relationships do if item.id == old do index = i
		if index < 0 do return false
		project.relationships[index].id = new
	case .Event:
		index := -1; for item, i in project.events do if item.id == old do index = i
		if index < 0 do return false
		project.events[index].id = new
		for &item in project.conditions do if item.event_id == old do item.event_id = new
		for &item in project.effects do if item.event_id == old do item.event_id = new
		for &item in project.nodes do if item.event_id == old do item.event_id = new
	case .Objective:
		index := -1; for item, i in project.objectives do if item.id == old do index = i
		if index < 0 do return false
		project.objectives[index].id = new
		for &item in project.conditions do if item.objective_id == old do item.objective_id = new
		for &item in project.effects do if item.objective_id == old do item.objective_id = new
	case .Ending:
		index := -1; for item, i in project.endings do if item.id == old do index = i
		if index < 0 do return false
		project.endings[index].id = new
		for &item in project.nodes do if item.ending == old do item.ending = new
	case .Storylet_Group:
		index := -1; for item, i in project.storylet_groups do if item.id == old do index = i
		if index < 0 do return false
		project.storylet_groups[index].id = new
		for &item in project.storylets do if item.group == old do item.group = new
	case .Storylet:
		index := -1; for item, i in project.storylets do if item.id == old do index = i
		if index < 0 do return false
		project.storylets[index].id = new
		for &item in project.conditions do if item.kind == .Storylet_Seen && item.content_id == old do item.content_id = new
		for &item in project.effects do if item.kind == .Mark_Storylet && item.content_id == old do item.content_id = new
	case .Invariant:
		index := -1; for item, i in project.invariants do if item.id == old do index = i
		if index < 0 do return false
		project.invariants[index].id = new
	case .Condition:
		index := story_condition_index(project, old); if index < 0 do return false
		project.conditions[index].id = new
		for &item in project.conditions do for &child in item.child_ids[:item.child_id_count] do if child == old do child = new
		for &item in project.objectives {
			if item.completion_condition_id == old do item.completion_condition_id = new
			if item.failure_condition_id == old do item.failure_condition_id = new}
		for &item in project.nodes {
			if item.condition_id == old do item.condition_id = new
			for &choice in item.choices[:item.choice_count] do if choice.condition_id == old do choice.condition_id = new
		}
		for &item in project.storylets do for &child in item.condition_ids[:item.condition_count] do if child == old do child = new
		for &item in project.endings do if item.condition_id == old do item.condition_id = new
		for &item in project.invariants do if item.condition_id == old do item.condition_id = new
	case .Effect:
		index := story_effect_index(project, old); if index < 0 do return false
		project.effects[index].id = new
		for &item in project.nodes do for &effect in item.effect_ids[:item.effect_id_count] do if effect == old do effect = new
		for &item in project.storylets do for &effect in item.effect_ids[:item.effect_count] do if effect == old do effect = new
	}
	mystery_authoring_rename_core_refs(project, kind, old, new)
	return true
}

story_authoring_remove_unreferenced :: proc(
	project: ^Story_Project,
	kind: Story_Authoring_Record_Kind,
	id: string,
) -> bool {
	preview := story_authoring_dependency_preview(
		project,
		kind,
		id,
	); if preview.dependency_count > 0 || preview.truncated do return false
	switch kind {
	case .Entity:
		index := story_entity_index(project, id); if index < 0 do return false
		ordered_remove(&project.entities, index)
	case .Role:
		for item, i in project.roles do if item.id == id {ordered_remove(&project.roles, i); return true}
		return false
	case .Variable:
		index := story_variable_index(project, id); if index < 0 do return false
		ordered_remove(&project.variables, index)
	case .Fact:
		for item, i in project.facts do if item.id == id {ordered_remove(&project.facts, i); return true}
		return false
	case .Proposition:
		index := story_proposition_index(project, id); if index < 0 do return false
		ordered_remove(&project.propositions, index)
	case .Knowledge:
		for item, i in project.initial_knowledge do if fmt.tprintf("%s/%s", item.actor_id, item.proposition_id) == id {ordered_remove(&project.initial_knowledge, i); return true}
		return false
	case .Relationship:
		for item, i in project.relationships do if item.id == id {ordered_remove(&project.relationships, i); return true}
		return false
	case .Event:
		for item, i in project.events do if item.id == id {ordered_remove(&project.events, i); return true}
		return false
	case .Objective:
		for item, i in project.objectives do if item.id == id {ordered_remove(&project.objectives, i); return true}
		return false
	case .Ending:
		for item, i in project.endings do if item.id == id {ordered_remove(&project.endings, i); return true}
		return false
	case .Storylet_Group:
		for item, i in project.storylet_groups do if item.id == id {ordered_remove(&project.storylet_groups, i); return true}
		return false
	case .Storylet:
		for item, i in project.storylets do if item.id == id {ordered_remove(&project.storylets, i); return true}
		return false
	case .Invariant:
		for item, i in project.invariants do if item.id == id {ordered_remove(&project.invariants, i); return true}
		return false
	case .Condition:
		index := story_condition_index(project, id); if index < 0 do return false
		ordered_remove(&project.conditions, index)
	case .Effect:
		index := story_effect_index(project, id); if index < 0 do return false
		ordered_remove(&project.effects, index)
	}
	return true
}

story_authoring_reorder :: proc(values: ^[dynamic]$T, from, to: int) -> bool {if from < 0 || to < 0 || from >= len(values^) || to >= len(values^) do return false
	item := values^[from]
	if from < to {for i in from ..< to do values^[i] = values^[i + 1]}
	else {for i := from; i > to; i -= 1 do values^[i] = values^[i - 1]}
	values^[to] = item
	return true}

story_authoring_apply_record :: proc(
	project: ^Story_Project,
	command: ^Story_Authoring_Command,
	update: bool,
) -> bool {
	core := Story_Command {
		kind = update ? .Update_Record : .Add_Record,
	}
	switch command.record_kind {
	case .Entity:
		core.record_kind = .Entity; core.entity = command.entity
	case .Role:
		core.record_kind = .Role; core.role = command.role
	case .Variable:
		core.record_kind = .Variable; core.variable = command.variable
	case .Fact:
		core.record_kind = .Fact; core.fact = command.fact
	case .Proposition:
		core.record_kind = .Proposition; core.proposition = command.proposition
	case .Knowledge:
		core.record_kind = .Knowledge; core.knowledge = command.knowledge
	case .Relationship:
		core.record_kind = .Relationship; core.relationship = command.relationship
	case .Event:
		core.record_kind = .Event; core.event = command.event
	case .Objective:
		core.record_kind = .Objective; core.objective = command.objective
	case .Ending:
		core.record_kind = .Ending; core.ending = command.ending
	case .Storylet_Group:
		core.record_kind = .Storylet_Group; core.storylet_group = command.storylet_group
	case .Storylet:
		core.record_kind = .Storylet; core.storylet = command.storylet
	case .Invariant:
		core.record_kind = .Invariant; core.invariant = command.invariant
	case .Condition:
		if !story_authoring_valid_id(command.condition.id) do return false
		index := story_condition_index(project, command.condition.id)
		if update {if index < 0 do return false; project.conditions[index] = command.condition} else {if index >= 0 do return false; append(&project.conditions, command.condition)}
		return true
	case .Effect:
		if !story_authoring_valid_id(command.effect.id) do return false
		index := story_effect_index(project, command.effect.id)
		if update {if index < 0 do return false; project.effects[index] = command.effect} else {if index >= 0 do return false; append(&project.effects, command.effect)}
		return true
	}
	return story_apply_record(project, &core, update)
}

story_authoring_reorder_record :: proc(
	project: ^Story_Project,
	kind: Story_Authoring_Record_Kind,
	from, to: int,
) -> bool {switch kind {case .Entity:
		return story_authoring_reorder(&project.entities, from, to); case .Role:
		return story_authoring_reorder(&project.roles, from, to); case .Variable:
		return story_authoring_reorder(&project.variables, from, to); case .Fact:
		return story_authoring_reorder(&project.facts, from, to); case .Proposition:
		return story_authoring_reorder(&project.propositions, from, to); case .Knowledge:
		return story_authoring_reorder(&project.initial_knowledge, from, to); case .Relationship:
		return story_authoring_reorder(&project.relationships, from, to); case .Event:
		return story_authoring_reorder(&project.events, from, to); case .Objective:
		return story_authoring_reorder(&project.objectives, from, to); case .Ending:
		return story_authoring_reorder(&project.endings, from, to); case .Storylet_Group:
		return story_authoring_reorder(&project.storylet_groups, from, to); case .Storylet:
		return story_authoring_reorder(&project.storylets, from, to); case .Invariant:
		return story_authoring_reorder(&project.invariants, from, to); case .Condition:
		return story_authoring_reorder(&project.conditions, from, to); case .Effect:
		return story_authoring_reorder(&project.effects, from, to)}; return false}

story_authoring_condition_child :: proc(
	project: ^Story_Project,
	command: ^Story_Authoring_Command,
) -> bool {index := story_condition_index(project, command.owner_id); if index < 0 do return false
	parent := &project.conditions[index]
	if parent.kind != .All && parent.kind != .Any && parent.kind != .Not do return false
	#partial switch command.kind {case .Insert_Condition_Child:
		if parent.child_id_count >= len(parent.child_ids) || story_condition_index(project, command.id) < 0 do return false
		at := clamp(command.to, 0, parent.child_id_count)
		for i := parent.child_id_count; i > at; i -= 1 do parent.child_ids[i] = parent.child_ids[i - 1]
		parent.child_ids[at] = command.id
		parent.child_id_count += 1
		return true; case .Remove_Condition_Child:
		if command.from < 0 || command.from >= parent.child_id_count do return false
		for i in command.from + 1 ..< parent.child_id_count do parent.child_ids[i - 1] = parent.child_ids[i]
		parent.child_id_count -= 1
		parent.child_ids[parent.child_id_count] = ""
		return true; case .Reorder_Condition_Child:
		if command.from < 0 || command.to < 0 || command.from >= parent.child_id_count || command.to >= parent.child_id_count do return false
		item := parent.child_ids[command.from]
		if command.from <
		   command.to {for i in command.from ..< command.to do parent.child_ids[i] = parent.child_ids[i + 1]} else {for i := command.from; i > command.to; i -= 1 do parent.child_ids[i] = parent.child_ids[i - 1]}
		parent.child_ids[command.to] = item
		return true; case:
		return false}}

story_authoring_effect_reference :: proc(
	project: ^Story_Project,
	command: ^Story_Authoring_Command,
) -> bool {if story_effect_index(project, command.id) < 0 && command.kind == .Insert_Effect_Reference do return false
	for &node in project.nodes do if node.id == command.owner_id {#partial switch command.kind {case .Insert_Effect_Reference:
			if node.effect_id_count >= len(node.effect_ids) do return false; at := clamp(command.to, 0, node.effect_id_count); for i := node.effect_id_count; i > at; i -= 1 do node.effect_ids[i] = node.effect_ids[i - 1]; node.effect_ids[at] = command.id; node.effect_id_count += 1; return true; case .Remove_Effect_Reference:
			if command.from < 0 || command.from >= node.effect_id_count do return false; for i in command.from + 1 ..< node.effect_id_count do node.effect_ids[i - 1] = node.effect_ids[i]; node.effect_id_count -= 1; node.effect_ids[node.effect_id_count] = ""; return true; case .Reorder_Effect_Reference:
			if command.from < 0 || command.to < 0 || command.from >= node.effect_id_count || command.to >= node.effect_id_count do return false; node.effect_ids[command.from], node.effect_ids[command.to] = node.effect_ids[command.to], node.effect_ids[command.from]; return true; case:
			return false}}
	for &item in project.storylets do if item.id == command.owner_id {#partial switch command.kind {case .Insert_Effect_Reference:
			if item.effect_count >= len(item.effect_ids) do return false; at := clamp(command.to, 0, item.effect_count); for i := item.effect_count; i > at; i -= 1 do item.effect_ids[i] = item.effect_ids[i - 1]; item.effect_ids[at] = command.id; item.effect_count += 1; return true; case .Remove_Effect_Reference:
			if command.from < 0 || command.from >= item.effect_count do return false; for i in command.from + 1 ..< item.effect_count do item.effect_ids[i - 1] = item.effect_ids[i]; item.effect_count -= 1; item.effect_ids[item.effect_count] = ""; return true; case .Reorder_Effect_Reference:
			if command.from < 0 || command.to < 0 || command.from >= item.effect_count || command.to >= item.effect_count do return false; item.effect_ids[command.from], item.effect_ids[command.to] = item.effect_ids[command.to], item.effect_ids[command.from]; return true; case:
			return false}}
	return false}

story_authoring_apply_raw :: proc(
	project: ^Story_Project,
	command: ^Story_Authoring_Command,
	result: ^Story_Authoring_Result,
) -> bool {
	switch command.kind {
	case .Set_Metadata:
		if !story_authoring_valid_id(command.metadata.id) do return false
		project.id =
			command.metadata.id; project.title = command.metadata.title; project.creator = command.metadata.creator; project.description = command.metadata.description; project.content_version = command.metadata.content_version; project.default_space_id = command.metadata.default_space_id; return true
	case .Add_Expansion:
		if !story_authoring_valid_id(command.expansion.id) || command.expansion.version == "" do return false
		for item in project.expansion_requirements do if item.id == command.expansion.id do return false
		append(&project.expansion_requirements, command.expansion)
		return true
	case .Update_Expansion:
		if command.from < 0 || command.from >= len(project.expansion_requirements) || !story_authoring_valid_id(command.expansion.id) || command.expansion.version == "" do return false
		for item, i in project.expansion_requirements do if i != command.from && item.id == command.expansion.id do return false
		project.expansion_requirements[command.from] = command.expansion
		return true
	case .Remove_Expansion:
		if command.from < 0 || command.from >= len(project.expansion_requirements) do return false
		ordered_remove(&project.expansion_requirements, command.from); return true
	case .Reorder_Expansion:
		return story_authoring_reorder(&project.expansion_requirements, command.from, command.to)
	case .Add_Capability:
		for item in project.capabilities do if item.id == command.capability.id do return false
		copy, ok := story_authoring_clone_capability(command.capability); if !ok do return false
		append(&project.capabilities, copy); return true
	case .Update_Capability:
		if command.from < 0 || command.from >= len(project.capabilities) do return false
		for item, i in project.capabilities do if i != command.from && item.id == command.capability.id do return false
		copy, ok := story_authoring_clone_capability(command.capability); if !ok do return false
		story_authoring_destroy_capability_payload(
			&project.capabilities[command.from],
		); project.capabilities[command.from] = copy; return true
	case .Remove_Capability:
		if command.from < 0 || command.from >= len(project.capabilities) do return false
		story_authoring_destroy_capability_payload(
			&project.capabilities[command.from],
		); ordered_remove(&project.capabilities, command.from); return true
	case .Reorder_Capability:
		return story_authoring_reorder(&project.capabilities, command.from, command.to)
	case .Add_Entity:
		if !story_authoring_valid_id(command.entity.id) || story_entity_index(project, command.entity.id) >= 0 do return false
		append(&project.entities, command.entity)
		return true
	case .Update_Entity:
		index := story_entity_index(project, command.entity.id); if index < 0 do return false
		project.entities[index] = command.entity
		return true
	case .Add_Variable:
		if !story_authoring_valid_id(command.variable.id) || story_variable_index(project, command.variable.id) >= 0 do return false
		append(&project.variables, command.variable)
		return true
	case .Update_Variable:
		index := story_variable_index(project, command.variable.id); if index < 0 do return false
		project.variables[index] = command.variable
		return true
	case .Add_Proposition:
		if !story_authoring_valid_id(command.proposition.id) || story_proposition_index(project, command.proposition.id) >= 0 do return false
		append(&project.propositions, command.proposition)
		return true
	case .Update_Proposition:
		index := story_proposition_index(project, command.proposition.id)
		if index < 0 do return false
		project.propositions[index] = command.proposition
		return true
	case .Add:
		return story_authoring_apply_record(project, command, false)
	case .Update:
		return story_authoring_apply_record(project, command, true)
	case .Duplicate:
		if !story_authoring_valid_id(command.new_id) || story_authoring_record_exists(project, command.record_kind, command.new_id) do return false
		#partial switch command.record_kind {case .Entity:
			command.entity.id = command.new_id; case .Role:
			command.role.id = command.new_id; case .Variable:
			command.variable.id = command.new_id; case .Fact:
			command.fact.id = command.new_id; case .Proposition:
			command.proposition.id = command.new_id; case .Relationship:
			command.relationship.id = command.new_id; case .Event:
			command.event.id = command.new_id; case .Objective:
			command.objective.id = command.new_id; case .Ending:
			command.ending.id = command.new_id; case .Storylet_Group:
			command.storylet_group.id = command.new_id; case .Storylet:
			command.storylet.id = command.new_id; case .Invariant:
			command.invariant.id = command.new_id; case .Condition:
			command.condition.id = command.new_id; case .Effect:
			command.effect.id = command.new_id; case:
			return false}
		return story_authoring_apply_record(project, command, false)
	case .Reorder:
		return story_authoring_reorder_record(
			project,
			command.record_kind,
			command.from,
			command.to,
		)
	case .Rename:
		return story_authoring_replace_id(project, command.record_kind, command.id, command.new_id)
	case .Remove:
		result.blocked_by = story_authoring_dependency_preview(
			project,
			command.record_kind,
			command.id,
		)
		if result.blocked_by.dependency_count > 0 || result.blocked_by.truncated do return false
		return story_authoring_remove_unreferenced(project, command.record_kind, command.id)
	case .Insert_Condition_Child, .Remove_Condition_Child, .Reorder_Condition_Child:
		return story_authoring_condition_child(project, command)
	case .Insert_Effect_Reference, .Remove_Effect_Reference, .Reorder_Effect_Reference:
		return story_authoring_effect_reference(project, command)
	}
	return false
}

story_authoring_snapshot_clear :: proc(items: ^[dynamic]Story_Project) {for &item in items^ do story_project_destroy(&item)
	delete(items^)
	items^ = nil}

story_authoring_history_push :: proc(items: ^[dynamic]Story_Project, project: ^Story_Project) {
	if len(items^) >=
	   STORY_AUTHORING_HISTORY_LIMIT {story_project_destroy(&items^[0]); ordered_remove(items, 0)}
	append(items, story_project_clone(project))
}

story_authoring_history_destroy :: proc(
	history: ^Story_Authoring_History,
) {story_authoring_snapshot_clear(&history.undo); story_authoring_snapshot_clear(&history.redo)
	history^ = {}}

story_authoring_apply :: proc(
	project: ^Story_Project,
	history: ^Story_Authoring_History,
	commands: []Story_Authoring_Command,
) -> Story_Authoring_Result {
	result :=
		Story_Authoring_Result{}; if project == nil || len(commands) == 0 {result.message = "no authoring commands"; return result}; result.revision = project.revision
	working := story_project_clone(project)
	for &command in commands {if !story_authoring_apply_raw(
			&working,
			&command,
			&result,
		) {story_project_destroy(&working); result.message = result.blocked_by.dependency_count > 0 ? "remove blocked by dependencies" : "authoring command rejected without changes"; return result}}
	working.revision += 1; result.validation = story_project_validate(&working); if !result.validation.ok {story_project_destroy(&working); result.message = "authoring transaction failed validation"; return result}
	if history !=
	   nil {story_authoring_history_push(&history.undo, project); story_authoring_snapshot_clear(&history.redo)}
	story_project_destroy(
		project,
	); project^ = working; result.ok = true; result.revision = project.revision; result.message = "authoring transaction committed"; if project == &active_story_project do _ = authoring_invalidate_after_edit(.Story_Core, project.revision); return result
}

story_authoring_undo :: proc(project: ^Story_Project, history: ^Story_Authoring_History) -> bool {
	if project == nil || history == nil || len(history.undo) == 0 do return false
	story_authoring_history_push(
		&history.redo,
		project,
	); replacement := history.undo[len(history.undo) - 1]; ordered_remove(&history.undo, len(history.undo) - 1); story_project_destroy(project); project^ = replacement; if project == &active_story_project do _ = authoring_invalidate_after_edit(.Story_Core, project.revision); return true
}

story_authoring_redo :: proc(project: ^Story_Project, history: ^Story_Authoring_History) -> bool {
	if project == nil || history == nil || len(history.redo) == 0 do return false
	story_authoring_history_push(
		&history.undo,
		project,
	); replacement := history.redo[len(history.redo) - 1]; ordered_remove(&history.redo, len(history.redo) - 1); story_project_destroy(project); project^ = replacement; if project == &active_story_project do _ = authoring_invalidate_after_edit(.Story_Core, project.revision); return true
}

story_authoring_result_destroy :: proc(result: ^Story_Authoring_Result) {story_validation_destroy(
		&result.validation,
	)
	result^ = {}}
