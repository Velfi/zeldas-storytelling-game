package main

import "core:fmt"
import "core:strings"

AUTHORING_MAX_CASES :: 64

Authoring_Document_Kind :: enum {
	Story,
	Level,
	Graph_Layout,
}

Authoring_Document_State :: struct {
	dirty:bool,
	revision, saved_revision:u64,
}

Authoring_Case_Paths :: struct {
	story, level, graph_layout:string,
	story_autosave, level_autosave, graph_layout_autosave:string,
}

Authoring_Case :: struct {
	id, title, directory:string,
	paths:Authoring_Case_Paths,
	documents:[Authoring_Document_Kind]Authoring_Document_State,
}

Authoring_Project :: struct {
	id, title, root_path:string,
	campaign_path, export_directory:string,
	cases:[AUTHORING_MAX_CASES]Authoring_Case,
	case_count, active_case:int,
	// Loaded source-project assets are transferred to the live authoring
	// workspace when the project is first bound. Keeping the pending registry on
	// the project prevents case switches from reloading over unsaved edits.
	asset_registry:Project_Asset_Registry,
	asset_registry_pending:bool,
}

authoring_stable_id_valid :: proc(id:string)->bool {
	if len(id)==0 do return false
	for ch in id {
		if !((ch>='a'&&ch<='z')||(ch>='A'&&ch<='Z')||(ch>='0'&&ch<='9')||ch=='_'||ch=='-') do return false
	}
	return true
}

// Source paths are deliberately portable project-relative paths. Rejecting
// absolute, backslash, empty, dot, and parent components makes containment a
// lexical invariant rather than something dependent on the current filesystem.
authoring_relative_path_valid :: proc(path:string)->bool {
	if len(path)==0||path[0]=='/'||strings.contains(path,"\\") do return false
	if len(path)>=2&&((path[0]>='a'&&path[0]<='z')||(path[0]>='A'&&path[0]<='Z'))&&path[1]==':' do return false
	parts,_:=strings.split(path,"/",context.temp_allocator)
	for part in parts do if part==""||part=="."||part==".." do return false
	return true
}

authoring_resolve_path :: proc(project:^Authoring_Project,relative:string)->(string,bool) {
	if project==nil||len(project.root_path)==0||!authoring_relative_path_valid(relative) do return "",false
	separator:="/"
	if project.root_path[len(project.root_path)-1]=='/' do separator=""
	return fmt.tprintf("%s%s%s",project.root_path,separator,relative),true
}

authoring_case_paths :: proc(project_id,case_id:string)->(Authoring_Case_Paths,bool) {
	if !authoring_stable_id_valid(project_id)||!authoring_stable_id_valid(case_id) do return {},false
	base:=fmt.tprintf("cases/%s",case_id)
	autosave:=fmt.tprintf(".autosave/%s/%s",project_id,case_id)
	return {
		story=fmt.tprintf("%s/story.toml",base),
		level=fmt.tprintf("%s/level.toml",base),
		graph_layout=fmt.tprintf("%s/graph.layout.toml",base),
		story_autosave=fmt.tprintf("%s/story.autosave.toml",autosave),
		level_autosave=fmt.tprintf("%s/level.autosave.toml",autosave),
		graph_layout_autosave=fmt.tprintf("%s/graph-layout.autosave.toml",autosave),
	},true
}

authoring_case_new :: proc(project_id,id,title:string)->(Authoring_Case,bool) {
	paths,ok:=authoring_case_paths(project_id,id)
	if !ok do return {},false
	return {id=id,title=title,directory=fmt.tprintf("cases/%s",id),paths=paths},true
}

authoring_project_new :: proc(id,title,root_path:string)->(Authoring_Project,bool) {
	if !authoring_stable_id_valid(id)||len(root_path)==0 do return {},false
	return {id=id,title=title,root_path=root_path,campaign_path="campaign.toml",export_directory="exports",active_case=-1},true
}

authoring_project_case_index :: proc(project:^Authoring_Project,id:string)->int {
	if project==nil do return -1
	for item,i in project.cases[:project.case_count] do if item.id==id do return i
	return -1
}

authoring_project_add_case :: proc(project:^Authoring_Project,id,title:string)->bool {
	if project==nil||project.case_count>=AUTHORING_MAX_CASES||authoring_project_case_index(project,id)>=0 do return false
	item,ok:=authoring_case_new(project.id,id,title)
	if !ok do return false
	project.cases[project.case_count]=item
	project.case_count+=1
	if project.active_case<0 do project.active_case=0
	return true
}

authoring_project_switch_case :: proc(project:^Authoring_Project,id:string)->bool {
	index:=authoring_project_case_index(project,id)
	if index<0 do return false
	project.active_case=index
	return true
}

authoring_project_active_case :: proc(project:^Authoring_Project)->^Authoring_Case {
	if project==nil||project.active_case<0||project.active_case>=project.case_count do return nil
	return &project.cases[project.active_case]
}

authoring_case_document_path :: proc(item:^Authoring_Case,kind:Authoring_Document_Kind,autosave:=false)->string {
	if item==nil do return ""
	switch kind {
	case .Story:return autosave?item.paths.story_autosave:item.paths.story
	case .Level:return autosave?item.paths.level_autosave:item.paths.level
	case .Graph_Layout:return autosave?item.paths.graph_layout_autosave:item.paths.graph_layout
	}
	return ""
}

authoring_case_mark_dirty :: proc(item:^Authoring_Case,kind:Authoring_Document_Kind,revision:u64) {
	if item==nil do return
	item.documents[kind].revision=revision
	item.documents[kind].dirty=revision!=item.documents[kind].saved_revision
}

authoring_case_mark_saved :: proc(item:^Authoring_Case,kind:Authoring_Document_Kind,revision:u64) {
	if item==nil do return
	item.documents[kind]={dirty=false,revision=revision,saved_revision=revision}
}

authoring_case_dirty :: proc(item:^Authoring_Case)->bool {
	if item==nil do return false
	for document in item.documents do if document.dirty do return true
	return false
}

authoring_project_dirty :: proc(project:^Authoring_Project)->bool {
	if project==nil do return false
	for &item in project.cases[:project.case_count] do if authoring_case_dirty(&item) do return true
	return false
}
