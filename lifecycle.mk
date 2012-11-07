
#
# Concepts:
#
# Build Stage     - a single step that generates some output from some output
#                   in a predetermined way.
# Stage Chain     - a series of stages that are implicitly connected together 
#                   via shared outputs and inputs.
# Build Pipeline  - a concrete input and output that are connected together by
#                   some chain of implicit rules (stage chain).
# Build Phase     - a set of pipeline instances that are logically associated.
#
# Build Lifecycle - a set of phases and implicit pipelines that define the
#                   complete build
#
#
# Notes:
#     Use of this library requires the MSDIR variable to be set, and for the 
#     location to be writable.
#

$(info lifecycle.mk loaded)

include util.mk

define rule_t
$(1): $(2)
	$(call format_cmd,$(4),$(3),$(5))
endef

#
# formats a multiline command for use in a make recipe. This ensures
# that each line is properly tabbed, and any required pre and 
# post-processing steps are performed. Pre and Post can consist of
# anything that can be legally prepended and appended to each line
# of the command.
#
# $1 - pre-processing step.
# $2 - command, consisting of one or more lines.
# $3 - post-processing step.
#
define format_cmd
$(1)$(subst $(\n),$(3)$(\n)$(\t)$(1),$(subst $(\t),,$(2)))$(3)
endef

#
# defines a build stage for milestone based builds, via a pattern rule.
# also defines a vpath for each of the predecessor stages.
#
# TODO: should the vpath be defined using patsubst or foreach?
#
# $(MSDIR) - the directory to place milestones in.
#
# $1 - the milestone/build stage
# $2 - the predecessor/dependency stages of $1
# $3 - the name of a variable containing a command to
#      be performed for the build stage.
# $4 - the directory to execute the command referenced by $3 in.
# $5 - the directory to place the logs in.
#
define build_stage_t
$(if $(MSDIR),,$(error MSDIR was not defined. no place to put milestones))
$(MSDIR)/$(1): $(2) | $(MSDIR) $(4) $(5)
	$(call format_cmd,@echo $(3): ,$(value $(3)),)
	@truncate -s 0 -c $(5)/$(1).out
	$(call format_cmd,@$(if $(4),cd $(4) && ,),$(value $(3)),$(if $(5), >> $(5)/$(1).out,))
	@touch $$@
endef

define milestone_vpath_t
vpath $1: $(MSDIR)
endef

#
# Defines a build pipeline. This is a dependency only rule that specifies the
# relationship between one concrete product and another.
#
# $1 - the name of the build scope.
# $2 - the name of the dependent stage.
# $3 - a list of the names of the pipeline dependencies.
#
define build_scoped_pipeline_t
$(call build_pipeline_t,$1.$2,$(patsubst %,$1.%,$3))
endef

#
# Defines a build pipeline. This is a dependency only rule that specifies the
# relationship between one concrete product and another.
#
# $1 - the name of the dependent stage.
# $2 - a list of the names of the pipeline dependencies.
#
define build_pipeline_t
$(if $(MSDIR),,$(error MSDIR was not defined, no place to put milestones))
$(MSDIR)/$1: $2
endef

#
# ensures that we don't end up with a pipeline connection with either the left
# or right of the ':' empty.
#
define build_pipeline_check
$(if $(and $1,$2),$(call build_pipeline_t,$1,$2),)
endef


define build_product_t
$1: $2
endef

#
# Defines a set of pipelines, and logically groups them as a single phase.
# Any dependency of the phase will then trigger a rebuild 
#
# $1 - the name of the phase.
# $2 - a list of the names of all of the pipeline members and phase dependencies.
#
define build_phase_t
$(call build_pipeline_t,$1,$2)
	@echo $(call uppercase,$1) phase complete.
	@touch $$@
endef

#
# Wraper for build_stage_t with 4 arguments. Translates the build stage name
# to upper case for use as the build command.
#
# $1 - the name of the build lifecycle stage.
# $2 - the name of the predecessor stage.
# $3 - the name of a variable containing the directory the build command should be executed from.
# $4 - the directory where logs should be placed.
#
define build_stage_t4
$(call build_stage_t,%.$1,$(call build_stage_p,$1,$2),$(call uppercase,$1),$($3),$4)
endef

#
# A helper to build the prerequisite lists for generated pattern rules for 
# build lifecycle stages.
#
# $1 - the name of the build stage.
# $2 - the name of the predecessor stage, if any.
# $3 - a prefix to be used for $2. The resulting symbol will be $3$2
#
define build_prerequisites
$($(call uppercase,$1)_P) $(if $2,$3$2,)
endef

define build_stage_p
$(call build_prerequisites,$1,$2,%.)
endef

define build_phase_p
$(call build_prerequisites,$1,$2,$3.)
endef

#
# Level 1
#
# Injects a set of build stages into the calling context, and constructs an
# appropriate vpath directive for each milestone type.
#
# $1 - the function to invoke on the generated output.
# $2 - the list of build stages to create and inject, where each element
#      looks like:
#
#      <stage>:<predecessor>[:option]
#      each stage and predecessor will be used to generate pattern rules.
#
# $3 - the name of the directory to store the logs in.
#
define inject_stages
$(call inject_stage_vpaths,$1,$2)$(call inject_stage_rules,$1,$2,$3)
endef

define inject_stage_vpaths
$(foreach stage,$2,$(call $1,$(call milestone_vpath_t,%.$(call field,1,$(stage)))))
endef

