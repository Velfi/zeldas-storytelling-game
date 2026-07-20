package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

Authoring_Recovery_Apply_Result :: struct {ok,rolled_back:bool,message:string}
Authoring_Navigation_Command :: enum {Project,Story,Mystery,Graph,Build,Campaign,Assets,Packages}
Authoring_Navigation_Dispatch :: struct {command:Authoring_Navigation_Command,target:Authoring_Navigation_Target,applied:bool}
Authoring_Playtest_Coordinator :: struct {active:bool,snapshot:Authoring_Playtest_Snapshot,validation:Authoring_Validation_Snapshot,working_playthrough:Campaign_Playthrough}
Authoring_Picker_Selection :: struct {accepted:bool,path:string}
Authoring_Package_UI_Assembly :: struct {valid:bool,message:string,export_request:Authoring_Service_Export,install_request:Authoring_Service_Install}
Authoring_Asset_Import_UI_Assembly :: struct {valid:bool,message:string,request:Project_Asset_Import_Request}
Authoring_Staged_Config_Inclusion :: struct {valid:bool,paths:[dynamic]string,message:string}

authoring_integration_counter:u64
authoring_navigation_focused_field:string

authoring_integration_temp_file :: proc(label,extension:string)->string {authoring_integration_counter+=1;return fmt.tprintf("/private/tmp/chicago-%s-%d-%d%s",label,os.get_pid(),authoring_integration_counter,extension)}

authoring_graph_from_story :: proc(story:^Story_Project)->Graph_Document {
	old_document:=graph_document;old_source:=graph_source_project;old_state:=graph_state;old_history:=new(Graph_History);old_history^=graph_history;graph_document={};graph_source_project=nil;graph_import_story(story);result:=graph_document;graph_document=old_document;graph_source_project=old_source;graph_state=old_state;graph_history=old_history^;free(old_history);return result
}

authoring_graph_layout_apply_text :: proc(doc:^Graph_Document,text:string)->Validation {
	if doc==nil do return {false,"graph recovery destination is missing"}
	for line in strings.split(text,"\n") {parts:=strings.split(line,"\t",context.temp_allocator);if len(parts)==0 do continue
		if parts[0]=="case"&&len(parts)>=2&&parts[1]!=doc.case_id do return {false,"graph recovery belongs to another case"}
		if parts[0]=="scene"&&len(parts)>=5 {index:=-1;for scene,i in doc.scenes[:doc.scene_count] do if scene.scene.id==parts[1] do index=i;x,x_ok:=strconv.parse_f32(parts[2]);y,y_ok:=strconv.parse_f32(parts[3]);zoom,z_ok:=strconv.parse_f32(parts[4]);if index>=0&&x_ok&&y_ok&&z_ok {doc.scenes[index].pan={x,y};doc.scenes[index].zoom=zoom}}
		if parts[0]=="node"&&len(parts)>=6 {index:=-1;for node,i in doc.nodes[:doc.node_count] do if node.beat.scene==parts[1]&&node.beat.id==parts[2] do index=i;x,x_ok:=strconv.parse_f32(parts[3]);y,y_ok:=strconv.parse_f32(parts[4]);if index>=0&&x_ok&&y_ok {doc.nodes[index].position={x,y};doc.nodes[index].collapsed=parts[5]=="1"}}
		if strings.has_prefix(line,"revision =") {parts:=strings.split(line,"=");if len(parts)==2 {revision,ok:=strconv.parse_u64(strings.trim_space(parts[1]));if ok do doc.revision=revision}}
	}
	// Graph validators resolve conditions/effects through the active document.
	// Recovery and case loading validate a detached draft, so temporarily make
	// that draft active without transferring or destroying any owned buffers.
	if doc==&graph_document do return graph_validate(doc)
	active:=graph_document;graph_document=doc^;checked:=graph_validate(&graph_document);doc^=graph_document;graph_document=active;return checked
}

