package main

// Compiled story data owns its storage and is independent from editor documents.
// Runtime IDs are assigned by stable-ID lexical order, so harmless source-array
// reordering cannot change save identity or runtime references.

STORY_INVALID_RUNTIME_ID :: -1

Compiled_Id :: struct {stable_id:string, runtime_id:int}

Compiled_Story_Node :: struct {
	id, scene, speaker, next, success, failure, cancel, subscene:int,
	line_id, text:string,
	kind:Story_Node_Kind,
	condition_root, first_effect, effect_count:int,
}

Compiled_Story :: struct {
	project_id, content_version:string,
	content_identity, schema_identity:u64,
	// Runtime data is an owned clone. Editor mutations cannot alter a running
	// story; a new compile is required to cross this boundary.
	runtime:Story_Project,
	entities, variables, propositions, events, objectives, conditions, effects, scenes, nodes, storylets, endings:[dynamic]Compiled_Id,
	compiled_nodes:[dynamic]Compiled_Story_Node,
}

Story_Compile_Result :: struct {ok:bool, message:string, story:Compiled_Story, validation:Story_Validation}

story_hash_text :: proc(hash:u64, value:string)->u64 {
	result:=hash
	for ch in value do result=(result~u64(ch))*1099511628211
	return (result~255)*1099511628211
}

story_hash_value :: proc(hash:u64,value:Story_Value)->u64 {result:=(hash~u64(value.kind))*1099511628211;result=(result~u64(value.boolean_value))*1099511628211;result=(result~u64(value.integer_value))*1099511628211;return story_hash_text(result,value.text_value)}
story_record_hash :: proc()->u64 {return 1469598103934665603}

compiled_ids_add :: proc(items:^[dynamic]Compiled_Id,id:string) {
	if id=="" do return
	insert_at:=len(items^)
	for item,i in items^ do if id<item.stable_id {insert_at=i;break}
	append(items,Compiled_Id{stable_id=id})
	for i:=len(items^)-1;i>insert_at;i-=1 do items[i]=items[i-1]
	items[insert_at]={stable_id=id}
}

compiled_ids_finish :: proc(items:^[dynamic]Compiled_Id) {for &item,i in items^ do item.runtime_id=i}

compiled_id_find :: proc(items:[]Compiled_Id,id:string)->int {
	for item in items do if item.stable_id==id do return item.runtime_id
	return STORY_INVALID_RUNTIME_ID
}

compiled_story_destroy :: proc(story:^Compiled_Story) {
	story_project_destroy(&story.runtime)
	delete(story.entities);delete(story.variables);delete(story.propositions);delete(story.events);delete(story.objectives);delete(story.conditions);delete(story.effects)
	delete(story.scenes);delete(story.nodes);delete(story.storylets);delete(story.endings);delete(story.compiled_nodes)
	story^={}
}

story_compile_result_destroy :: proc(result:^Story_Compile_Result) {compiled_story_destroy(&result.story);story_validation_destroy(&result.validation);result^={}}

