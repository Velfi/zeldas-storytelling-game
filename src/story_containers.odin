package main

import "core:fmt"

Story_Container_Result :: struct {ok:bool, message:string}

story_container_state_index :: proc(state:^Story_State,id:string)->int {for item,i in state.containers do if item.entity_id==id do return i;return -1}
story_containment_index :: proc(state:^Story_State,item_id:string)->int {for item,i in state.containment do if item.item_id==item_id do return i;return -1}

story_container_used_volume :: proc(project:^Story_Project,state:^Story_State,container_id:string)->int {
	used:=0
	for placement in state.containment do if placement.container_id==container_id {i:=story_entity_index(project,placement.item_id);if i>=0 do used+=project.entities[i].volume}
	return used
}

story_container_available_volume :: proc(project:^Story_Project,state:^Story_State,container_id:string)->int {
	i:=story_entity_index(project,container_id);if i<0||project.entities[i].container_capacity<=0 do return 0
	return max(0,project.entities[i].container_capacity-story_container_used_volume(project,state,container_id))
}

story_container_contains :: proc(state:^Story_State,container_id,item_id:string)->bool {i:=story_containment_index(state,item_id);return i>=0&&state.containment[i].container_id==container_id}

story_container_would_cycle :: proc(state:^Story_State,item_id,container_id:string)->bool {
	current:=container_id
	for _ in 0..=len(state.containment) {if current==item_id do return true;i:=story_containment_index(state,current);if i<0 do return false;current=state.containment[i].container_id}
	return true
}

story_container_store :: proc(project:^Story_Project,state:^Story_State,container_id,item_id:string)->Story_Container_Result {
	container_i:=story_entity_index(project,container_id);item_i:=story_entity_index(project,item_id)
	if container_i<0||story_container_state_index(state,container_id)<0 do return {message="container does not exist"}
	if item_i<0 do return {message="item does not exist"}
	cs:=&state.containers[story_container_state_index(state,container_id)];if cs.locked do return {message="container is locked"}
	if project.entities[item_i].volume<=0 do return {message="item has no storable volume"}
	if story_containment_index(state,item_id)>=0 do return {message="item is already stored"}
	if story_container_would_cycle(state,item_id,container_id) do return {message="containers cannot contain themselves"}
	available:=story_container_available_volume(project,state,container_id);if project.entities[item_i].volume>available do return {message=fmt.tprintf("item needs %d volume; only %d available",project.entities[item_i].volume,available)}
	append(&state.containment,Story_Containment_State{item_id=item_id,container_id=container_id});return {true,"item stored"}
}

story_container_remove :: proc(state:^Story_State,container_id,item_id:string)->Story_Container_Result {
	ci:=story_container_state_index(state,container_id);if ci<0 do return {message="container does not exist"}
	if state.containers[ci].locked do return {message="container is locked"}
	i:=story_containment_index(state,item_id);if i<0||state.containment[i].container_id!=container_id do return {message="item is not in container"}
	ordered_remove(&state.containment,i);return {true,"item removed"}
}

story_container_set_locked :: proc(state:^Story_State,container_id:string,locked:bool)->Story_Container_Result {
	i:=story_container_state_index(state,container_id);if i<0 do return {message="container does not exist"}
	state.containers[i].locked=locked;return {true,locked?"container locked":"container unlocked"}
}

story_container_set_owner :: proc(project:^Story_Project,state:^Story_State,container_id,owner_id:string)->Story_Container_Result {
	i:=story_container_state_index(state,container_id);if i<0 do return {message="container does not exist"}
	if owner_id!=""&&story_entity_index(project,owner_id)<0 do return {message="owner does not exist"}
	state.containers[i].owner_id=owner_id;return {true,owner_id==""?"container unowned":"container owner changed"}
}

run_story_container_tests :: proc() {
	project:=Story_Project{version=STORY_PROJECT_VERSION,id="containers",title="Containers",content_version="1"}
	defer story_project_destroy(&project)
	append(&project.entities,
		Story_Entity{id="detective",kind="person"},
		Story_Entity{id="chest",kind="object",volume=8,container_capacity=10,initially_locked=true,owner_id="detective"},
		Story_Entity{id="letter",kind="object",volume=2},
		Story_Entity{id="statue",kind="object",volume=9},
	)
	validation:=story_project_validate(&project);assert(validation.ok);story_validation_destroy(&validation)
	roundtrip_path:="/private/tmp/chicago-container-roundtrip.toml";assert(save_story_project(roundtrip_path,&project).ok)
	roundtrip:Story_Project;assert(load_story_project(roundtrip_path,&roundtrip).ok);defer story_project_destroy(&roundtrip)
	roundtrip_chest:=roundtrip.entities[story_entity_index(&roundtrip,"chest")];assert(roundtrip_chest.volume==8&&roundtrip_chest.container_capacity==10&&roundtrip_chest.initially_locked&&roundtrip_chest.owner_id=="detective")
	state:=story_state_new(&project);defer story_state_destroy(&state)
	assert(state.containers[0].locked&&state.containers[0].owner_id=="detective")
	assert(!story_container_store(&project,&state,"chest","letter").ok)
	assert(story_container_set_locked(&state,"chest",false).ok)
	assert(story_container_store(&project,&state,"chest","letter").ok&&story_container_contains(&state,"chest","letter"))
	assert(story_container_used_volume(&project,&state,"chest")==2&&story_container_available_volume(&project,&state,"chest")==8)
	assert(!story_container_store(&project,&state,"chest","statue").ok)
	assert(story_container_remove(&state,"chest","letter").ok)
	assert(story_container_set_owner(&project,&state,"chest","").ok&&state.containers[0].owner_id=="")
	clone:=story_state_clone(&state);defer story_state_destroy(&clone);assert(len(clone.containers)==1&&!clone.containers[0].locked)
}