authoring_recovery_apply :: proc(project:^Authoring_Project,item:^Authoring_Case,bundle:^Authoring_Recovery_Bundle,story:^Story_Project,graph:^Graph_Document,level:^Level_Document)->Authoring_Recovery_Apply_Result {
	if project==nil||item==nil||bundle==nil||story==nil||graph==nil||level==nil do return {message="recovery apply target is incomplete"};if current:=authoring_recovery_can_restore(item,bundle);!current.ok do return {message=current.message}
	story_path:=authoring_integration_temp_file("recovery-story",".toml");level_path:=authoring_integration_temp_file("recovery-level",".toml");defer {_ = os.remove(story_path);_ = os.remove(level_path)}
	if os.write_entire_file(story_path,transmute([]byte)bundle.documents[.Story].serialized)!=nil||os.write_entire_file(level_path,transmute([]byte)bundle.documents[.Level].serialized)!=nil do return {message="recovery documents could not be staged"}
	next_story:Story_Project;if loaded:=load_story_project(story_path,&next_story);!loaded.ok do return {rolled_back=true,message=loaded.message};next_story.revision=bundle.documents[.Story].draft_revision
	next_level:Level_Document;if loaded:=level_load(level_path,&next_level);!loaded.ok {story_project_destroy(&next_story);return {rolled_back=true,message=loaded.message}};next_level.revision=bundle.documents[.Level].draft_revision;next_level.dirty=true
	next_graph:=authoring_graph_from_story(&next_story);next_graph.revision=bundle.documents[.Graph_Layout].draft_revision;next_graph.dirty=true;if layout:=authoring_graph_layout_apply_text(&next_graph,bundle.documents[.Graph_Layout].serialized);!layout.ok {story_project_destroy(&next_story);authoring_level_document_destroy(&next_level);authoring_graph_document_destroy(&next_graph);return {rolled_back=true,message=layout.message}}
	// Commit only after every recovered document has parsed and validated.
	story_project_destroy(story);authoring_level_document_destroy(level);authoring_graph_document_destroy(graph);story^=next_story;level^=next_level;graph^=next_graph
	for kind in Authoring_Document_Kind {item.documents[kind].revision=bundle.documents[kind].draft_revision;item.documents[kind].dirty=true};return {ok=true,message="RECOVERY APPLIED ATOMICALLY"}
}

authoring_production_revisions :: proc(story:^Story_Project,graph:^Graph_Document,level:^Level_Document,campaign:^Campaign_Definition,assets:^Project_Asset_Registry)->[len(Authoring_Validation_Domain)]u64 {result:[len(Authoring_Validation_Domain)]u64;if story!=nil {result[int(Authoring_Validation_Domain.Story_Core)]=story.revision;result[int(Authoring_Validation_Domain.Mystery)]=story.revision};if graph!=nil do result[int(Authoring_Validation_Domain.Graph)]=graph.revision;if level!=nil do result[int(Authoring_Validation_Domain.Level)]=level.revision;if campaign!=nil do result[int(Authoring_Validation_Domain.Campaign)]=u64(len(campaign.cases)+len(campaign.conditions)+len(campaign.effects));if assets!=nil do result[int(Authoring_Validation_Domain.Assets)]=assets.revision;result[int(Authoring_Validation_Domain.Packaging)]=max(result[int(Authoring_Validation_Domain.Story_Core)],result[int(Authoring_Validation_Domain.Assets)]);result[int(Authoring_Validation_Domain.Compatibility)]=max(result[int(Authoring_Validation_Domain.Campaign)],result[int(Authoring_Validation_Domain.Packaging)]);return result}

authoring_production_validate :: proc(profile:Authoring_Validation_Profile,story:^Story_Project,graph:^Graph_Document,level:^Level_Document,campaign:^Campaign_Definition,assets:^Project_Asset_Registry,pkg:^Authoring_Package_Inspection)->Authoring_Validation_Snapshot {revisions:=authoring_production_revisions(story,graph,level,campaign,assets);revision:=revisions[int(Authoring_Validation_Domain.Compatibility)]+revisions[int(Authoring_Validation_Domain.Graph)]+revisions[int(Authoring_Validation_Domain.Level)];return authoring_validate_project({story=story,graph=graph,level=level,campaign=campaign,assets=assets,pkg=pkg,revisions=revisions},profile,revision)}