compile_story_project :: proc(project:^Story_Project)->Story_Compile_Result {
	result:=Story_Compile_Result{}
	if resolved:=story_resolve_environment(project);!resolved.ok {result.message=resolved.message;return result}
	result.validation=story_project_validate(project)
	if !result.validation.ok {result.message="story compilation failed validation";return result}
	for capability in project.capabilities {adapter:=story_domain_find(capability.id,capability.version);if adapter!=nil&&adapter.compile!=nil&&!adapter.compile(project) {result.message="story capability compilation failed";return result}}
	compiled:=Compiled_Story{project_id=project.id,content_version=project.content_version,schema_identity=story_schema_identity(project),runtime=story_project_clone(project)}
	for item in project.entities do compiled_ids_add(&compiled.entities,item.id)
	for item in project.variables do compiled_ids_add(&compiled.variables,item.id)
	for item in project.propositions do compiled_ids_add(&compiled.propositions,item.id)
	for item in project.events do compiled_ids_add(&compiled.events,item.id)
	for item in project.objectives do compiled_ids_add(&compiled.objectives,item.id)
	for item in project.conditions do compiled_ids_add(&compiled.conditions,item.id)
	for item in project.effects do compiled_ids_add(&compiled.effects,item.id)
	for item in project.scenes do compiled_ids_add(&compiled.scenes,item.id)
	for item in project.nodes do compiled_ids_add(&compiled.nodes,item.id)
	for item in project.storylets do compiled_ids_add(&compiled.storylets,item.id)
	for item in project.endings do compiled_ids_add(&compiled.endings,item.id)
	compiled_ids_finish(&compiled.entities);compiled_ids_finish(&compiled.variables);compiled_ids_finish(&compiled.propositions);compiled_ids_finish(&compiled.events);compiled_ids_finish(&compiled.objectives);compiled_ids_finish(&compiled.conditions);compiled_ids_finish(&compiled.effects);compiled_ids_finish(&compiled.scenes);compiled_ids_finish(&compiled.nodes);compiled_ids_finish(&compiled.storylets);compiled_ids_finish(&compiled.endings)
	for mapping in compiled.nodes {
		source_index:=-1
		for node,i in project.nodes do if node.id==mapping.stable_id {source_index=i;break}
		if source_index<0 do continue
		node:=project.nodes[source_index]
		append(&compiled.compiled_nodes,Compiled_Story_Node{
			id=mapping.runtime_id,scene=compiled_id_find(compiled.scenes[:],node.scene_id),speaker=compiled_id_find(compiled.entities[:],node.speaker_id),
			next=compiled_id_find(compiled.nodes[:],node.next),success=compiled_id_find(compiled.nodes[:],node.success),failure=compiled_id_find(compiled.nodes[:],node.failure),cancel=compiled_id_find(compiled.nodes[:],node.cancel),subscene=compiled_id_find(compiled.scenes[:],node.subscene_id),
			line_id=node.line_id,text=node.text,kind=node.kind,condition_root=compiled_id_find(compiled.conditions[:],node.condition_id),first_effect=STORY_INVALID_RUNTIME_ID,effect_count=node.effect_id_count,
		})
	}
	hash:u64=1469598103934665603
	hash=story_hash_text(hash,project.version);hash=story_hash_text(hash,compiled.project_id);hash=story_hash_text(hash,project.title);hash=story_hash_text(hash,project.creator);hash=story_hash_text(hash,project.description);hash=story_hash_text(hash,compiled.content_version);hash=story_hash_text(hash,project.default_space_id)
	for requirement in project.expansion_requirements {hash=story_hash_text(hash,requirement.id);hash=story_hash_text(hash,requirement.version);hash=(hash~u64(requirement.optional))*1099511628211;hash=(hash~u64(requirement.distribution))*1099511628211;hash=(hash~u64(requirement.fallback))*1099511628211}
	for capability in project.capabilities {hash=story_hash_text(hash,capability.id);hash=story_hash_text(hash,capability.version)}
	for resolved in project.resolved_environment.expansions {hash=story_hash_text(hash,resolved.id);hash=story_hash_text(hash,resolved.namespace);hash=story_hash_text(hash,resolved.version);hash=story_hash_text(hash,resolved.content_hash)}
	for item in compiled.entities do hash=story_hash_text(hash,item.stable_id)
	for item in compiled.variables do hash=story_hash_text(hash,item.stable_id)
	for item in compiled.propositions do hash=story_hash_text(hash,item.stable_id)
	for item in compiled.events do hash=story_hash_text(hash,item.stable_id)
	for item in compiled.objectives do hash=story_hash_text(hash,item.stable_id)
	for item in compiled.conditions do hash=story_hash_text(hash,item.stable_id)
	for item in compiled.effects do hash=story_hash_text(hash,item.stable_id)
	for item in compiled.scenes do hash=story_hash_text(hash,item.stable_id)
	for item in compiled.nodes do hash=story_hash_text(hash,item.stable_id)
	for item in compiled.storylets do hash=story_hash_text(hash,item.stable_id)
	for item in compiled.endings do hash=story_hash_text(hash,item.stable_id)
	for mapping in compiled.entities {source:=story_entity_index(project,mapping.stable_id);if source>=0 {item:=project.entities[source];hash=story_hash_text(hash,item.kind);hash=story_hash_text(hash,item.display_name);hash=story_hash_text(hash,item.description);hash=story_hash_text(hash,item.spatial.space_id);hash=story_hash_text(hash,item.spatial.target_id);hash=(hash~u64(item.spatial.target_kind))*1099511628211;hash=(hash~u64(item.volume))*1099511628211;hash=(hash~u64(item.container_capacity))*1099511628211;hash=(hash~u64(item.initially_locked))*1099511628211;hash=story_hash_text(hash,item.owner_id);hash=story_hash_text(hash,item.initial_container_id);for tag in item.tags[:item.tag_count] do hash=story_hash_text(hash,tag);for role in item.roles[:item.role_count] do hash=story_hash_text(hash,role)}}
	for role in project.roles {record:=story_hash_text(story_record_hash(),role.id);record=story_hash_text(record,role.display_name);record=story_hash_text(record,role.description);record=(record~u64(role.minimum))*1099511628211;record=(record~u64(role.maximum))*1099511628211;hash~=record}
	for mapping in compiled.variables {for &item in project.variables do if item.id==mapping.stable_id {hash=story_hash_text(hash,item.display_name);hash=story_hash_text(hash,item.description);hash=story_hash_value(hash,item.default_value);hash=(hash~u64(item.minimum))*1099511628211;hash=(hash~u64(item.maximum))*1099511628211;for value in item.enum_values[:item.enum_value_count] do hash=story_hash_text(hash,value)}}
	for fact in project.facts {record:=story_hash_text(story_record_hash(),fact.id);record=story_hash_text(record,fact.display_name);record=story_hash_text(record,fact.proposition);record=story_hash_text(record,fact.variable_id);record=(record~u64(fact.canonical_truth))*1099511628211;record=(record~u64(fact.player_visible))*1099511628211;hash~=record}
	for mapping in compiled.propositions {for item in project.propositions do if item.id==mapping.stable_id {hash=story_hash_text(hash,item.text);hash=(hash~u64(item.canonical_truth))*1099511628211}}
	for item in project.initial_knowledge {record:=story_hash_text(story_record_hash(),item.actor_id);record=story_hash_text(record,item.proposition_id);record=(record~u64(item.stance))*1099511628211;hash~=record}
	for item in project.relationships {record:=story_hash_text(story_record_hash(),item.id);record=story_hash_text(record,item.source_id);record=story_hash_text(record,item.target_id);record=story_hash_text(record,item.kind);record=story_hash_text(record,item.variable_id);hash~=record}
	for mapping in compiled.events {for &item in project.events do if item.id==mapping.stable_id {hash=story_hash_text(hash,item.subject_id);hash=story_hash_text(hash,item.action);hash=story_hash_text(hash,item.object_id);hash=story_hash_text(hash,item.location_id);hash=story_hash_text(hash,item.fictional_time);hash=story_hash_text(hash,item.provenance);for witness in item.witnesses[:item.witness_count] do hash=story_hash_text(hash,witness)}}
	for mapping in compiled.objectives {for item in project.objectives do if item.id==mapping.stable_id {hash=story_hash_text(hash,item.display_name);hash=story_hash_text(hash,item.description);hash=(hash~u64(item.hidden))*1099511628211;hash=(hash~u64(item.initial_status))*1099511628211;hash=(hash~u64(item.stage_count))*1099511628211;hash=story_hash_text(hash,item.completion_condition_id);hash=story_hash_text(hash,item.failure_condition_id)}}
	for mapping in compiled.scenes {for item in project.scenes do if item.id==mapping.stable_id {hash=story_hash_text(hash,item.display_name);hash=story_hash_text(hash,item.entry_node);hash=story_hash_text(hash,item.bound_entity);hash=story_hash_text(hash,item.summary);hash=story_hash_text(hash,item.return_to)}}
	for mapping in compiled.conditions {for item in project.conditions do if item.id==mapping.stable_id {hash=(hash~u64(item.kind))*1099511628211;hash=story_hash_text(hash,item.variable_id);hash=story_hash_text(hash,item.entity_id);hash=story_hash_text(hash,item.other_entity_id);hash=story_hash_text(hash,item.proposition_id);hash=story_hash_text(hash,item.objective_id);hash=story_hash_text(hash,item.event_id);hash=story_hash_text(hash,item.content_id);hash=story_hash_text(hash,item.text_value);hash=story_hash_value(hash,item.value);hash=(hash~u64(item.comparison))*1099511628211;hash=(hash~u64(item.objective_status))*1099511628211;hash=(hash~u64(item.belief_stance))*1099511628211;hash=story_hash_text(hash,item.spatial_a.space_id);hash=story_hash_text(hash,item.spatial_a.target_id);hash=story_hash_text(hash,item.spatial_b.space_id);hash=story_hash_text(hash,item.spatial_b.target_id);for child_i in 0..<item.child_id_count do hash=story_hash_text(hash,item.child_ids[child_i]);hash=(hash~u64(item.distance*1000))*1099511628211}}
	for mapping in compiled.effects {for item in project.effects do if item.id==mapping.stable_id {hash=(hash~u64(item.kind))*1099511628211;hash=story_hash_text(hash,item.variable_id);hash=story_hash_text(hash,item.actor_id);hash=story_hash_text(hash,item.other_actor_id);hash=story_hash_text(hash,item.proposition_id);hash=story_hash_text(hash,item.objective_id);hash=story_hash_text(hash,item.event_id);hash=story_hash_text(hash,item.content_id);hash=story_hash_text(hash,item.world_id);hash=story_hash_value(hash,item.value);hash=(hash~u64(item.belief_stance))*1099511628211;hash=(hash~u64(item.objective_status))*1099511628211;hash=story_hash_text(hash,item.spatial_target.space_id);hash=story_hash_text(hash,item.spatial_target.target_id);hash=story_hash_text(hash,item.spatial_destination.space_id);hash=story_hash_text(hash,item.spatial_destination.target_id);hash=(hash~u64(item.spatial_command))*1099511628211;hash=(hash~u64(item.world_enabled))*1099511628211}}
	for node,i in compiled.compiled_nodes {hash=story_hash_text(hash,node.line_id);hash=story_hash_text(hash,node.text);hash=(hash~u64(node.kind))*1099511628211;hash=(hash~u64(node.scene+1))*1099511628211;hash=(hash~u64(node.speaker+1))*1099511628211;hash=(hash~u64(node.subscene+1))*1099511628211;hash=(hash~u64(node.condition_root+1))*1099511628211;hash=(hash~u64(node.effect_count))*1099511628211;hash=(hash~u64(node.next+1))*1099511628211;hash=(hash~u64(node.success+1))*1099511628211;hash=(hash~u64(node.failure+1))*1099511628211;hash=(hash~u64(node.cancel+1))*1099511628211;if i<len(compiled.nodes) {for source in project.nodes do if source.id==compiled.nodes[i].stable_id {for effect_i in 0..<source.effect_id_count do hash=story_hash_text(hash,source.effect_ids[effect_i]);hash=story_hash_text(hash,source.ui);hash=story_hash_text(hash,source.camera);hash=story_hash_text(hash,source.actor);hash=story_hash_text(hash,source.actor_mark);hash=story_hash_text(hash,source.animation);hash=story_hash_text(hash,source.summary);hash=story_hash_text(hash,source.ending);hash=story_hash_text(hash,source.domain_ref);hash=story_hash_text(hash,source.event_id);hash=(hash~u64(source.duration*1000))*1099511628211;hash=(hash~u64(source.transition*1000))*1099511628211;hash=(hash~u64(source.blocking))*1099511628211;for choice_i in 0..<source.choice_count {choice:=source.choices[choice_i];hash=story_hash_text(hash,choice.id);hash=story_hash_text(hash,choice.label);hash=story_hash_text(hash,choice.target);hash=story_hash_text(hash,choice.condition_id)}}}}
	for mapping in compiled.storylets {for &item in project.storylets do if item.id==mapping.stable_id {hash=story_hash_text(hash,item.group);hash=story_hash_text(hash,item.scene_id);for condition in item.condition_ids[:item.condition_count] do hash=story_hash_text(hash,condition);for effect in item.effect_ids[:item.effect_count] do hash=story_hash_text(hash,effect);hash=(hash~u64(item.dramatic_priority))*1099511628211;hash=(hash~u64(item.specificity))*1099511628211;hash=(hash~u64(item.cooldown))*1099511628211;hash=(hash~u64(item.authored_order))*1099511628211;hash=(hash~u64(item.repeat_policy))*1099511628211;hash=(hash~u64(item.fallback))*1099511628211}}
	for group in project.storylet_groups {record:=story_hash_text(story_record_hash(),group.id);record=(record~u64(group.allow_empty))*1099511628211;record=(record~u64(group.seeded_random_ties))*1099511628211;hash~=record}
	for mapping in compiled.endings {for item in project.endings do if item.id==mapping.stable_id {hash=story_hash_text(hash,item.title);hash=story_hash_text(hash,item.summary);hash=story_hash_text(hash,item.condition_id);hash=(hash~u64(item.priority))*1099511628211}}
	for item in project.invariants {record:=story_hash_text(story_record_hash(),item.id);record=story_hash_text(record,item.description);record=story_hash_text(record,item.condition_id);record=(record~u64(item.kind))*1099511628211;record=(record~u64(item.required))*1099511628211;hash~=record}
	for capability in project.capabilities {adapter:=story_domain_find(capability.id,capability.version);if adapter!=nil&&adapter.hash!=nil do hash=adapter.hash(project,hash)}
	compiled.content_identity=hash
	result.ok=true;result.message="STORY COMPILED";result.story=compiled
	return result
}
