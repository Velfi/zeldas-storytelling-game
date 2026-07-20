package main

import "core:path/filepath"

authoring_workspace_action_apply_story_commands :: proc(story:^Story_Project,history:^Story_Authoring_History,commands:[]Story_Authoring_Command)->Story_Authoring_Result {return story_authoring_apply(story,history,commands)}

authoring_workspace_action_add_story_node :: proc(story:^Story_Project,scene_id:string,node:Story_Node,make_entry:bool)->Validation {if story==nil||scene_id==""||node.id=="" do return {false,"story node action is incomplete"};scene_index:=story_scene_index(story,scene_id);if scene_index<0 do return {false,"story scene does not exist"};for existing in story.nodes do if existing.scene_id==scene_id&&existing.id==node.id do return {false,"story node id already exists"};copy:=node;copy.scene_id=scene_id;append(&story.nodes,copy);if make_entry do story.scenes[scene_index].entry_node=node.id;story.revision+=1;validated:=story_project_validate(story);defer story_validation_destroy(&validated);if !validated.ok {ordered_remove(&story.nodes,len(story.nodes)-1);story.revision-=1;return {false,len(validated.diagnostics)>0?validated.diagnostics[0].message:"story node action failed validation"}};return {true,"STORY NODE COMMITTED THROUGH GRAPH ACTION"}}

authoring_workspace_action_create_project_case :: proc(root,project_id,project_title,case_id,case_title:string,kind:Authoring_Template_Kind,out:^Authoring_Project)->Authoring_Lifecycle_Result {
	if out==nil do return {false,"project creation destination is missing"}
	project,ok:=authoring_project_new(project_id,project_title,root);if !ok do return {false,"project template identity was rejected"}
	created:=authoring_create_case_template(&project,case_id,case_title,kind);if !created.ok do return created
	out^=project;return {true,"PROJECT AND CASE TEMPLATE CREATED THROUGH WORKSPACE ACTION"}
}

authoring_workspace_action_create_level :: proc(path,id,title:string,out:^Level_Document)->Validation {
	if path==""||out==nil do return {false,"level creation path or destination is missing"}
	if !authoring_atomic_write(path,authoring_minimal_level_text(id,title)) do return {false,"could not create initial playable level"}
	return level_load(path,out)
}

authoring_workspace_action_apply_level_commands :: proc(doc:^Level_Document,commands:[]Level_Command)->Validation {
	if doc==nil||len(commands)==0 do return {false,"build command batch is empty"}
	for command,index in commands {preview:=level_preview_transaction(doc,command);if preview.state==.Blocked do return {false,preview.message};if !level_commit_transaction(doc,command,"workspace acceptance build action") do return {false,"build command could not be committed"};_=index}
	return {true,"TYPED WORKSPACE BUILD COMMANDS COMMITTED"}
}

// Shared typed mapping boundary used by the Assets workspace and headless
// acceptance. It registers the canonical semantic usage and authors the target
// field as one operation; failures leave both registry and documents unchanged.
authoring_workspace_action_map_asset :: proc(registry:^Project_Asset_Registry,asset_id:string,target:Project_Asset_Semantic_Target,entity_id:string,story:^Story_Project=nil,level:^Level_Document=nil,campaign:^Campaign_Definition=nil)->Validation {
	if registry==nil do return {false,"asset registry is required"};index:=project_asset_index(registry,asset_id);if index<0 do return {false,"asset does not exist"};usage,valid:=project_asset_semantic_usage(registry.assets[index],target,entity_id);if !valid.ok do return valid
	switch target {case .Character_Appearance:if story==nil do return {false,"story target is required"};i:=story_entity_index(story,entity_id);if i<0 do return {false,"story entity does not exist"};story.entities[i].appearance_model_asset_ref=asset_id;story.revision+=1
	case .Prop_Model,.Material:if level==nil do return {false,"level target is required"};i:=level_object_index(level,entity_id);if i<0 do return {false,"level object does not exist"};if target==.Prop_Model do level.objects[i].model_asset_ref=asset_id;else if registry.assets[index].kind==.Texture do level.objects[i].texture_asset_ref=asset_id;else do level.objects[i].material_asset_ref=asset_id;level.revision+=1;level.dirty=true
	case .UI_Image,.Sound_Cue,.Animation:if story==nil do return {false,"story target is required"};i:=project_asset_story_node_index(story,entity_id);if i<0 do return {false,"story node does not exist"};if target==.UI_Image do story.nodes[i].ui_image_asset_ref=asset_id;else if target==.Sound_Cue do story.nodes[i].sound_cue_asset_ref=asset_id;else do story.nodes[i].animation_asset_ref=asset_id;story.revision+=1
	case .Font:if story==nil do return {false,"story target is required"};story.ui_font_asset_ref=asset_id;story.revision+=1
	case .Campaign_Thumbnail:if campaign==nil do return {false,"campaign target is required"};campaign.thumbnail=registry.assets[index].project_path!=""?registry.assets[index].project_path:registry.assets[index].source_path
	case .Catalog_Model:return {false,"catalog mapping requires the live catalog workspace"}}
	if !project_asset_registry_register_usage(registry,usage) do return {false,"asset usage could not be registered"};return {true,"ASSET MAPPED THROUGH TYPED WORKSPACE ACTION"}
}

// Path-injected actions shared by native-dialog UI wrappers and deterministic
// headless acceptance. Callers choose paths; these procedures own the same
// service, inspection, library selection, and launch transitions.
authoring_workspace_action_export :: proc(request:Authoring_Service_Export,service_root:string=".")->Authoring_Service_Result {
	config:=authoring_library_service_default_config(service_root);return authoring_service_export(&config,request)
}

