package main

Story_Test_Spatial :: struct {began,committed,rolled_back:bool, staged:[16]Story_Spatial_Command, staged_count:int}

story_test_domain_clone :: proc(source:rawptr)->rawptr {result:=new(u64);result^=(cast(^u64)source)^;return result}
story_test_domain_destroy :: proc(payload:rawptr) {free(payload)}
story_test_domain_hash :: proc(project:^Story_Project,seed:u64)->u64 {payload:=story_capability_payload(project,"test_domain","1");if payload==nil do return seed;return seed~(cast(^u64)payload)^}
story_test_domain_serialize :: proc(payload:rawptr)->string {return "[domain_test]\nvalue = 41\n"}
story_test_domain_parse :: proc(source:rawptr,project:^Story_Project)->bool {return true}
story_test_domain_validate :: proc(project:^Story_Project,result:^Story_Validation) {}
story_test_domain_compile :: proc(project:^Story_Project)->bool {return true}
story_test_domain_state_create :: proc(project:^Story_Project)->rawptr {value:=new(u64);value^=7;return value}
story_test_domain_state_clone :: proc(state:rawptr)->rawptr {if state==nil do return nil;value:=new(u64);value^=(cast(^u64)state)^;return value}
story_test_domain_state_destroy :: proc(state:rawptr) {if state!=nil do free(state)}

story_test_spatial_query :: proc(userdata:rawptr,query:Story_Spatial_Query)->Story_Spatial_Result {
	if query.a.space_id=="unloaded" do return {.Unavailable,false,0,"space is unloaded"}
	switch query.kind {
	case .Present:return {.Available,true,0,"target is present"}
	case .Contained_By:return {.Available,query.b.target_id=="courtyard",0,"containment checked"}
	case .Distance:return {.Available,false,3,"distance measured"}
	case .Visible:return {.Available,true,0,"visibility checked"}
	case .Reachable:return {.Available,true,0,"reachability checked"}
	case .Travel_Time:return {.Available,false,12,"transition route measured"}
	}
	return {.Missing,false,0,"target is missing"}
}
story_test_spatial_begin :: proc(userdata:rawptr)->bool {state:=cast(^Story_Test_Spatial)userdata;state.began=true;state.staged_count=0;return true}
story_test_spatial_stage :: proc(userdata:rawptr,command:Story_Spatial_Command)->bool {state:=cast(^Story_Test_Spatial)userdata;if command.target.target_id=="reject" do return false;state.staged[state.staged_count]=command;state.staged_count+=1;return true}
story_test_spatial_commit :: proc(userdata:rawptr)->bool {state:=cast(^Story_Test_Spatial)userdata;state.committed=true;return true}
story_test_spatial_rollback :: proc(userdata:rawptr) {state:=cast(^Story_Test_Spatial)userdata;state.rolled_back=true;state.staged_count=0}

run_story_spatial_tests :: proc() {
	fixture:=Story_Test_Spatial{}
	service:=Story_Spatial_Service{userdata=&fixture,query=story_test_spatial_query,begin=story_test_spatial_begin,stage=story_test_spatial_stage,commit=story_test_spatial_commit,rollback=story_test_spatial_rollback}
	a:=Story_Spatial_Id{"vale_house","ada"};b:=Story_Spatial_Id{"vale_house","courtyard"}
	kinds:=[6]Story_Condition_Kind{.Spatial_Present,.Spatial_Contained_By,.Spatial_Distance,.Spatial_Visible,.Spatial_Reachable,.Spatial_Travel_Time}
	for kind in kinds {limit:=f32(4);if kind==.Spatial_Travel_Time do limit=15;condition:=Story_Condition{kind=kind,spatial_a=a,spatial_b=b,distance=limit};result:=story_spatial_condition(&service,&condition);assert(result.value)}
	unavailable:=Story_Condition{kind=.Spatial_Present,spatial_a={"unloaded","ada"}};assert(!story_spatial_condition(&service,&unavailable).value)
	project:=Story_Project{version=STORY_PROJECT_VERSION,id="spatial",title="Spatial"};defer story_project_destroy(&project)
	append(&project.effects,Story_Effect{kind=.Spatial_Command,spatial_command=.Set_Visible,spatial_target=a,world_enabled=true})
	state:=story_state_new(&project);defer story_state_destroy(&state);indices:=[1]int{0}
	result:=story_apply_transaction(&project,&state,indices[:],&service);assert(result.ok&&fixture.began&&fixture.committed&&fixture.staged_count==1)
	fixture={};project.effects[0].spatial_target.target_id="reject";failed:=story_apply_transaction(&project,&state,indices[:],&service);assert(!failed.ok&&fixture.rolled_back&&fixture.staged_count==0)
}

run_story_domain_lifecycle_tests :: proc() {
	_=story_domain_register({id="test_domain",version="1",parse=story_test_domain_parse,clone=story_test_domain_clone,destroy=story_test_domain_destroy,validate=story_test_domain_validate,compile=story_test_domain_compile,hash=story_test_domain_hash,serialize=story_test_domain_serialize,state_create=story_test_domain_state_create,state_clone=story_test_domain_state_clone,state_destroy=story_test_domain_state_destroy})
	_=story_domain_register({id="test_domain_two",version="1",parse=story_test_domain_parse,clone=story_test_domain_clone,destroy=story_test_domain_destroy,validate=story_test_domain_validate,compile=story_test_domain_compile,hash=story_test_domain_hash,serialize=story_test_domain_serialize,state_create=story_test_domain_state_create,state_clone=story_test_domain_state_clone,state_destroy=story_test_domain_state_destroy})
	project:=Story_Project{version=STORY_PROJECT_VERSION,id="domain_lifecycle",title="Domain lifecycle"};payload:=new(u64);payload^=41;second_payload:=new(u64);second_payload^=42;append(&project.capabilities,Story_Capability_Requirement{id="test_domain",version="1",payload=payload},Story_Capability_Requirement{id="test_domain_two",version="1",payload=second_payload});defer story_project_destroy(&project)
	clone:=story_project_clone(&project);assert(clone.capabilities[0].payload!=nil&&clone.capabilities[0].payload!=project.capabilities[0].payload&&(cast(^u64)clone.capabilities[0].payload)^==41);story_project_destroy(&clone)
	compiled:=compile_story_project(&project);assert(compiled.ok&&compiled.story.runtime.capabilities[0].payload!=nil&&compiled.story.runtime.capabilities[0].payload!=project.capabilities[0].payload);runtime:=story_runtime_new(&compiled.story);assert(runtime.capability_state_count==2&&runtime.capability_states[0].state!=nil&&(cast(^u64)runtime.capability_states[0].state)^==7);saved:=story_runtime_save(&runtime);(cast(^u64)runtime.capability_states[0].state)^=9;assert(story_runtime_restore(&runtime,&saved)&&(cast(^u64)runtime.capability_states[0].state)^==7&&runtime.capability_state_count==2);story_runtime_save_destroy(&saved);story_runtime_destroy(&runtime);story_compile_result_destroy(&compiled)
	serialized:=story_project_serialize(&project);assert(len(serialized)>0)
}
