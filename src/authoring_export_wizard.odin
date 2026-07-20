package main

import "core:fmt"

Authoring_Export_Wizard_Stage :: enum {Summary, Dependencies, Validation, Destination, Exporting, Result}
Authoring_Export_Wizard :: struct {
	stage:Authoring_Export_Wizard_Stage,
	title,version,thumbnail,destination,message:string,
	dependency_count:int,
	validation_revision:u64,
	validation_domain_count:int,
	dependencies_reviewed,validation_passed:bool,
	request:Authoring_Service_Export,
	artifact:Authoring_Portable_Package,
}

authoring_export_wizard_begin :: proc(title,version,thumbnail:string,dependency_count:int,request:Authoring_Service_Export)->Authoring_Export_Wizard {return {stage=.Summary,title=title,version=version,thumbnail=thumbnail,dependency_count=dependency_count,request=request,message="REVIEW ARTIFACT SUMMARY"}}

authoring_export_wizard_advance :: proc(wizard:^Authoring_Export_Wizard,validation:^Authoring_Validation_Snapshot=nil,destination:string="",service_result:^Authoring_Service_Result=nil)->Validation {
	if wizard==nil do return {false,"export wizard is missing"}
	switch wizard.stage {
	case .Summary:if wizard.title==""||wizard.version=="" do return {false,"title and content version are required"};wizard.stage=.Dependencies;wizard.message="REVIEW DEPENDENCIES"
	case .Dependencies:wizard.dependencies_reviewed=true;wizard.stage=.Validation;wizard.message="RUN EXPORTABLE VALIDATION"
	case .Validation:if validation==nil||validation.profile!=.Exportable||validation.domain_count==0||authoring_validation_is_blocked(validation) do return {false,"fresh production exportable validation is blocking or unavailable"};wizard.validation_revision=validation.revision;wizard.validation_domain_count=validation.domain_count;wizard.validation_passed=true;wizard.stage=.Destination;wizard.message=fmt.tprintf("VALIDATED SNAPSHOT r%d · %d DOMAINS · CHOOSE DESTINATION",validation.revision,validation.domain_count)
	case .Destination:if destination=="" do return {false,"export destination is required"};wizard.destination=destination;wizard.request.output_path=destination;wizard.stage=.Exporting;wizard.message="EXPORT IN PROGRESS"
	case .Exporting:if service_result==nil||!service_result.ok do return {false,"verified export result is required"};wizard.artifact=service_result.artifact;wizard.stage=.Result;wizard.message="EXPORT COMPLETE · REVIEW ARTIFACT IDENTITY"
	case .Result:return {true,"EXPORT WIZARD COMPLETE"}
	}
	return {true,wizard.message}
}

authoring_export_wizard_ready :: proc(wizard:^Authoring_Export_Wizard)->bool {return wizard!=nil&&wizard.stage==.Result&&wizard.dependencies_reviewed&&wizard.validation_passed&&wizard.validation_domain_count>0&&wizard.destination!=""&&wizard.artifact.identity.id!=""}
