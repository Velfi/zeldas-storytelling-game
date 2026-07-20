package main

import "core:strings"

Story_Capabilities :: struct {
	format_version:string,
	domains:[STORY_MAX_DOMAIN_ADAPTERS]Story_Domain_Capability,
	domain_count:int,
	revision_checked_commands, atomic_batches, dry_run, deterministic_compile, scene_runtime:bool,
}
Story_Domain_Capability :: struct {id,version:string}

Story_Reference :: struct {id, display_name:string, kind:Story_Record_Kind}
Story_Reference_Query :: struct {items:[dynamic]Story_Reference}
Story_Dependency_Query :: struct {target_id:string, dependents:[dynamic]Story_Reference}

story_capabilities :: proc()->Story_Capabilities {story_domain_register_core();result:=Story_Capabilities{format_version=STORY_PROJECT_VERSION,revision_checked_commands=true,atomic_batches=true,dry_run=true,deterministic_compile=true,scene_runtime=true};for adapter,i in story_domain_adapters[:story_domain_adapter_count] {result.domains[i]={adapter.id,adapter.version};result.domain_count+=1};return result}

story_reference_matches :: proc(id,name,needle:string)->bool {return needle==""||strings.contains(strings.to_lower(id),strings.to_lower(needle))||strings.contains(strings.to_lower(name),strings.to_lower(needle))}

story_reference_search :: proc(project:^Story_Project,needle:string)->Story_Reference_Query {
	result:Story_Reference_Query
	for item in project.entities do if story_reference_matches(item.id,item.display_name,needle) do append(&result.items,Story_Reference{item.id,item.display_name,.Entity})
	for item in project.roles do if story_reference_matches(item.id,item.display_name,needle) do append(&result.items,Story_Reference{item.id,item.display_name,.Role})
	for item in project.variables do if story_reference_matches(item.id,item.display_name,needle) do append(&result.items,Story_Reference{item.id,item.display_name,.Variable})
	for item in project.facts do if story_reference_matches(item.id,item.display_name,needle) do append(&result.items,Story_Reference{item.id,item.display_name,.Fact})
	for item in project.propositions do if story_reference_matches(item.id,item.text,needle) do append(&result.items,Story_Reference{item.id,item.text,.Proposition})
	for item in project.relationships do if story_reference_matches(item.id,item.kind,needle) do append(&result.items,Story_Reference{item.id,item.kind,.Relationship})
	for item in project.events do if story_reference_matches(item.id,item.action,needle) do append(&result.items,Story_Reference{item.id,item.action,.Event})
	for item in project.objectives do if story_reference_matches(item.id,item.display_name,needle) do append(&result.items,Story_Reference{item.id,item.display_name,.Objective})
	for item in project.scenes do if story_reference_matches(item.id,item.display_name,needle) do append(&result.items,Story_Reference{item.id,item.display_name,.Scene})
	for item in project.nodes do if story_reference_matches(item.id,item.text,needle) do append(&result.items,Story_Reference{item.id,item.text,.Node})
	for item in project.storylet_groups do if story_reference_matches(item.id,"",needle) do append(&result.items,Story_Reference{item.id,"",.Storylet_Group})
	for item in project.storylets do if story_reference_matches(item.id,"",needle) do append(&result.items,Story_Reference{item.id,"",.Storylet})
	for item in project.endings do if story_reference_matches(item.id,item.title,needle) do append(&result.items,Story_Reference{item.id,item.title,.Ending})
	for item in project.invariants do if story_reference_matches(item.id,item.description,needle) do append(&result.items,Story_Reference{item.id,item.description,.Invariant})
	return result
}

story_reference_query_destroy :: proc(result:^Story_Reference_Query) {delete(result.items);result^={}}

story_dependency_add :: proc(result:^Story_Dependency_Query,id,name:string,kind:Story_Record_Kind) {for item in result.dependents do if item.id==id&&item.kind==kind do return;append(&result.dependents,Story_Reference{id,name,kind})}

story_dependencies :: proc(project:^Story_Project,target:string)->Story_Dependency_Query {
	result:=Story_Dependency_Query{target_id=target}
	for item in project.entities {for role_i in 0..<item.role_count do if item.roles[role_i]==target do story_dependency_add(&result,item.id,item.display_name,.Entity)}
	for item in project.facts do if item.proposition==target||item.variable_id==target do story_dependency_add(&result,item.id,item.display_name,.Fact)
	for item in project.initial_knowledge do if item.actor_id==target||item.proposition_id==target do story_dependency_add(&result,item.actor_id,item.proposition_id,.Knowledge)
	for item in project.relationships do if item.source_id==target||item.target_id==target||item.variable_id==target do story_dependency_add(&result,item.id,item.kind,.Relationship)
	for item in project.events {if item.subject_id==target||item.object_id==target||item.location_id==target do story_dependency_add(&result,item.id,item.action,.Event);for i in 0..<item.witness_count do if item.witnesses[i]==target do story_dependency_add(&result,item.id,item.action,.Event)}
	for item in project.scenes do if item.bound_entity==target||item.entry_node==target do story_dependency_add(&result,item.id,item.display_name,.Scene)
	for item in project.nodes do if item.scene_id==target||item.speaker_id==target||item.next==target||item.success==target||item.failure==target||item.cancel==target||item.subscene_id==target do story_dependency_add(&result,item.id,item.text,.Node)
	for item in project.storylets do if item.group==target||item.scene_id==target do story_dependency_add(&result,item.id,"",.Storylet)
	return result
}

story_dependency_query_destroy :: proc(result:^Story_Dependency_Query) {delete(result.dependents);result^={}}