authoring_navigation_command :: proc(target:Authoring_Navigation_Target)->Authoring_Navigation_Command {switch target.workspace {case "project":return .Project;case "story":return .Story;case "mystery":return .Mystery;case "graph":return .Graph;case "build":return .Build;case "campaign":return .Campaign;case "assets":return .Assets;case "export","library":return .Packages};return .Project}

authoring_navigation_dispatch :: proc(diagnostic:Authoring_Diagnostic,g:^Game=nil)->Authoring_Navigation_Dispatch {
	target:=authoring_diagnostic_navigation(diagnostic);command:=authoring_navigation_command(target);result:=Authoring_Navigation_Dispatch{command=command,target=target};if g==nil do return result
	authoring_navigation_focused_field=target.field_path
	switch command {
	case .Project:g.screen=.Authoring;authoring_workspace.tab=.Project
	case .Story:g.screen=.Authoring;authoring_workspace.tab=.Story_Data;authoring_navigation_focus_story(target.entity_id)
	case .Mystery:g.screen=.Authoring;authoring_workspace.tab=.Mystery;_=authoring_navigation_focus_mystery(target.entity_id,target.field_path)
	case .Graph:
		g.screen=.Investigate;g.editor_mode=.Graph
		for node,i in graph_document.nodes[:graph_document.node_count] do if node.beat.id==target.entity_id {scene:=graph_scene_index(node.beat.scene);if scene>=0 do graph_state.active_scene=scene;graph_select_only(i);_=graph_frame_nodes(true);break}
	case .Build:
		g.screen=.Investigate;g.editor_mode=.Build
		selection:=level_selection_for_id(&level_document,target.entity_id);if selection.kind!=.None {editor_state.selection[0]=selection;editor_state.selection_count=1}
		if target.location.present {level_document.active_story=target.location.story;editor_state.cursor_world=target.location.position;editor_state.cursor_world_valid=true;g.camera_x=target.location.position.x;g.camera_y=target.location.position.y}
	case .Campaign:g.screen=.Campaign_Action;campaign_workspace_begin();_=authoring_navigation_focus_campaign(target.entity_id,target.field_path)
	case .Assets:g.screen=.Authoring;authoring_workspace.tab=.Assets;_=authoring_navigation_focus_asset(target.entity_id)
	case .Packages:g.screen=.Authoring;authoring_workspace.tab=target.workspace=="library"?.Library:.Packages;_=authoring_navigation_focus_package(target.entity_id)
	};result.applied=true;return result
}

authoring_navigation_focus_mystery :: proc(id,field:string)->bool {
	payload:=mystery_payload(&active_story_project);if payload==nil do return false
	for kind in Mystery_Authoring_Record_Kind {
		count:=authoring_mystery_count(kind);for index in 0..<count do if authoring_mystery_id(kind,index)==id {authoring_workspace.selected_category=int(kind);authoring_workspace.selected_record=index;for cursor in 0..<32 {name,_,field_count:=authoring_mystery_scalar_field(kind,cursor);if field_count==0 do break;if name==field {authoring_mystery_field_cursor=cursor;return true}};for cursor in 0..<16 {name,field_count:=authoring_mystery_list_field(kind,cursor);if field_count==0 do break;if name==field {authoring_mystery_list_cursor=cursor;return true}};return true}
	}
	if id=="solution" {authoring_workspace.selected_category=int(Mystery_Authoring_Record_Kind.Solution);authoring_workspace.selected_record=0;return true}
	return false
}

authoring_navigation_focus_campaign :: proc(id,field:string)->bool {
	doc:=&campaign_workspace.draft
	for item,index in doc.cases do if item.id==id {campaign_workspace.selected_case=index;campaign_workspace.selected_condition=item.condition_root;campaign_workspace.tab=strings.contains(field,"condition")?.Conditions:.Cases;return true}
	for item,index in doc.variables do if item.id==id {campaign_workspace.selected_variable=index;campaign_workspace.tab=.Variables;return true}
	if strings.contains(field,"effect") {campaign_workspace.tab=.Effects;return true};if strings.contains(field,"condition") {campaign_workspace.tab=.Conditions;return true};campaign_workspace.tab=.Overview;return id==doc.id||id==""
}