define inject_stage_rules
$(foreach stage,$2,$(call $1,$(call call4,build_stage_t4,$(call list_pad,3,null,$(call unpack,$(stage))) $3)))
endef

#
# Level 1
#
# Injects a set of build pipelines into the calling context.
#
# $1 - the function to invoke on the generated content.
# $2 - the list of pipelines to build, where each element looks like:
#
#      <concrete_stage>:<concrete_predecessor1>[:<concrete_predecessor2>[:...]]
#      each of the predecessors is another concrete stage, and a concrete
#      stage is the fully scoped name with no pattern characters.
#
define inject_pipelines
$(foreach pipeline,$2,$(call $1,$(call call2,build_pipeline_t,$(call list_pad,2,null,$(call unpack,$(pipeline))))))
endef

#
# Level 1
#
# Injects a set of pipeline product rules into the calling context.
#
# $1 - the function to invoke on the generated content.
# $2 - the list of concrete product mappings, where each element looks like:
#
#      <product>:<stage>[:<stage1>[:...]]
#
define inject_products
$(foreach pipeline,$2,$(call $1,$(call call2,build_product_t,$(call list_pad,2,null,$(call unpack,$(pipeline))))))
endef

#
# Level 1
#
# Injects a set of build phases into the calling context.
#
# $1 - the function to invoke on the generated content. i.e. 'eval', 
#      'print', 'trace',...
# $2 - the list of phases to build, where each element looks like:
#
#      <phase>:<predecessor1>[:<prececessor2>[:...]]
#      where prececessor is either another phase, or a pipeline
#
define inject_phases
$(call build_phase_links,$1,$2)$(call inject_phase_rules,$1,$2)
endef

#
# $1 - the function to invoke on the generated content.
# $2 - the list of phases to construct rules for.
#
define inject_phase_rules
$(foreach phase,$2,$(call $1,$(call call2,build_phase_t,$(call list_pad,2,null,$(call unpack,$(phase))))))
endef

#
# In order to properly link phases, it is also necessary to make all of the
# non-phase predecessors dependent upon the prececessor phases.
#

#
# Sets up the dependency between a pipeline and all predecessor phases of
# the containing phase.
#
# $1 - the function to invoke on the generated content.
# $2 - the list of defined phases.
# $3 - the list of components of a phase.
#
define build_phase_link
$(foreach pipeline,$(filter-out $2,$3),$(call $1,$(call build_pipeline_check,$(pipeline),$(filter $2,$3))))
endef

#
# Ensures that all pipeline components of a phase are also dependent upon
# the predecessor phases of the containing phase, for all phases.
#
# $1 - the function to invoke on the generated content.
# $2 - the list of phases to construct linkages for.
#
define build_phase_links
$(foreach phase,$2,$(call build_phase_link,$1,$(call map_keys,$2),$(call tail,$(call unpack,$(phase)))))
endef

#
# Example usage:
#
# $(call inject_stages,dep.extract:dep.fetch src.extract:src.fetch configure:src.extract:BUILDDIR build:configure:BUILDDIR install:build:BUILDDIR package:install publish:package,$(LOGDIR))
#
# $(call inject_pipelines,$(call with_scope,$(LIBNAME),publish:src.fetch build.tgz:package) $(call with_scope,%,dep.tgz:dep.fetch dep.files:prepare src.tgz:src.fetch))
#
# $(call inject_phases,$(LIBNAME).prepare:$(call pack,$(patsubst %,%.dep.extract,$(DEPENDENCIES))):$(LIBNAME).dep.files)
#

# TODO: is there really no better way to do this? could we build these functions with eval? use recursion somehow?
# Note: the list should be padded with nulls if it is not the indicated size
#       to ensure that the real parameters are placed in the appropriate slots.
#
# workaround for the inability to dynamically build parameter lists.
call2 = $(call $1,$(call param,1,$2),$(call param,2,$2))
call3 = $(call $1,$(call param,1,$2),$(call param,2,$2),$(call param,3,$2))
call4 = $(call $1,$(call param,1,$2),$(call param,2,$2),$(call param,3,$2),$(call param,4,$2))

# experimental recursive approach.
#
# TODO: this still requires too much code.
#
#call = $(call call1_,$1,$2,$3)
#call1_ = $(if $(subst 1,,$1),$(call $2,$3),$(call call2_,$1,$2,$(call param,1,$3),$(call tail,$3)))
#call2_ = $(if $(subst 2,,$1),$(call $2,$3,$4),$(call call3_,$1,$2,$3,$(call param,1,$4),$(call tail,$4)))
#call3_ = $(if $(subst 3,,$1),$(call $2,$3,$4,$5),$(call call4_,$1,$2,$3,$4,$(call param,1,$5),$(call tail,$5)))
#call4_ = $(if $(subst 4,,$1),$(call $2,$3,$4,$5,$6),$(call call5_,$1,$2,$3,$4,$5,$(call param,1,$6),$(call tail,$6)))
#call5_ = $(if $(subst 5,,$1),$(call $2,$3,$4,$5,$6,$7),$(call call6_,$1,$2,$3,$4,$5,$6,$(call param,1,$7),$(call tail,$7)))

#call2 = $(call call,2,$1,$2)
#call3 = $(call call,3,$1,$2)
#call4 = $(call call,4,$1,$2)

# performs null mappings in list-mapped function calls.
param = $(patsubst null,,$(strip $(word $1,$2)))

eval = $(eval $1)
print = $(info $1)
trace = $(info $1)$(eval $1)