authoring_workspace_action_inspect :: proc(path:string,kind:Authoring_Artifact_Kind,service_root:string=".")->Authoring_Service_Result {
	config:=authoring_library_service_default_config(service_root);checked:=authoring_service_inspect(&config,path,kind,&authoring_workspace.inspection);if checked.ok do _=authoring_workspace_resolve_inspection();authoring_workspace.picked_path=path;return {ok=checked.ok,message=checked.message,artifact=authoring_workspace.inspection.artifact}
}

authoring_workspace_action_install :: proc(library_root:string,decision:Authoring_Import_Decision=.Coexist,editable_root:string="",service_root:string=".")->Authoring_Service_Result {
	authoring_workspace.library_root=library_root;authoring_workspace.import_decision=int(decision);authoring_workspace.editable_root=editable_root
	assembly:=authoring_package_install_assemble(&authoring_workspace.inspection,{true,authoring_workspace.picked_path},{library_root!="",library_root},decision,{editable_root!="",editable_root});if !assembly.valid do return {message=assembly.message}
	config:=authoring_library_service_default_config(service_root);result:=authoring_service_install(&config,assembly.install_request);if result.ok {existing:=authoring_library_installed_index(&authoring_workspace.library,result.installed.identity);if existing<0 do append(&authoring_workspace.library.installed,result.installed);else do authoring_workspace.library.installed[existing]=result.installed;authoring_workspace.library.revision+=1;authoring_workspace.selected_library=max(0,authoring_library_installed_index(&authoring_workspace.library,result.installed.identity))};return result
}

authoring_workspace_action_select_installed :: proc(identity:Authoring_Content_Identity)->bool {index:=authoring_library_installed_index(&authoring_workspace.library,identity);if index<0 do return false;authoring_workspace.selected_library=index;return true}
authoring_workspace_action_restart_library :: proc(root:string)->Validation {delete(authoring_workspace.library.installed);delete(authoring_workspace.library.sources);delete(authoring_workspace.library.saves);delete(authoring_workspace.library.dependency_edges);authoring_workspace.library={};authoring_workspace.selected_library=0;authoring_workspace.library_root=root;return authoring_service_scan_library(root,&authoring_workspace.library)}

authoring_workspace_action_launch_story :: proc(relative_story_path:string)->Story_Runtime_Step {
	if len(authoring_workspace.library.installed)==0 do return {message="no installed library selection"};installed:=authoring_workspace.library.installed[clamp(authoring_workspace.selected_library,0,len(authoring_workspace.library.installed)-1)];path,error:=filepath.join([]string{installed.install_root,relative_story_path},context.temp_allocator);if error!=nil do return {message="installed story path is invalid"};story:Story_Project;if loaded:=load_story_project(path,&story);!loaded.ok do return {message=loaded.message};defer story_project_destroy(&story);compiled:=compile_story_project(&story);if !compiled.ok do return {message=compiled.message};defer story_compile_result_destroy(&compiled);runtime:=story_runtime_new(&compiled.story);defer story_runtime_destroy(&runtime);step:=story_runtime_enter_scene(&runtime,"opening");if step.expected==.Choice do step=story_runtime_choose(&runtime,"proceed");if step.ok&&!step.finished do step=story_runtime_advance(&runtime);return step
}

authoring_workspace_action_launch_campaign :: proc()->Story_Runtime_Step {
	if len(authoring_workspace.library.installed)==0 do return {message="no installed campaign selection"};installed:=authoring_workspace.library.installed[clamp(authoring_workspace.selected_library,0,len(authoring_workspace.library.installed)-1)];path,error:=filepath.join([]string{installed.install_root,"runtime","campaign.toml"},context.temp_allocator);if error!=nil do return {message="installed campaign path is invalid"};campaign:Campaign_Definition;if loaded:=load_campaign_manifest(path,&campaign);!loaded.ok do return {message=loaded.message};defer {delete(campaign.variables);delete(campaign.conditions);delete(campaign.effects);delete(campaign.cases)};if len(campaign.cases)==0 do return {message="installed campaign has no cases"};story:Story_Project;if loaded:=load_story_project(campaign.cases[0].story_path,&story);!loaded.ok do return {message=loaded.message};defer story_project_destroy(&story);compiled:=compile_story_project(&story);if !compiled.ok do return {message=compiled.message};defer story_compile_result_destroy(&compiled);runtime:=story_runtime_new(&compiled.story);defer story_runtime_destroy(&runtime);step:=story_runtime_enter_scene(&runtime,"opening");if step.expected==.Choice do step=story_runtime_choose(&runtime,"proceed");if step.ok&&!step.finished do step=story_runtime_advance(&runtime);return step
}

authoring_workspace_action_staged_export :: proc(title,version:string,dependency_count:int,request:Authoring_Service_Export,validation:^Authoring_Validation_Snapshot,destination,service_root:string)->Authoring_Service_Result {
	wizard:=authoring_export_wizard_begin(title,version,"",dependency_count,request);if !authoring_export_wizard_advance(&wizard).ok do return {message=wizard.message};if !authoring_export_wizard_advance(&wizard).ok do return {message=wizard.message};if checked:=authoring_export_wizard_advance(&wizard,validation);!checked.ok do return {message=checked.message};if selected:=authoring_export_wizard_advance(&wizard,destination=destination);!selected.ok do return {message=selected.message};result:=authoring_workspace_action_export(wizard.request,service_root);if result.ok do _=authoring_export_wizard_advance(&wizard,service_result=&result);return result
}