authoring_navigation_focus_asset :: proc(id:string)->bool {for item,index in authoring_workspace.assets.assets do if item.id==id {authoring_workspace.selected_asset=index;authoring_asset_load_selected();return true};return false}

authoring_navigation_focus_package :: proc(id:string)->bool {if authoring_workspace.inspection.artifact.identity.id==id do return true;for item,index in authoring_workspace.library.installed do if item.identity.id==id {authoring_workspace.selected_library=index;return true};return false}

authoring_navigation_focus_story :: proc(id:string)->bool {
	for kind in Story_Authoring_Record_Kind {
		count:=authoring_story_count(kind);for index in 0..<count do if authoring_story_id(kind,index)==id {authoring_workspace.selected_category=int(kind);authoring_workspace.selected_record=index;return true}
	}
	return false
}

authoring_execute_diagnostic_fix :: proc(diagnostic:Authoring_Diagnostic,ctx:^Authoring_Fix_Context,story_history:^Story_Authoring_History=nil)->Validation {if diagnostic.fix_id=="" do return {false,"diagnostic has no safe fix"};if strings.has_prefix(diagnostic.fix_id,"story.")&&ctx!=nil&&ctx.story!=nil {return {false,"story fixes require an explicit typed authoring command"}};return authoring_dispatch_safe_fix(diagnostic.fix_id,ctx)}

authoring_playtest_begin :: proc(state:^Authoring_Playtest_Coordinator,story:^Story_Project,runtime:^Story_Runtime,graph:^Graph_Document,level:^Level_Document,campaign:^Campaign_Definition,playthrough:^Campaign_Playthrough,assets:^Project_Asset_Registry,setup:^Authoring_Creator_State_Setup=nil)->Validation {
	if state==nil||state.active do return {false,"whole-project playtest is already active"};validation:=authoring_production_validate(.Playable,story,graph,level,campaign,assets,nil);if authoring_validation_is_blocked(&validation) {state.validation=validation;return {false,"playtest validation is blocking"}};revisions:=authoring_production_revisions(story,graph,level,campaign,assets);state.snapshot=authoring_playtest_snapshot_create(story,runtime,level,graph,campaign,playthrough,revisions);if playthrough!=nil do state.working_playthrough=playthrough^;state.validation=validation;state.active=true
	if setup!=nil&&runtime!=nil {scenario:=Scenario_Context{runtime=runtime^};if runtime.compiled!=nil do scenario.compiled=runtime.compiled^;applied:=authoring_apply_creator_setup(setup,&scenario,campaign,&state.working_playthrough);if !applied.ok {_=authoring_playtest_end(state,story,runtime,graph,level,campaign,playthrough);return applied};runtime^=scenario.runtime}
	return {true,"WHOLE-PROJECT PLAYTEST STARTED FROM ISOLATED SNAPSHOT"}
}

authoring_playtest_end :: proc(state:^Authoring_Playtest_Coordinator,story:^Story_Project,runtime:^Story_Runtime,graph:^Graph_Document,level:^Level_Document,campaign:^Campaign_Definition,playthrough:^Campaign_Playthrough)->Validation {
	if state==nil||!state.active do return {false,"whole-project playtest is not active"};snapshot:=&state.snapshot;if runtime!=nil&&snapshot.runtime_present do _=story_runtime_restore(runtime,&snapshot.runtime)
	if story!=nil&&snapshot.story_present {story_project_destroy(story);story^=story_project_clone(&snapshot.story)};if level!=nil&&snapshot.level_present {authoring_level_document_destroy(level);level^=level_clone_document(&snapshot.level)};if graph!=nil&&snapshot.graph_present {authoring_graph_document_destroy(graph);graph^=graph_document_clone(&snapshot.graph)};if campaign!=nil&&snapshot.campaign_present {delete(campaign.variables);delete(campaign.conditions);delete(campaign.effects);delete(campaign.cases);campaign^=campaign_clone(&snapshot.campaign)};if playthrough!=nil do playthrough^=snapshot.playthrough
	authoring_playtest_snapshot_destroy(snapshot);authoring_validation_snapshot_destroy(&state.validation);state.working_playthrough={};state.active=false;return {true,"WHOLE-PROJECT PLAYTEST ENDED AND SOURCE STATE RESTORED"}
}

