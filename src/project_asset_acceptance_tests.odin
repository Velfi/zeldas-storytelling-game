package main

import "core:fmt"
import "core:os"
import "core:strings"

run_project_asset_acceptance_tests :: proc() {
	root := "/private/tmp/chicago-project-asset-acceptance"
	if os.exists(root) do assert(os.remove_all(root) == nil)
	assert(os.make_directory_all(root) == nil)
	source := "assets/ui/campaigns/unsorted-cases-hero.png"
	provenance := Project_Asset_Provenance {
		source_uri               = "https://example.test/cover",
		source_name              = "Cover",
		creator                  = "Test Artist",
		attribution              = "Test Artist",
		license_id               = "CC-BY-4.0",
		license_text             = "CC BY 4.0",
		redistribution_permitted = true,
	}
	registry: Project_Asset_Registry
	defer project_asset_registry_destroy(&registry)
	request := Project_Asset_Import_Request {
		project_root          = root,
		source_path           = source,
		destination_directory = "assets/imported",
		requested_id          = "cover",
		kind                  = .Thumbnail,
		mode                  = .Copy,
		embed_policy          = .Embed,
		provenance            = provenance,
	}
	assert(project_asset_import(&registry, request).ok)
	assert(
		!project_asset_import(&registry, {project_root = root, source_path = source, destination_directory = "assets/imported", requested_id = "duplicate", kind = .Image, mode = .Copy, embed_policy = .Embed, provenance = provenance}).ok,
	)
	assert(
		project_asset_registry_register_usage(
			&registry,
			{"cover", "campaign", "acceptance", "thumbnail"},
		),
	)
	preview := project_asset_change_preview(
		&registry,
		"cover",
	); assert(len(preview.usages) == 1); project_asset_change_preview_destroy(&preview)
	assert(!project_asset_registry_remove(&registry, "cover").ok)
	before :=
		registry.assets[0]; replacement := before; replacement.kind = .Image; assert(project_asset_registry_replace(&registry, "cover", replacement).ok && len(registry.usages) == 1 && registry.usages[0].asset_id == "cover")

	owned_path := project_asset_record_path(
		root,
		registry.assets[0],
	); assert(os.is_file(owned_path)); assert(os.remove(owned_path) == nil)
	missing_plan := project_asset_plan_relink(
		&registry,
		root,
		"assets/ui/campaigns",
	); assert(len(missing_plan.missing) == 1 && len(missing_plan.candidates) >= 1)
	// Planning is a read-only review step: neither registry revision nor the
	// missing destination changes until the selected exact-hash candidate is committed.
	relink_revision :=
		registry.revision; assert(!os.is_file(owned_path) && registry.revision == relink_revision)
	assert(
		project_asset_apply_relink(&registry, root, missing_plan.candidates[0]).ok &&
		os.is_file(owned_path),
	); project_asset_relink_plan_destroy(&missing_plan)

	// Replacement is likewise explicitly previewed. The preview exposes impact,
	// validates type metadata and pins the candidate hash before any mutation.
	replacement_source := "assets/ui/evidence/bronze-statuette.png"
	replacement_preview := project_asset_preview_replacement(
		&registry,
		"cover",
		replacement_source,
	)
	assert(replacement_preview.valid && len(replacement_preview.change.usages) == 1)
	before_replacement_hash :=
		registry.assets[0].sha256; assert(before_replacement_hash != replacement_preview.candidate_sha256 && registry.assets[0].sha256 == before_replacement_hash)
	history: Project_Asset_History; defer project_asset_history_destroy(&history)
	project_asset_history_begin(&history, &registry)
	assert(project_asset_commit_replacement(&registry, root, &replacement_preview).ok)
	replacement_hash :=
		registry.assets[0].sha256; assert(replacement_hash == replacement_preview.candidate_sha256 && len(registry.usages) == 1)
	assert(
		project_asset_history_undo(&history, &registry) &&
		registry.assets[0].sha256 == before_replacement_hash &&
		len(registry.usages) == 1,
	)
	assert(
		project_asset_history_redo(&history, &registry) &&
		registry.assets[0].sha256 == replacement_hash &&
		len(registry.usages) == 1,
	)
	replacement_owned_path := project_asset_record_path(
		root,
		registry.assets[0],
	); assert(replacement_owned_path != owned_path && os.is_file(replacement_owned_path) && os.is_file(owned_path))
	project_asset_replacement_preview_destroy(&replacement_preview)
	// A failed compound transaction restores its exact pre-edit registry and does
	// not create a redo entry.
	project_asset_history_begin(
		&history,
		&registry,
	); registry.assets[0].embed_policy = .Prohibited; registry.revision += 1
	assert(
		project_asset_history_cancel(&history, &registry) &&
		registry.assets[0].embed_policy == .Embed,
	)

	// New edits after undo invalidate the redo branch.
	project_asset_history_begin(
		&history,
		&registry,
	); registry.assets[0].kind = .Thumbnail; registry.revision += 1
	assert(
		project_asset_history_undo(&history, &registry),
	); project_asset_history_begin(&history, &registry); registry.assets[0].kind = .Image; registry.revision += 1
	assert(!project_asset_history_redo(&history, &registry))

	allowed := project_asset_plan_stage(
		&registry,
		root,
		"assets",
	); assert(allowed.allowed && allowed.total_bytes > 0 && len(allowed.items) == 1); project_asset_stage_plan_destroy(&allowed)
	registry.assets[0].provenance.redistribution_permitted = false
	blocked := project_asset_plan_stage(
		&registry,
		root,
		"assets",
	); assert(!blocked.allowed && len(blocked.diagnostics) == 1); project_asset_stage_plan_destroy(&blocked)
	registry.assets[0].provenance.redistribution_permitted =
		true; registry.assets[0].embed_policy = .Prohibited
	prohibited := project_asset_plan_stage(
		&registry,
		root,
		"assets",
	); assert(!prohibited.allowed && len(prohibited.diagnostics) == 1); project_asset_stage_plan_destroy(&prohibited)
	registry.assets[0].embed_policy = .Embed; assert(os.remove(replacement_owned_path) == nil)
	missing := project_asset_plan_stage(
		&registry,
		root,
		"assets",
	); assert(!missing.allowed && len(missing.diagnostics) == 1); project_asset_stage_plan_destroy(&missing)

	report_registry: Project_Asset_Registry; defer project_asset_registry_destroy(&report_registry)
	append(
		&report_registry.assets,
		Project_Asset_Record {
			id = "embedded",
			sha256 = "a",
			source_mode = .Link,
			source_path = "a",
			embed_policy = .Embed,
			provenance = {redistribution_permitted = true},
			technical = {byte_size = 10},
		},
		Project_Asset_Record {
			id = "external",
			sha256 = "b",
			source_mode = .Link,
			source_path = "b",
			embed_policy = .External,
			technical = {byte_size = 20},
		},
		Project_Asset_Record {
			id = "prohibited",
			sha256 = "c",
			source_mode = .Link,
			source_path = "c",
			embed_policy = .Prohibited,
			technical = {byte_size = 30},
		},
	)
	report := project_asset_package_size_report(
		&report_registry,
	); assert(report.embedded_bytes == 10 && report.external_bytes == 20 && report.prohibited_bytes == 30 && report.embedded_count == 1 && report.external_count == 1 && report.prohibited_count == 1)

	// Unsupported and non-redistributable inputs fail before registration and
	// leave the registry byte-for-byte equivalent at the document level.
	bad_path := "/private/tmp/chicago-project-asset-acceptance/unsupported.txt"; assert(os.write_entire_file(bad_path, "not an asset") == nil)
	bad_registry: Project_Asset_Registry; defer project_asset_registry_destroy(&bad_registry)
	assert(
		!project_asset_import(&bad_registry, {project_root = root, source_path = bad_path, destination_directory = "assets/imported", requested_id = "bad", kind = .Image, mode = .Copy, embed_policy = .Embed, provenance = provenance}).ok &&
		len(bad_registry.assets) == 0,
	)
	denied := provenance; denied.redistribution_permitted = false
	assert(
		!project_asset_import(&bad_registry, {project_root = root, source_path = source, destination_directory = "assets/imported", requested_id = "denied", kind = .Thumbnail, mode = .Copy, embed_policy = .Embed, provenance = denied}).ok &&
		len(bad_registry.assets) == 0,
	)

	// Focused typed import fixtures cover exact WAV metadata and both accepted
	// and rejected font signatures without relying on host-installed fonts.
	wav_path := fmt.tprintf(
		"%s/tone.wav",
		root,
	); wav := [48]u8{'R', 'I', 'F', 'F', 40, 0, 0, 0, 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ', 16, 0, 0, 0, 1, 0, 1, 0, 0x40, 0x1f, 0, 0, 0x80, 0x3e, 0, 0, 2, 0, 16, 0, 'd', 'a', 't', 'a', 4, 0, 0, 0, 0, 0, 0, 0}; assert(os.write_entire_file(wav_path, wav[:]) == nil); wav_metadata: Project_Asset_Technical_Metadata; assert(project_asset_inspect_file(wav_path, &wav_metadata).ok && wav_metadata.audio.channels == 1 && wav_metadata.audio.sample_rate == 8000 && wav_metadata.audio.duration_seconds == .00025)
	font_path := fmt.tprintf(
		"%s/test.ttf",
		root,
	); font_bytes := [12]u8{0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}; assert(os.write_entire_file(font_path, font_bytes[:]) == nil); font_metadata: Project_Asset_Technical_Metadata; assert(project_asset_inspect_file(font_path, &font_metadata).ok); font_bytes[0] = 'B'; assert(os.write_entire_file(font_path, font_bytes[:]) == nil); assert(!project_asset_inspect_file(font_path, &font_metadata).ok)

	glb: Project_Asset_Technical_Metadata
	assert(
		project_asset_inspect_file("assets/KayKit_Character_Animations_1.1/Animations/gltf/Rig_Medium/Rig_Medium_MovementBasic.glb", &glb).ok,
	)
	assert(
		glb.model.meters_per_unit == 1 &&
		glb.model.up_axis == "+Y" &&
		glb.model.forward_axis == "+Z" &&
		glb.model.mesh_count > 0 &&
		glb.model.material_count > 0,
	)
	animated_glb: Project_Asset_Technical_Metadata
	assert(
		project_asset_inspect_file("assets/KayKit_Character_Animations_1.1/Animations/gltf/Rig_Medium/Rig_Medium_MovementBasic.glb", &animated_glb).ok,
	)
	assert(animated_glb.animation.clip_count > 0 && animated_glb.animation.duration_seconds > 0)
	bounded_glb: Project_Asset_Technical_Metadata
	assert(
		project_asset_inspect_file("assets/kenney_furniture-kit/Models/GLTF format/lampSquareTable.glb", &bounded_glb).ok,
	)
	assert(
		bounded_glb.model.bounds_min.x < bounded_glb.model.bounds_max.x &&
		bounded_glb.model.bounds_min.y < bounded_glb.model.bounds_max.y &&
		bounded_glb.model.bounds_min.z < bounded_glb.model.bounds_max.z,
	)
	preview_registry: Project_Asset_Registry; defer project_asset_registry_destroy(&preview_registry); append(&preview_registry.assets, Project_Asset_Record{id = "preview_image", kind = .Image, source_path = source, sha256 = "preview"}); preview_path, preview_kind, preview_ready := project_asset_preview_source(root, &preview_registry, 0); assert(preview_ready && preview_kind == .Image && preview_path == source)
	wav_44100 :=
		wav; wav_44100[24] = 0x44; wav_44100[25] = 0xac; wav_44100[28] = 0x88; wav_44100[29] = 0x58; wav_44100_path := fmt.tprintf("%s/audition.wav", root); assert(os.write_entire_file(wav_44100_path, wav_44100[:]) == nil); append(&preview_registry.assets, Project_Asset_Record{id = "preview_audio", kind = .Audio, source_path = wav_44100_path, sha256 = "audio"}); preview_frames, preview_channels, preview_rate, audio_ready := project_asset_audio_preview_info(root, &preview_registry, "preview_audio"); assert(audio_ready && preview_frames == 2 && preview_channels == 1 && preview_rate == 44100)
	project_catalog: Editor_Catalog = {
		loaded = true,
	}; append(
		&project_catalog.entries,
		Catalog_Entry {
			id = "project:chair",
			kind = .Object,
			model_asset_ref = "owned_model",
			material_asset_ref = "owned_material",
			texture_asset_ref = "owned_texture",
		},
	); catalog_text := catalog_asset_overrides_serialize(&project_catalog); assert(strings.contains(catalog_text, "model_asset_ref = \"owned_model\"") && catalog_asset_overrides_save(root, &project_catalog).ok); project_catalog.entries[0].model_asset_ref = ""; project_catalog.entries[0].material_asset_ref = ""; project_catalog.entries[0].texture_asset_ref = ""; assert(catalog_asset_overrides_load(root, &project_catalog).ok && project_catalog.entries[0].model_asset_ref == "owned_model" && project_catalog.entries[0].material_asset_ref == "owned_material" && project_catalog.entries[0].texture_asset_ref == "owned_texture"); delete(project_catalog.entries)

	model := Project_Asset_Record {
		id   = "model",
		kind = .Model,
	}; texture := Project_Asset_Record {
		id   = "texture",
		kind = .Texture,
	}; material := Project_Asset_Record {
		id   = "material",
		kind = .Material,
	}; image := Project_Asset_Record {
		id   = "image",
		kind = .Image,
	}; audio := Project_Asset_Record {
		id   = "audio",
		kind = .Audio,
	}; animation := Project_Asset_Record {
		id   = "animation",
		kind = .Animation,
	}; font := Project_Asset_Record {
		id   = "font",
		kind = .Font,
	}; thumbnail := Project_Asset_Record {
		id   = "thumbnail",
		kind = .Thumbnail,
	}
	u0, v0 := project_asset_semantic_usage(
		model,
		.Catalog_Model,
		"chair",
	); u1, v1 := project_asset_semantic_usage(model, .Character_Appearance, "detective"); u2, v2 := project_asset_semantic_usage(model, .Prop_Model, "desk_prop"); u3, v3 := project_asset_semantic_usage(texture, .Material, "wall"); u4, v4 := project_asset_semantic_usage(material, .Material, "floor"); u5, v5 := project_asset_semantic_usage(image, .UI_Image, "card"); u6, v6 := project_asset_semantic_usage(audio, .Sound_Cue, "opening"); u7, v7 := project_asset_semantic_usage(thumbnail, .Campaign_Thumbnail, "campaign"); u8, v8 := project_asset_semantic_usage(animation, .Animation, "walk"); u9, v9 := project_asset_semantic_usage(font, .Font, "case_ui")
	assert(
		v0.ok &&
		u0.field_path == "model_asset_ref" &&
		v1.ok &&
		u1.field_path == "appearance.model_asset_ref" &&
		v2.ok &&
		u2.field_path == "prop.model_asset_ref",
	)
	assert(
		v3.ok &&
		u3.field_path == "material.texture_asset_ref" &&
		v4.ok &&
		u4.field_path == "material_asset_ref" &&
		v5.ok &&
		u5.field_path == "ui.image_asset_ref",
	)
	assert(
		v6.ok &&
		u6.field_path == "sound_cue_asset_ref" &&
		v7.ok &&
		u7.field_path == "thumbnail" &&
		v8.ok &&
		u8.field_path == "animation_asset_ref" &&
		v9.ok &&
		u9.field_path == "ui.font_asset_ref",
	)
	_, mismatch := project_asset_semantic_usage(audio, .Catalog_Model, "bad"); assert(!mismatch.ok)

	// Typed references survive authored document roundtrips and runtime-facing
	// resolution returns the owned file path while legacy empty fields remain a
	// valid fallback signal.
	refs: Project_Asset_Registry; defer project_asset_registry_destroy(&refs); append(&refs.assets, Project_Asset_Record{id = "owned_model", kind = .Model, sha256 = "fixture-model", source_mode = .Link, source_path = "assets/imported/model.glb", project_path = "assets/imported/model.glb", embed_policy = .External, technical = {byte_size = 1}}, Project_Asset_Record{id = "owned_image", kind = .Image, sha256 = "fixture-image", source_mode = .Link, source_path = "assets/imported/card.png", project_path = "assets/imported/card.png", embed_policy = .External, technical = {byte_size = 1}}, Project_Asset_Record{id = "owned_audio", kind = .Audio, sha256 = "fixture-audio", source_mode = .Link, source_path = "assets/imported/cue.ogg", project_path = "assets/imported/cue.ogg", embed_policy = .External, technical = {byte_size = 1}}, Project_Asset_Record{id = "owned_animation", kind = .Animation, sha256 = "fixture-animation", source_mode = .Link, source_path = "assets/imported/walk.glb", project_path = "assets/imported/walk.glb", embed_policy = .External, technical = {byte_size = 1}}, Project_Asset_Record{id = "owned_font", kind = .Font, sha256 = "fixture-font", source_mode = .Link, source_path = "assets/imported/ui.ttf", project_path = "assets/imported/ui.ttf", embed_policy = .External, technical = {byte_size = 1}})
	ref_story: Story_Project; assert(load_story_project("assets/stories/mysteries/the_torn_appointment.story.toml", &ref_story).ok); defer story_project_destroy(&ref_story); assert(len(ref_story.entities) > 0 && len(ref_story.nodes) > 0); ref_story.entities[0].appearance_model_asset_ref = "owned_model"; ref_story.nodes[0].ui_image_asset_ref = "owned_image"; ref_story.nodes[0].sound_cue_asset_ref = "owned_audio"; ref_story.nodes[0].animation_asset_ref = "owned_animation"; ref_story.ui_font_asset_ref = "owned_font"; story_path := fmt.tprintf("%s/typed.story.toml", root); assert(os.write_entire_file(story_path, story_project_serialize(&ref_story)) == nil); story_roundtrip: Story_Project; assert(load_story_project(story_path, &story_roundtrip).ok); model_path, model_ok := story_entity_appearance_path(&story_roundtrip, &refs, story_roundtrip.entities[0].id); image_path, image_ok := story_node_ui_image_path(&story_roundtrip, &refs, story_roundtrip.nodes[0].id); sound_path, sound_ok := story_node_sound_path(&story_roundtrip, &refs, story_roundtrip.nodes[0].id); animation_path, animation_ok := story_node_animation_path(&story_roundtrip, &refs, story_roundtrip.nodes[0].id); ui_font_path, font_ok := story_ui_font_path(&story_roundtrip, &refs); assert(model_ok && model_path == "assets/imported/model.glb" && image_ok && image_path == "assets/imported/card.png" && sound_ok && sound_path == "assets/imported/cue.ogg" && animation_ok && animation_path == "assets/imported/walk.glb" && font_ok && ui_font_path == "assets/imported/ui.ttf"); dialogue_backend := Vulkan_Backend {
		dialogue_asset_count = 1,
	}; dialogue_backend.dialogue_asset_ids[0] =
		story_roundtrip.nodes[0].id; dialogue_backend.dialogue_asset_textures[0] = 17; assert(vulkan_dialogue_asset_texture(&dialogue_backend, story_roundtrip.nodes[0].id) == 17 && vulkan_dialogue_asset_texture(&dialogue_backend, "missing") < 0); story_project_destroy(&story_roundtrip)
	ref_level: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &ref_level).ok); defer authoring_level_document_destroy(&ref_level); assert(len(ref_level.objects) > 0); ref_level.objects[0].model_asset_ref = "owned_model"; ref_level.objects[0].material_asset_ref = "owned_model"; ref_level.objects[0].texture_asset_ref = "owned_image"; level_path := fmt.tprintf("%s/typed.level.toml", root); assert(level_save(level_path, &ref_level).ok); level_roundtrip: Level_Document; assert(level_load(level_path, &level_roundtrip).ok); resolved_level_path, resolved_level_ok := level_object_model_path(&level_roundtrip, &refs, level_roundtrip.objects[0].id); resolved_material_path, resolved_material_ok := level_object_material_path(&level_roundtrip, &refs, level_roundtrip.objects[0].id); resolved_texture_path, resolved_texture_ok := level_object_texture_path(&level_roundtrip, &refs, level_roundtrip.objects[0].id); assert(level_roundtrip.objects[0].material_asset_ref == "owned_model" && level_roundtrip.objects[0].texture_asset_ref == "owned_image" && resolved_level_ok && resolved_level_path == "assets/imported/model.glb" && resolved_material_ok && resolved_material_path == "assets/imported/model.glb" && resolved_texture_ok && resolved_texture_path == "assets/imported/card.png"); authoring_level_document_destroy(&level_roundtrip)
	replacement_ref :=
		refs.assets[project_asset_index(&refs, "owned_model")]; replacement_ref.project_path = "assets/imported/model-v2.glb"; assert(project_asset_registry_replace(&refs, "owned_model", replacement_ref).ok); replaced_story_path, replaced_story_ok := story_entity_appearance_path(&ref_story, &refs, ref_story.entities[0].id); replaced_level_path, replaced_level_ok := level_object_model_path(&ref_level, &refs, ref_level.objects[0].id); assert(replaced_story_ok && replaced_level_ok && replaced_story_path == "assets/imported/model-v2.glb" && replaced_level_path == replaced_story_path)

	// The production Asset workspace transaction spans both the registry usage
	// and the authored Campaign thumbnail field.
	saved_workspace := new(
		Authoring_Workspace_State,
	); saved_workspace^ = authoring_workspace; saved_campaign_workspace := campaign_workspace; saved_campaign_document := campaign_document
	authoring_workspace = {
		selected_asset = 0,
	}; campaign_workspace = {
		draft = {id = "asset_campaign", thumbnail = "old.png"},
	}; campaign_document = {
		id        = "asset_campaign",
		thumbnail = "old.png",
	}
	append(
		&authoring_workspace.assets.assets,
		Project_Asset_Record{id = "cover", kind = .Thumbnail, project_path = "assets/cover.png"},
	)
	message := authoring_asset_map_selected_by_kind(

	); assert(strings.contains(message, "AUTHORED FIELD") && len(authoring_workspace.assets.usages) == 1 && campaign_workspace.draft.thumbnail == "assets/cover.png")
	assert(
		authoring_asset_history_restore(true) &&
		len(authoring_workspace.assets.usages) == 0 &&
		campaign_workspace.draft.thumbnail == "old.png",
	)
	assert(
		authoring_asset_history_restore(false) &&
		len(authoring_workspace.assets.usages) == 1 &&
		campaign_workspace.draft.thumbnail == "assets/cover.png",
	)
	if len(active_story_project.entities) >
	   0 {original_appearance := active_story_project.entities[0].appearance_model_asset_ref; append(&authoring_workspace.assets.assets, Project_Asset_Record{id = "appearance", kind = .Model, project_path = "assets/character.glb"}); authoring_workspace.selected_asset = 1; authoring_workspace.tab = .Story_Data; authoring_workspace.selected_category = int(Story_Authoring_Record_Kind.Entity); authoring_workspace.selected_record = 0; editor_state.selection_count = 0; message = authoring_asset_map_selected_by_kind(); assert(strings.contains(message, "AUTHORED FIELD") && active_story_project.entities[0].appearance_model_asset_ref == "appearance"); assert(authoring_asset_history_restore(true) && active_story_project.entities[0].appearance_model_asset_ref == original_appearance); assert(authoring_asset_history_restore(false) && active_story_project.entities[0].appearance_model_asset_ref == "appearance"); active_story_project.entities[0].appearance_model_asset_ref = original_appearance}
	if graph_document.node_count >
	   0 {saved_graph_node := graph_state.selected_node; mappable_node := -1; for node_index in 0 ..< graph_document.node_count do if graph_document.nodes[node_index].beat.id != "" {mappable_node = node_index; break}; assert(mappable_node >= 0); graph_state.selected_node = mappable_node; old_image, old_sound, old_animation := graph_document.nodes[mappable_node].beat.ui_image_asset_ref, graph_document.nodes[mappable_node].beat.sound_cue_asset_ref, graph_document.nodes[mappable_node].beat.animation_asset_ref; old_font := active_story_project.ui_font_asset_ref; append(&authoring_workspace.assets.assets, Project_Asset_Record{id = "mapped_image", kind = .Image}, Project_Asset_Record{id = "mapped_audio", kind = .Audio}, Project_Asset_Record{id = "mapped_animation", kind = .Animation}, Project_Asset_Record{id = "mapped_font", kind = .Font}); base := len(authoring_workspace.assets.assets) - 4; for offset in 0 ..< 4 {authoring_workspace.selected_asset = base + offset; message = authoring_asset_map_selected_by_kind(); if !strings.contains(message, "AUTHORED FIELD") do fmt.println("ASSET MAPPER FAILURE · ", offset, " · ", message); assert(strings.contains(message, "AUTHORED FIELD"))}; assert(graph_document.nodes[mappable_node].beat.ui_image_asset_ref == "mapped_image" && graph_document.nodes[mappable_node].beat.sound_cue_asset_ref == "mapped_audio" && graph_document.nodes[mappable_node].beat.animation_asset_ref == "mapped_animation" && active_story_project.ui_font_asset_ref == "mapped_font"); graph_document.nodes[mappable_node].beat.ui_image_asset_ref = old_image; graph_document.nodes[mappable_node].beat.sound_cue_asset_ref = old_sound; graph_document.nodes[mappable_node].beat.animation_asset_ref = old_animation; active_story_project.ui_font_asset_ref = old_font; graph_state.selected_node = saved_graph_node}
	if len(level_document.objects) >
	   0 {saved_selection := editor_state.selection[0]; saved_selection_count := editor_state.selection_count; editor_state.selection[0] = {.Object, level_document.objects[0].id, -1}; editor_state.selection_count = 1; object := &level_document.objects[0]; old_model, old_material, old_texture := object.model_asset_ref, object.material_asset_ref, object.texture_asset_ref; append(&authoring_workspace.assets.assets, Project_Asset_Record{id = "mapped_prop", kind = .Model}, Project_Asset_Record{id = "mapped_material", kind = .Material}, Project_Asset_Record{id = "mapped_texture", kind = .Texture}); base := len(authoring_workspace.assets.assets) - 3; for offset in 0 ..< 3 {authoring_workspace.selected_asset = base + offset; message = authoring_asset_map_selected_by_kind(); assert(strings.contains(message, "AUTHORED FIELD"))}; assert(object.model_asset_ref == "mapped_prop" && object.material_asset_ref == "mapped_material" && object.texture_asset_ref == "mapped_texture"); object.model_asset_ref = old_model; object.material_asset_ref = old_material; object.texture_asset_ref = old_texture; editor_state.selection[0] = saved_selection; editor_state.selection_count = saved_selection_count}

	// Reusable catalog content is a durable, namespaced, version-pinned project
	// requirement. It remains distinct from owned asset IDs through save/load
	// and becomes explicit package compatibility metadata rather than a file to
	// embed under the source project's ownership.
	external_registry: Project_Asset_Registry; defer project_asset_registry_destroy(&external_registry)
	external_usage := Project_External_Catalog_Usage {
		reference = {
			namespace = "org.example.furniture",
			catalog_id = "victorian-chair",
			version = "2.1.0",
		},
		document = "level",
		entity_id = "study-chair",
		field_path = "catalog_ref",
	}
	assert(
		project_asset_registry_register_external_catalog_usage(&external_registry, external_usage).ok,
	)
	assert(
		!project_asset_registry_register_external_catalog_usage(&external_registry, {reference = {namespace = "", catalog_id = "chair", version = ""}, document = "level", entity_id = "bad", field_path = "catalog_ref"}).ok,
	)
	external_path := fmt.tprintf(
		"%s/external-registry.toml",
		root,
	); assert(project_asset_registry_save(external_path, &external_registry).ok)
	external_loaded: Project_Asset_Registry; defer project_asset_registry_destroy(&external_loaded); assert(project_asset_registry_load(external_path, &external_loaded).ok && len(external_loaded.external_catalog_usages) == 1)
	loaded_external :=
		external_loaded.external_catalog_usages[0]; assert(loaded_external == external_usage && project_asset_registry_serialize(&external_loaded) == project_asset_registry_serialize(&external_registry))
	external_plan := project_asset_plan_stage(
		&external_loaded,
		root,
		"assets",
	); assert(external_plan.allowed && len(external_plan.items) == 0 && len(external_plan.external_catalog_requirements) == 1 && strings.contains(external_plan.attribution_manifest, "[[external_catalog_requirements]]") && strings.contains(external_plan.attribution_manifest, "org.example.furniture")); project_asset_stage_plan_destroy(&external_plan)
	project_asset_history_destroy(
		&authoring_workspace.asset_history,
	); project_asset_registry_destroy(&authoring_workspace.assets); delete(authoring_workspace.asset_campaign_undo); delete(authoring_workspace.asset_campaign_redo); delete(authoring_asset_authored_undo); delete(authoring_asset_authored_redo); authoring_asset_authored_undo = nil; authoring_asset_authored_redo = nil; campaign_destroy(&campaign_workspace.draft); campaign_workspace = {}; authoring_workspace = saved_workspace^; free(saved_workspace); campaign_workspace = saved_campaign_workspace; campaign_document = saved_campaign_document
}
