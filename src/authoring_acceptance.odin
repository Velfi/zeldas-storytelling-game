package main

// A deterministic, headless acceptance path for the complete authoring loop.
// It deliberately uses a fresh root and the same public procedures as the UI;
// callers can run it from self-tests or a purpose-built developer command.

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Authoring_Acceptance_Result :: struct {
	ok: bool,
	phase, message, root: string,
	assertions: int,
}

authoring_acceptance_counter: u64

authoring_acceptance_fail :: proc(result: ^Authoring_Acceptance_Result, phase, message: string) -> Authoring_Acceptance_Result {
	result.phase = phase
	result.message = message
	return result^
}

authoring_acceptance_require :: proc(result: ^Authoring_Acceptance_Result, value: bool) -> bool {
	result.assertions += 1
	return value
}

authoring_acceptance_join :: proc(parts: ..string) -> string {
	result, error := filepath.join(parts[:], context.allocator)
	if error != nil do return ""
	return result
}

// run_authoring_acceptance owns everything below its temporary root. When
// keep_root is true the returned root is retained for failure investigation.
run_authoring_acceptance :: proc(repository_root: string, keep_root := false) -> Authoring_Acceptance_Result {
	authoring_acceptance_counter += 1
	root := fmt.tprintf("/tmp/chicago-authoring-acceptance-%d-%d", os.get_pid(), authoring_acceptance_counter)
	result := Authoring_Acceptance_Result{phase="setup", root=root}
	if os.exists(root) do _ = os.remove_all(root)
	if os.make_directory_all(root) != nil do return authoring_acceptance_fail(&result, "setup", "could not create clean profile root")
	defer if !keep_root do _ = os.remove_all(root)

	// Project and mystery case are created from the production templates.
	project:Authoring_Project
	created := authoring_workspace_action_create_project_case(root,"acceptance_campaign","Acceptance Campaign","acceptance_mystery","Acceptance Mystery",.Mystery,&project)
	if !authoring_acceptance_require(&result, created.ok) do return authoring_acceptance_fail(&result, "template", created.message)
	item := authoring_project_active_case(&project)
	if !authoring_acceptance_require(&result, item != nil) do return authoring_acceptance_fail(&result, "template", "template did not select its case")
	story_path, story_path_ok := authoring_resolve_path(&project, item.paths.story)
	level_path, level_path_ok := authoring_resolve_path(&project, item.paths.level)
	if !authoring_acceptance_require(&result, story_path_ok && level_path_ok) do return authoring_acceptance_fail(&result, "template", "template paths were unsafe")

	story: Story_Project
	loaded_story := load_story_project(story_path, &story)
	if !authoring_acceptance_require(&result, loaded_story.ok) do return authoring_acceptance_fail(&result, "story", loaded_story.message)
	defer story_project_destroy(&story)
	// Conditional conversation and its Story records are committed through the
	// same typed transaction boundary as the Story workspace.
	story_history:Story_Authoring_History;defer story_authoring_history_destroy(&story_history)
	story_commands:=[7]Story_Authoring_Command{
		{kind=.Add,record_kind=.Variable,variable={id="evidence_ready",display_name="Evidence ready",kind=.Boolean,default_value=story_value_boolean(true)}},
		{kind=.Add,record_kind=.Condition,condition={id="evidence_ready_cond",kind=.Value_Equals,variable_id="evidence_ready",value=story_value_boolean(true)}},
		{kind=.Add,record_kind=.Entity,entity={id="acceptance_character_a",kind="person",display_name="Acceptance Character A"}},
		{kind=.Add,record_kind=.Entity,entity={id="acceptance_character_b",kind="person",display_name="Acceptance Character B"}},
		{kind=.Add,record_kind=.Proposition,proposition={id="acceptance_proposition",text="The acceptance evidence identifies the culprit."}},
		{kind=.Add,record_kind=.Fact,fact={id="acceptance_fact",display_name="Acceptance Fact",proposition="acceptance_proposition",canonical_truth=.True,player_visible=true}},
		{kind=.Add,record_kind=.Ending,ending={id="acceptance_ending",title="Case Solved",summary="The contradiction closes the case.",priority=1}},
	}
	story_authored:=authoring_workspace_action_apply_story_commands(&story,&story_history,story_commands[:]);defer story_authoring_result_destroy(&story_authored);if !authoring_acceptance_require(&result,story_authored.ok) do return authoring_acceptance_fail(&result,"story",story_authored.message)
	choice := Story_Node{id="conditional_conversation", scene_id="opening", kind=.Choice, ui="dialogue", camera="evidence_camera", actor="culprit", actor_mark="evidence_staging", domain_ref="evidence_interaction_marker", choice_count=1}
	choice.choices[0] = {id="proceed", label="Present the evidence", target="opening_end", condition_id="evidence_ready_cond"}
	if authored_node:=authoring_workspace_action_add_story_node(&story,"opening",choice,true);!authoring_acceptance_require(&result,authored_node.ok) do return authoring_acceptance_fail(&result,"graph",authored_node.message)
	// Mystery metadata is committed through the typed transactional authoring
	// surface, including dependencies created together in one atomic change.
	mystery_history: Mystery_Authoring_History
	defer mystery_authoring_history_destroy(&mystery_history)
	mystery_commands := make([dynamic]Mystery_Authoring_Command, 0, 11)
	defer delete(mystery_commands)
	claim := Mystery_Claim{id="culprit_claim", speaker_id="culprit", proposition_id="case_support", protects="culprit", response="The evidence is misleading.", canonical_truth=false}
	deduction := Mystery_Deduction{id="evidence_deduction", proposition_id="case_support", category="support", support_count=1}; deduction.supports[0]="initial_clue"
	question := Mystery_Question{id="culprit_question", prompt="Who is protected by the evidence?", hypothesis_id="case_support", category="final", require_deduction_count=1, required_for_final=true}; question.requires_deductions[0]="evidence_deduction"
	dialogue := Mystery_Dialogue_Metadata{node_id="conditional_conversation", character_id="culprit", prompt="Present the evidence", response="You cannot prove it.", clue_id="initial_clue", interaction="evidence_interaction_marker", require_count=1}; dialogue.requires[0]="initial_clue"
	contradiction:=Mystery_Contradiction{id="culprit_contradiction",claim_id="culprit_claim",fact_id="acceptance_fact",conclusion_id="case_support",explanation="The authored fact contradicts the culprit's claim."}
	demonstration:=Mystery_Demonstration{id="culprit_demonstration",question_id="culprit_question",mode="evidence",resolution="supported",result="proven",prompt="Place the decisive evidence.",slot_count=1,accepted_count=1,route_count=1,result_count=1};demonstration.slot_labels[0]="Evidence";demonstration.slot_types[0]="clue";demonstration.accepted[0]="initial_clue";demonstration.route_firsts[0]=0;demonstration.route_counts[0]=1;demonstration.result_deductions[0]="evidence_deduction"
	ending:=Mystery_Ending_Metadata{ending_id="acceptance_ending",trigger="airtight",outcome="case solved",subtitle="Evidence accepted",epilogue="The contradiction closes the case.",tone="decisive",primary_label="Continue",primary_action="campaign"}
	acceptance_clue:=Mystery_Clue{id="acceptance_clue",source_id="acceptance_character_a",description="The acceptance clue identifies the culprit.",proposition_id="acceptance_proposition"}
	acceptance_solution:=mystery_payload(&story).solution;acceptance_solution.culprit_id="culprit";acceptance_solution.decisive_contradiction_id="culprit_contradiction";acceptance_solution.requirements[0]="evidence_deduction";acceptance_solution.requirement_count=1;acceptance_solution.exclusions[0]="acceptance_character_a";acceptance_solution.exclusions[1]="acceptance_character_b";acceptance_solution.exclusion_count=2
	append(&mystery_commands,
		Mystery_Authoring_Command{kind=.Add,record_kind=.Character,character={entity_id="acceptance_character_a",private_secret="Witnessed the decisive evidence.",motive="Tell the truth",initial_disposition=1}},
		Mystery_Authoring_Command{kind=.Add,record_kind=.Character,character={entity_id="acceptance_character_b",private_secret="Was elsewhere.",motive="Avoid suspicion",initial_disposition=0}},
		Mystery_Authoring_Command{kind=.Add,record_kind=.Clue,clue=acceptance_clue},
		Mystery_Authoring_Command{kind=.Add,record_kind=.Claim,claim=claim},
		Mystery_Authoring_Command{kind=.Add,record_kind=.Contradiction,contradiction=contradiction},
		Mystery_Authoring_Command{kind=.Add,record_kind=.Deduction,deduction=deduction},
		Mystery_Authoring_Command{kind=.Add,record_kind=.Question,question=question},
		Mystery_Authoring_Command{kind=.Add,record_kind=.Demonstration,demonstration=demonstration},
		Mystery_Authoring_Command{kind=.Add,record_kind=.Dialogue,dialogue=dialogue},
		Mystery_Authoring_Command{kind=.Add,record_kind=.Ending,ending=ending},
		Mystery_Authoring_Command{kind=.Update,record_kind=.Solution,solution=acceptance_solution},
	)
	mystery_authored := mystery_authoring_apply(&story, &mystery_history, mystery_commands[:])
	defer mystery_authoring_result_destroy(&mystery_authored)
	if !authoring_acceptance_require(&result, mystery_authored.ok) {detail:=mystery_authored.message;if len(mystery_authored.validation.diagnostics)>0 do detail=fmt.tprintf("%s: %s",detail,mystery_authored.validation.diagnostics[0].message);return authoring_acceptance_fail(&result, "mystery", detail)}
	payload:=mystery_payload(&story);if !authoring_acceptance_require(&result,payload!=nil&&story_entity_index(&story,"acceptance_character_a")>=0&&story_entity_index(&story,"acceptance_character_b")>=0&&story_proposition_index(&story,"acceptance_proposition")>=0&&mystery_clue_index(payload,"acceptance_clue")>=0&&mystery_authoring_contradiction_index(payload,"culprit_contradiction")>=0&&mystery_authoring_demonstration_index(payload,"culprit_demonstration")>=0&&mystery_authoring_ending_index(payload,"acceptance_ending")>=0&&payload.solution.culprit_id=="culprit"&&payload.solution.requirement_count==1&&payload.solution.requirements[0]=="evidence_deduction"&&payload.solution.exclusion_count==2&&payload.solution.exclusions[0]=="acceptance_character_a"&&payload.solution.exclusions[1]=="acceptance_character_b") do return authoring_acceptance_fail(&result,"mystery","required created records, solution route, culprit, or exclusions were not authored")
	if saved := save_story_project(story_path, &story); !authoring_acceptance_require(&result, saved.ok) do return authoring_acceptance_fail(&result, "story", saved.message)

	// One playable room with every binding required by the mystery template.
	// The intentionally skeletal template has no spawn and therefore cannot be
	// loaded as playable until its first authored marker exists.
	level: Level_Document
	loaded_level := authoring_workspace_action_create_level(level_path,story.id,story.title,&level)
	if !authoring_acceptance_require(&result, loaded_level.ok) do return authoring_acceptance_fail(&result, "build", loaded_level.message)
	defer authoring_level_document_destroy(&level)
	trigger_reference := len(story.events)>0 ? story.events[0].id : "acceptance_trigger_event"
	build_commands:=make([dynamic]Level_Command,0,12);defer delete(build_commands)
	foundation_command:=Level_Command{kind=.Create_Foundation,entity_id="evidence_foundation",c={f32(Level_Foundation_Kind.Slab),.25},point_count=4};foundation_command.points[0]={2,2};foundation_command.points[1]={12,2};foundation_command.points[2]={12,12};foundation_command.points[3]={2,12};append(&build_commands,foundation_command)
	room_command:=Level_Command{kind=.Create_Room_Polygon,entity_id="evidence_room",material="wood",point_count=4};room_command.points[0]={2.25,2.25};room_command.points[1]={11.75,2.25};room_command.points[2]={11.75,11.75};room_command.points[3]={2.25,11.75};append(&build_commands,room_command)
	marker_specs:=[8]struct{id,reference:string,kind:Level_Marker_Kind,position:Vec2,radius,facing,height:f32}{{"culprit_spawn","culprit",.Character_Spawn,{6,8},.5,0,0},{"suspect_a_spawn","suspect_a",.Character_Spawn,{8,8},.5,0,0},{"suspect_b_spawn","suspect_b",.Character_Spawn,{10,8},.5,0,0},{"evidence_spawn","evidence_source",.Clue,{8,5},.5,0,0},{"evidence_interaction_marker","initial_clue",.Interaction,{8,5.75},1.25,0,0},{"evidence_trigger",trigger_reference,.Trigger,{7,5},1.25,0,0},{"evidence_camera","",.Camera,{8,10},.5,270,2.2},{"evidence_staging","",.Staging,{9,7},.5,180,0}}
	for spec in marker_specs do append(&build_commands,Level_Command{kind=.Add_Marker,entity_id=spec.id,a=spec.position,b={spec.radius,spec.facing},c={spec.height,f32(spec.kind)},material=spec.reference})
	append(&build_commands,Level_Command{kind=.Place_Object,entity_id="evidence_interaction",a={8,5},material="table"},Level_Command{kind=.Set_Interaction,entity_id="evidence_interaction",interaction=.Toggle,interaction_prompt="Inspect evidence",interaction_range=2,initially_active=true,powered=true})
	built:=authoring_workspace_action_apply_level_commands(&level,build_commands[:]);if !authoring_acceptance_require(&result,built.ok) do return authoring_acceptance_fail(&result,"build",built.message)
	if !authoring_acceptance_require(&result, len(level.markers)==9 && level.markers[0].kind==.Player_Spawn && level_marker_index(&level,"evidence_interaction_marker")>=0) do return authoring_acceptance_fail(&result, "build", "required player, character, interaction, clue, trigger, camera, and staging markers were not authored")
	if saved := level_save(level_path, &level); !authoring_acceptance_require(&result, saved.ok) do return authoring_acceptance_fail(&result, "build", saved.message)

	// Import three distinct production fixtures with complete attribution.
	assets: Project_Asset_Registry
	defer project_asset_registry_destroy(&assets)
	provenance := Project_Asset_Provenance{source_uri="https://kenney.nl/assets", source_name="Bundled acceptance fixture", creator="Kenney", attribution="Kenney assets", license_id="CC0-1.0", license_text="Creative Commons Zero", redistribution_permitted=true}
	fixtures := [3]struct {source, destination, id:string, kind:Project_Asset_Kind}{
		{"assets/ui/campaigns/unsorted-cases-hero.png", "assets/thumbnail", "acceptance_thumbnail", .Thumbnail},
		{"assets/kenney_furniture-kit/Models/GLTF format/lampSquareTable.glb", "assets/props", "acceptance_prop", .Model},
		{"assets/kenney_ui-audio/Audio/switch34.ogg", "assets/audio", "acceptance_audio", .Audio},
	}
	for fixture in fixtures {
		source := authoring_acceptance_join(repository_root, fixture.source)
		imported := project_asset_import(&assets, {project_root=root, source_path=source, destination_directory=fixture.destination, requested_id=fixture.id, kind=fixture.kind, mode=.Copy, embed_policy=.Embed, provenance=provenance})
		if !authoring_acceptance_require(&result, imported.ok) do return authoring_acceptance_fail(&result, "assets", imported.message)
	}
	object_index:=level_object_index(&level,"evidence_interaction");node_index:=project_asset_story_node_index(&story,"opening");if node_index<0&&len(story.nodes)>0 do node_index=0
	if !authoring_acceptance_require(&result,object_index>=0&&node_index>=0) do return authoring_acceptance_fail(&result,"assets","authored prop or opening node was not available for typed mapping")
	prop_mapping:=authoring_workspace_action_map_asset(&assets,"acceptance_prop",.Prop_Model,"evidence_interaction",level=&level);audio_mapping:=authoring_workspace_action_map_asset(&assets,"acceptance_audio",.Sound_Cue,story.nodes[node_index].id,story=&story)
	if !authoring_acceptance_require(&result,prop_mapping.ok&&audio_mapping.ok) do return authoring_acceptance_fail(&result,"assets","production typed asset mapper did not author prop/audio fields")
	if saved:=level_save(level_path,&level);!authoring_acceptance_require(&result,saved.ok) do return authoring_acceptance_fail(&result,"assets",saved.message)
	if saved:=save_story_project(story_path,&story);!authoring_acceptance_require(&result,saved.ok) do return authoring_acceptance_fail(&result,"assets",saved.message)
	asset_plan := project_asset_plan_stage(&assets, root, "assets")
	defer project_asset_stage_plan_destroy(&asset_plan)
	if !authoring_acceptance_require(&result, asset_plan.allowed && len(asset_plan.items)==3) do return authoring_acceptance_fail(&result, "assets", "attributed assets were not packageable")
	prop_metadata := assets.assets[project_asset_index(&assets,"acceptance_prop")].technical
	audio_metadata := assets.assets[project_asset_index(&assets,"acceptance_audio")].technical
	if !authoring_acceptance_require(&result, prop_metadata.model.mesh_count>0 && prop_metadata.model.material_count>0 && prop_metadata.model.bounds_min.x<prop_metadata.model.bounds_max.x && prop_metadata.model.bounds_min.y<prop_metadata.model.bounds_max.y && prop_metadata.model.up_axis=="+Y" && prop_metadata.model.forward_axis=="+Z") do return authoring_acceptance_fail(&result, "assets", "GLB orientation, bounds, or material metadata was not inspected")
	if !authoring_acceptance_require(&result, audio_metadata.audio.channels>0 && audio_metadata.audio.sample_rate>0 && audio_metadata.audio.duration_seconds>0) do return authoring_acceptance_fail(&result, "assets", "OGG channel, sample-rate, or duration metadata was not inspected")

	// Campaign records pin the distinct case content version through one typed,
	// undoable Campaign workspace transaction.
	saved_campaign_workspace:=new(Campaign_Workspace_State);saved_campaign_workspace^=campaign_workspace;campaign_workspace={draft={}}
	campaign_actions:=[3]Campaign_Workspace_Action{{kind=.Set_Metadata,metadata={version="MysteryCampaign v2",id="acceptance_campaign",title="Acceptance Campaign",creator="Acceptance Harness",description="Clean-profile acceptance",content_version="2.0.0"}},{kind=.Add_Condition,condition={kind=.Always}},{kind=.Add_Case,case_value={id="acceptance_mystery",title="Acceptance Mystery",story_path=item.paths.story,level_path=item.paths.level,case_content_version="1.0.0",condition_root=0,required=true}}}
	campaign_authored:=campaign_workspace_apply_actions(campaign_actions[:]);if !authoring_acceptance_require(&result,campaign_authored.ok&&campaign_workspace.dirty&&campaign_workspace.history.undo_count==1) do return authoring_acceptance_fail(&result,"campaign",campaign_authored.message)
	campaign:=campaign_clone(&campaign_workspace.draft);defer campaign_destroy(&campaign);campaign_destroy(&campaign_workspace.draft);campaign_workspace=saved_campaign_workspace^;free(saved_campaign_workspace)
	thumbnail_mapping:=authoring_workspace_action_map_asset(&assets,"acceptance_thumbnail",.Campaign_Thumbnail,campaign.id,campaign=&campaign);if !authoring_acceptance_require(&result,thumbnail_mapping.ok) do return authoring_acceptance_fail(&result,"assets","production typed asset mapper did not author campaign thumbnail")
	campaign_path := authoring_acceptance_join(root, "campaign.toml")
	if saved := save_campaign_manifest(campaign_path, &campaign); !authoring_acceptance_require(&result, saved.ok) do return authoring_acceptance_fail(&result, "campaign", saved.message)
	committed_snapshot:=new(Authoring_Story_Export_Snapshot);defer {authoring_story_export_snapshot_destroy(committed_snapshot);free(committed_snapshot)};if loaded:=authoring_story_export_snapshot_load(&project,item,committed_snapshot);!authoring_acceptance_require(&result,loaded.ok) do return authoring_acceptance_fail(&result,"snapshot",loaded.message)
	committed_story_hash,committed_story_hashed:=project_asset_sha256_file(story_path);committed_level_hash,committed_level_hashed:=project_asset_sha256_file(level_path);snapshot_node:=project_asset_story_node_index(&committed_snapshot.story,story.nodes[node_index].id);snapshot_object:=level_object_index(&committed_snapshot.level,"evidence_interaction");if !authoring_acceptance_require(&result,committed_story_hashed.ok&&committed_level_hashed.ok&&snapshot_node>=0&&snapshot_object>=0&&committed_snapshot.story.nodes[snapshot_node].sound_cue_asset_ref=="acceptance_audio"&&committed_snapshot.level.objects[snapshot_object].model_asset_ref=="acceptance_prop") do return authoring_acceptance_fail(&result,"snapshot","committed snapshot did not reload the saved authored identity and asset mappings")

	// Export and install the authored case as a distinct, immutable version via
	// the same library service used by the Packages workspace.
	package_config := authoring_acceptance_join(root, "story.package.json")
	package_path := authoring_acceptance_join(root, "acceptance-mystery.interactive-story")
	config_text := fmt.tprintf("{{\"author\":\"Acceptance Harness\",\"description\":\"Clean-profile acceptance\",\"content_version\":\"1.0.0\",\"story\":\"%s\",\"level\":\"%s\",\"thumbnail\":\"assets/thumbnail/unsorted-cases-hero.png\",\"include\":[\"assets\"],\"acknowledge_incomplete_validation\":true}}", item.paths.story, item.paths.level)
	if !authoring_acceptance_require(&result, authoring_atomic_write(package_config, config_text)) do return authoring_acceptance_fail(&result, "export", "could not write story package configuration")
	saved_validation_level:=level_document;saved_validation_story:=graph_source_project;saved_validation_graph:=graph_document;level_document=committed_snapshot.level;graph_source_project=&committed_snapshot.story;graph_document=committed_snapshot.graph
	export_validation:=authoring_production_validate(.Exportable,&committed_snapshot.story,&graph_document,&committed_snapshot.level,nil,&assets,nil);committed_snapshot.graph=graph_document;level_document=saved_validation_level;graph_source_project=saved_validation_story;graph_document=saved_validation_graph;defer authoring_validation_snapshot_destroy(&export_validation)
	if authoring_validation_is_blocked(&export_validation) {detail:="production exportable validation blocked";if len(export_validation.diagnostics)>0 {issue:=export_validation.diagnostics[0];detail=fmt.tprintf("%v/%s/%s: %s",issue.domain,issue.entity_id,issue.field_path,issue.message)};return authoring_acceptance_fail(&result,"export-validation",detail)}
	exported := authoring_workspace_action_staged_export(story.title,story.content_version,len(story.expansion_requirements),{kind=.Story, source_root=root, config_path=package_config, skip_engine_validation=true, asset_plan=&asset_plan},&export_validation,package_path,repository_root)
	if !authoring_acceptance_require(&result, exported.ok) do return authoring_acceptance_fail(&result, "export", exported.message)
	authoring_workspace={};inspected:=authoring_workspace_action_inspect(package_path,.Story,repository_root);if !authoring_acceptance_require(&result, inspected.ok && authoring_workspace.inspection.artifact.identity.content_version=="1.0.0") do return authoring_acceptance_fail(&result, "export", inspected.message)
	library_root := authoring_acceptance_join(root, "library")
	installed := authoring_workspace_action_install(library_root,.Coexist,"",repository_root)
	if !authoring_acceptance_require(&result, installed.ok && installed.installed.install_root!=root) do return authoring_acceptance_fail(&result, "install", installed.message)
	installed_assets := [4]string{"assets/acceptance_thumbnail.png", "assets/acceptance_prop.glb", "assets/acceptance_audio.ogg", "assets/asset-attribution.toml"}
	for relative in installed_assets {
		path := authoring_acceptance_join(installed.installed.install_root, relative)
		if !authoring_acceptance_require(&result, os.is_file(path)) do return authoring_acceptance_fail(&result, "install-assets", fmt.tprintf("installed package omitted %s", relative))
	}
	attribution_path := authoring_acceptance_join(installed.installed.install_root, "assets/asset-attribution.toml")
	attribution_bytes, attribution_error := os.read_entire_file_from_path(attribution_path, context.temp_allocator)
	if !authoring_acceptance_require(&result, attribution_error==nil && strings.contains(string(attribution_bytes), "CC0-1.0") && strings.contains(string(attribution_bytes), "acceptance_audio") && strings.contains(string(attribution_bytes), "sound_cue_asset_ref") && strings.contains(string(attribution_bytes), "prop.model_asset_ref")) do return authoring_acceptance_fail(&result, "install-assets", "installed attribution or usage metadata is incomplete")
	installed_story_path:=authoring_acceptance_join(installed.installed.install_root,item.paths.story);installed_level_path:=authoring_acceptance_join(installed.installed.install_root,item.paths.level);installed_story:Story_Project;installed_level:Level_Document
	if !authoring_acceptance_require(&result,load_story_project(installed_story_path,&installed_story).ok&&level_load(installed_level_path,&installed_level).ok) do return authoring_acceptance_fail(&result,"install-assets","installed authored documents could not be loaded")
	installed_node:=project_asset_story_node_index(&installed_story,story.nodes[node_index].id);installed_object:=level_object_index(&installed_level,"evidence_interaction");installed_prop_path:=authoring_acceptance_join(installed.installed.install_root,"assets/acceptance_prop.glb");installed_audio_path:=authoring_acceptance_join(installed.installed.install_root,"assets/acceptance_audio.ogg");installed_prop_metadata:Project_Asset_Technical_Metadata;audio_channels,audio_rate:i32;audio_samples:[^]i16;audio_frames:=stb_vorbis_decode_filename(strings.clone_to_cstring(installed_audio_path,context.temp_allocator),&audio_channels,&audio_rate,&audio_samples)
	if audio_samples!=nil do chicago_vorbis_free(audio_samples)
	if !authoring_acceptance_require(&result,installed_node>=0&&installed_story.nodes[installed_node].sound_cue_asset_ref=="acceptance_audio"&&installed_object>=0&&installed_level.objects[installed_object].model_asset_ref=="acceptance_prop"&&project_asset_inspect_file(installed_prop_path,&installed_prop_metadata).ok&&installed_prop_metadata.model.mesh_count>0&&audio_frames>0&&audio_channels>0&&audio_rate>0) do return authoring_acceptance_fail(&result,"install-assets","installed typed prop/audio references were not runtime-consumable")
	story_project_destroy(&installed_story);authoring_level_document_destroy(&installed_level)

	campaign_config := authoring_acceptance_join(root, "campaign.package.json")
	campaign_package := authoring_acceptance_join(root, "acceptance-campaign.mystery-campaign")
	campaign_config_text := "{\"campaign\":\"campaign.toml\",\"author\":\"Acceptance Harness\",\"description\":\"Clean-profile campaign acceptance\",\"content_version\":\"2.0.0\",\"cases\":[\"acceptance-mystery.interactive-story\"]}"
	if !authoring_acceptance_require(&result, authoring_atomic_write(campaign_config, campaign_config_text)) do return authoring_acceptance_fail(&result, "campaign-export", "could not write campaign package configuration")
	bundle_rule := Authoring_Campaign_Bundle_Rule{}
	defer delete(bundle_rule.cases)
	append(&bundle_rule.cases, Authoring_Campaign_Bundle_Case{id=story.id, version=story.content_version, package_path=package_path})
	saved_validation_level=level_document;saved_validation_story=graph_source_project;saved_validation_graph=graph_document;level_document=committed_snapshot.level;graph_source_project=&committed_snapshot.story;graph_document=committed_snapshot.graph;campaign_validation:=authoring_production_validate(.Exportable,&committed_snapshot.story,&graph_document,&committed_snapshot.level,&campaign,&assets,nil);committed_snapshot.graph=graph_document;level_document=saved_validation_level;graph_source_project=saved_validation_story;graph_document=saved_validation_graph;defer authoring_validation_snapshot_destroy(&campaign_validation);campaign_exported := authoring_workspace_action_staged_export(campaign.title,campaign.content_version,len(campaign.cases),{kind=.Campaign, source_root=root, config_path=campaign_config, campaign_rule=&bundle_rule},&campaign_validation,campaign_package,repository_root)
	if !authoring_acceptance_require(&result, campaign_exported.ok) do return authoring_acceptance_fail(&result, "campaign-export", campaign_exported.message)
	after_export_story_hash,after_export_story_hashed:=project_asset_sha256_file(story_path);after_export_level_hash,after_export_level_hashed:=project_asset_sha256_file(level_path);if !authoring_acceptance_require(&result,after_export_story_hashed.ok&&after_export_level_hashed.ok&&after_export_story_hash==committed_story_hash&&after_export_level_hash==committed_level_hash) do return authoring_acceptance_fail(&result,"snapshot","export did not consume the immutable committed snapshot")
	inspected=authoring_workspace_action_inspect(campaign_package,.Campaign,repository_root);if !authoring_acceptance_require(&result, inspected.ok && authoring_workspace.inspection.case_count==1) do return authoring_acceptance_fail(&result, "campaign-export", inspected.message)
	campaign_library := authoring_acceptance_join(root, "campaign-library")
	campaign_installed := authoring_workspace_action_install(campaign_library,.Coexist,"",repository_root)
	if !authoring_acceptance_require(&result, campaign_installed.ok) do return authoring_acceptance_fail(&result, "campaign-install", campaign_installed.message)
	if restarted:=authoring_workspace_action_restart_library(campaign_library);!authoring_acceptance_require(&result,restarted.ok) do return authoring_acceptance_fail(&result,"campaign-restart",restarted.message)
	if !authoring_acceptance_require(&result,authoring_workspace_action_select_installed(campaign_installed.installed.identity)) do return authoring_acceptance_fail(&result,"campaign-launch","installed campaign could not be selected from the library");embedded_step:=authoring_workspace_action_launch_campaign()
	if !authoring_acceptance_require(&result, embedded_step.ok && embedded_step.finished) do return authoring_acceptance_fail(&result, "campaign-launch", "campaign-embedded case did not complete")

	// Unified validation and diagnostic navigation are both exercised headlessly.
	graph := authoring_graph_from_story(&story)
	defer authoring_graph_document_destroy(&graph)
	snapshot := authoring_production_validate(.Draft, &story, &graph, &level, &campaign, &assets, nil)
	defer authoring_validation_snapshot_destroy(&snapshot)
	if !authoring_acceptance_require(&result, snapshot.revision > 0) do return authoring_acceptance_fail(&result, "validation", "unified validation did not run")
	for reported in snapshot.diagnostics {
		reported_navigation := authoring_navigation_dispatch(reported)
		if !authoring_acceptance_require(&result, reported_navigation.target.workspace!="" && reported_navigation.target.entity_id==reported.entity_id && reported_navigation.target.field_path==reported.field_path) do return authoring_acceptance_fail(&result, "validation", fmt.tprintf("reported diagnostic could not navigate to %s.%s", reported.entity_id, reported.field_path))
	}
	blocking_graph:=authoring_graph_from_story(&story);defer authoring_graph_document_destroy(&blocking_graph);diagnostic_node_index:=-1;for node,i in blocking_graph.nodes[:blocking_graph.node_count] do if node.beat.scene=="opening"&&node.beat.id=="conditional_conversation" {diagnostic_node_index=i;break};blocking:=authoring_validation_snapshot_init(.Draft,blocking_graph.revision);authoring_validation_add(&blocking,authoring_diagnostic_init(.Graph,"graph","conditional_conversation","camera",.Blocking,"acceptance blocking navigation probe"));defer authoring_validation_snapshot_destroy(&blocking);if !authoring_acceptance_require(&result,authoring_validation_is_blocked(&blocking)&&len(blocking.diagnostics)>0) do return authoring_acceptance_fail(&result,"validation","blocking diagnostic fixture was vacuous")
	graph_document=blocking_graph;focus_game:=Game{};focused:=false;for reported in blocking.diagnostics {navigation:=authoring_navigation_dispatch(reported,&focus_game);if navigation.command==.Graph&&graph_state.selected_node>=0 {focused=true;break}};if !authoring_acceptance_require(&result,focused&&focus_game.editor_mode==.Graph&&graph_state.selected_node==diagnostic_node_index) do return authoring_acceptance_fail(&result,"validation","blocking Graph diagnostic did not focus its authored node")
	// The exact clean-profile scenario produces and dispatches one non-vacuous
	// Blocking diagnostic for every unified validation domain. This verifies the
	// domain router itself in addition to the real Graph field focus above.
	asset_probe_index:=len(authoring_workspace.assets.assets);append(&authoring_workspace.assets.assets,Project_Asset_Record{id="acceptance_navigation_asset"});defer ordered_remove(&authoring_workspace.assets.assets,asset_probe_index)
	clue_probe:="acceptance_clue";if payload:=mystery_payload(&story);payload!=nil&&len(payload.clues)>0 do clue_probe=payload.clues[0].id
	probes:=[8]Authoring_Diagnostic{
		authoring_diagnostic_init(.Story_Core,"story",story.scenes[0].id,"entry_node",.Blocking,"acceptance Story focus probe"),
		authoring_diagnostic_init(.Mystery,"mystery",clue_probe,"description",.Blocking,"acceptance Mystery focus probe"),
		authoring_diagnostic_init(.Graph,"graph","conditional_conversation","camera",.Blocking,"acceptance Graph focus probe"),
		authoring_diagnostic_init(.Level,"level",level.markers[0].id,"radius",.Blocking,"acceptance Level focus probe"),
		authoring_diagnostic_init(.Campaign,"campaign",campaign.cases[0].id,"condition_root",.Blocking,"acceptance Campaign focus probe"),
		authoring_diagnostic_init(.Assets,"assets","acceptance_navigation_asset","provenance.license_id",.Blocking,"acceptance Asset focus probe"),
		authoring_diagnostic_init(.Packaging,"package","acceptance_package","destination",.Blocking,"acceptance Packaging focus probe"),
		authoring_diagnostic_init(.Compatibility,"package","acceptance_package","capabilities",.Blocking,"acceptance Compatibility focus probe"),
	}
	for probe in probes {routed:=authoring_navigation_dispatch(probe,&focus_game);if !authoring_acceptance_require(&result,probe.severity==.Blocking&&routed.applied&&routed.target.workspace!=""&&routed.target.entity_id==probe.entity_id&&routed.target.field_path==probe.field_path) do return authoring_acceptance_fail(&result,"validation",fmt.tprintf("%v blocking diagnostic did not focus %s.%s",probe.domain,probe.entity_id,probe.field_path))}

	// A real failed deterministic replay is persisted through the same failure
	// trace action exposed by the Diagnostics workspace.
	authoring_workspace.scenario_record=authoring_scenario_record_init("acceptance_failure","Acceptance failure trace")
	defer authoring_scenario_record_destroy(&authoring_workspace.scenario_record)
	_=authoring_scenario_record_action(&authoring_workspace.scenario_record,{action="start",value="missing_acceptance_scene"})
	failure_context:Scenario_Context
	failure_story:=authoring_acceptance_join(repository_root,"assets/stories/mysteries/the_torn_appointment.story.toml");failure_level:=authoring_acceptance_join(repository_root,"assets/levels/vale_house.toml")
	if ready:=scenario_context_init(failure_story,failure_level,&failure_context);!authoring_acceptance_require(&result,ready.ok) do return authoring_acceptance_fail(&result,"failure-trace",ready.message)
	authoring_workspace.scenario_last=authoring_scenario_replay(&authoring_workspace.scenario_record,&failure_context);scenario_context_destroy(&failure_context)
	failure_path:=authoring_acceptance_join(root,"scenario-failure.toml")
	failure_message:=authoring_workspace_export_failure(failure_path);failure_bytes,failure_error:=os.read_entire_file_from_path(failure_path,context.temp_allocator)
	if !authoring_acceptance_require(&result,strings.contains(failure_message,"EXPORTED")&&failure_error==nil&&strings.contains(string(failure_bytes),"missing_acceptance_scene")) do return authoring_acceptance_fail(&result,"failure-trace","failed replay trace was not exported with actionable context")

	// Opening and selected-state playtests execute from isolated runtime state.
	compiled := compile_story_project(&committed_snapshot.story)
	if !authoring_acceptance_require(&result, compiled.ok) do return authoring_acceptance_fail(&result, "playtest", compiled.message)
	defer story_compile_result_destroy(&compiled)
	runtime := story_runtime_new(&compiled.story)
	defer story_runtime_destroy(&runtime)
	creator_setup := Authoring_Creator_State_Setup{action_budget=1, time_minutes=-1}
	defer authoring_creator_setup_destroy(&creator_setup)
	append(&creator_setup.variables, Authoring_Creator_Variable{id="evidence_ready", value=story_value_boolean(true)})
	append(&creator_setup.knowledge, Authoring_Creator_Knowledge{kind=.Clue, id="initial_clue", present=true})
	playthrough := Campaign_Playthrough{campaign_id=campaign.id, campaign_content_version=campaign.content_version, id="acceptance-playthrough", name="Acceptance"}
	playtest:=new(Authoring_Playtest_Coordinator);defer free(playtest)
	saved_validation_level=level_document;saved_validation_story=graph_source_project;saved_validation_graph=graph_document;level_document=committed_snapshot.level;graph_source_project=&committed_snapshot.story;graph_document=committed_snapshot.graph
	started_playtest := authoring_playtest_begin(playtest, &committed_snapshot.story, &runtime, &committed_snapshot.graph, &committed_snapshot.level, &campaign, &playthrough, &assets, &creator_setup)
	committed_snapshot.graph=graph_document;level_document=saved_validation_level;graph_source_project=saved_validation_story;graph_document=saved_validation_graph
	if !authoring_acceptance_require(&result, started_playtest.ok && playtest.active) {detail:=started_playtest.message;if len(playtest.validation.diagnostics)>0 do detail=fmt.tprintf("%s: %s",detail,playtest.validation.diagnostics[0].message);return authoring_acceptance_fail(&result, "selected-state", detail)}
	selected_index := story_state_value_index(&runtime.state, "evidence_ready")
	if !authoring_acceptance_require(&result, selected_index>=0 && runtime.state.values[selected_index].value.boolean_value) do return authoring_acceptance_fail(&result, "selected-state", "creator-selected variable was not applied")
	selected_step := story_runtime_enter_scene(&runtime, "opening")
	if !authoring_acceptance_require(&result, selected_step.ok && selected_step.expected==.Choice && selected_step.node_id=="conditional_conversation") do return authoring_acceptance_fail(&result, "selected-state", "selected scene/node did not start from the creator-authored state")
	if ended_playtest := authoring_playtest_end(playtest, &committed_snapshot.story, &runtime, &committed_snapshot.graph, &committed_snapshot.level, &campaign, &playthrough); !authoring_acceptance_require(&result, ended_playtest.ok && !playtest.active) do return authoring_acceptance_fail(&result, "selected-state", ended_playtest.message)
	source_hash, source_hashed := project_asset_sha256_file(story_path)
	if !authoring_acceptance_require(&result, source_hashed.ok) do return authoring_acceptance_fail(&result, "isolation", source_hashed.message)
	step := story_runtime_enter_scene(&runtime, "opening")
	if !authoring_acceptance_require(&result, step.ok && step.expected==.Choice) do return authoring_acceptance_fail(&result, "playtest", step.message)
	step = story_runtime_choose(&runtime, "proceed")
	if !authoring_acceptance_require(&result, step.ok) do return authoring_acceptance_fail(&result, "playtest", step.message)
	step = story_runtime_advance(&runtime)
	if !authoring_acceptance_require(&result, step.ok && step.finished) do return authoring_acceptance_fail(&result, "playtest", step.message)
	if restarted:=authoring_workspace_action_restart_library(library_root);!authoring_acceptance_require(&result,restarted.ok) do return authoring_acceptance_fail(&result,"restart",restarted.message)
	if !authoring_acceptance_require(&result,authoring_workspace_action_select_installed(installed.installed.identity)) do return authoring_acceptance_fail(&result,"launch","installed story could not be selected from the library")
	installed_step := authoring_workspace_action_launch_story(item.paths.story)
	if !authoring_acceptance_require(&result, installed_step.ok && installed_step.finished) do return authoring_acceptance_fail(&result, "launch", "installed case did not complete through the runtime")

	// Reopen the source after runtime completion and prove player progress never
	// touched authoring files.
	restarted_project:Authoring_Project;if loaded:=authoring_project_load_manifest(root,&restarted_project);!authoring_acceptance_require(&result,loaded.ok) do return authoring_acceptance_fail(&result,"reopen",loaded.message);restarted_case:=authoring_project_active_case(&restarted_project);restarted_story_path,restarted_story_ok:=authoring_resolve_path(&restarted_project,restarted_case.paths.story)
	reopened: Story_Project
	if loaded := load_story_project(restarted_story_path, &reopened); !authoring_acceptance_require(&result, restarted_story_ok&&loaded.ok) do return authoring_acceptance_fail(&result, "reopen", loaded.message)
	defer story_project_destroy(&reopened)
	after_hash, after_hashed := project_asset_sha256_file(story_path)
	if !authoring_acceptance_require(&result, after_hashed.ok && after_hash==source_hash && reopened.id==story.id) do return authoring_acceptance_fail(&result, "isolation", "runtime progress changed or obscured the source project")

	result.ok = true
	result.phase = "complete"
	result.message = "CLEAN-PROFILE AUTHORING ACCEPTANCE PASSED"
	return result
}