authoring_package_export_assemble :: proc(project:^Authoring_Project,kind:Authoring_Artifact_Kind,destination:Authoring_Picker_Selection,config_relative:string,assets:^Project_Asset_Stage_Plan=nil,campaign_rule:^Authoring_Campaign_Bundle_Rule=nil)->Authoring_Package_UI_Assembly {result:Authoring_Package_UI_Assembly;if project==nil||!destination.accepted||destination.path=="" {result.message="package destination was not selected";return result};config_path,ok:=authoring_resolve_path(project,config_relative);if !ok||!os.is_file(config_path) {result.message="package source configuration is missing";return result};result.export_request={kind=kind,source_root=project.root_path,config_path=config_path,output_path=destination.path,skip_engine_validation=false,asset_plan=assets,campaign_rule=campaign_rule};result.valid=true;result.message="EXPORT REQUEST READY";return result}

authoring_package_install_assemble :: proc(inspection:^Authoring_Package_Inspection,package_picker,library_picker:Authoring_Picker_Selection,decision:Authoring_Import_Decision,editable_picker:Authoring_Picker_Selection={}) -> Authoring_Package_UI_Assembly {result:Authoring_Package_UI_Assembly;if inspection==nil||!package_picker.accepted||!library_picker.accepted {result.message="package and library selections are required";return result};if decision==.Editable_Copy&&!editable_picker.accepted {result.message="editable-copy destination is required";return result};result.install_request={inspection=inspection,package_path=package_picker.path,library_root=library_picker.path,editable_root=editable_picker.path,decision=decision};result.valid=true;result.message="INSTALL REQUEST READY";return result}

authoring_asset_import_assemble :: proc(project:^Authoring_Project,file_picker:Authoring_Picker_Selection,destination_relative,requested_id:string,kind:Project_Asset_Kind,mode:Project_Asset_Source_Mode,policy:Project_Asset_Embed_Policy,provenance:Project_Asset_Provenance)->Authoring_Asset_Import_UI_Assembly {result:Authoring_Asset_Import_UI_Assembly;if project==nil||!file_picker.accepted||!os.is_file(file_picker.path) {result.message="asset source file was not selected";return result};if mode==.Copy&&!authoring_relative_path_valid(destination_relative) {result.message="asset destination must be project-relative";return result};result.request={project_root=project.root_path,source_path=file_picker.path,destination_directory=destination_relative,requested_id=requested_id,kind=kind,mode=mode,embed_policy=policy,provenance=provenance};result.valid=true;result.message="ASSET IMPORT REQUEST READY";return result}

authoring_staged_config_inclusion :: proc(plan:^Project_Asset_Stage_Plan,prefix:string="project-assets")->Authoring_Staged_Config_Inclusion {result:=Authoring_Staged_Config_Inclusion{valid=true,message="STAGED ASSET INCLUDE LIST READY"};if plan==nil||!plan.allowed {result.valid=false;result.message="asset staging plan is missing or blocked";return result};for item in plan.items {path,error:=filepath.join([]string{prefix,item.package_path},context.allocator);if error!=nil||filepath.is_abs(path)||strings.contains(path,"..") {result.valid=false;result.message="staged asset include path is unsafe";return result};append(&result.paths,path)};attribution,error:=filepath.join([]string{prefix,"asset-attribution.toml"},context.allocator);if error==nil do append(&result.paths,attribution);return result}

authoring_staged_config_inclusion_destroy :: proc(result:^Authoring_Staged_Config_Inclusion){delete(result.paths);result^={}}
