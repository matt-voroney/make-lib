
ifndef LIBNAME
$(error LIBNAME not defined!: Must be set to the name of the library to be built)
endif
ifndef LIB_VERSION
$(error LIB_VERSION not defined!: Must be set to the version of '$(LIBNAME)' that is to be built)
endif
ifndef LIB_URL
$(error LIB_URL not defined!: Must be set to the URL where a source archive of '$(LIBNAME)' version '$(LIB_VERSION)' can be downloaded)
endif

S3_BUCKET ?= heroku-binaries
PUBLISHURL := https://s3.amazonaws.com/$(S3_BUCKET)
PATH := $(PATH):$(DEPDIR)/bin:$(DEPDIR)/sbin
DEPDIR ?= /tmp/vendor
INSTALLDIR ?= /tmp/vendor
LOGDIR ?= /tmp/log
BUILDDIR ?= $(LIBNAME)-src
DIRECTORIES := $(DIRECTORIES) $(DEPDIR) $(LOGDIR) $(BUILDDIR)
LIB_SRC_SUFFIX ?= $(filter-out $(LIB_URL),$(foreach sfx,.tar.gz .tgz .bz2 .xz,$(patsubst %$(sfx),$(sfx),$(LIB_URL))))

# map of lifecycle stage to predecessor and command variable. 
# i.e. <stage>:<predecessor>:<command>
LIFECYCLE := config:depend:CONFIGURE build:config:BUILD install:build:INSTALL
# map of compression formats to tar decompression switch. 
# i.e. <format>:<switch>
COMPRESSION := tgz:z tar.gz:z bz2:j xz:J 

# don't publish if we are only doing a local build.
phony_targets := depend config build install package $(if $(LOCALBUILD),,publish)
# build milestone suffixes.
ms_suffixes := $(patsubst %,.%,$(phony_targets)) -src.extract -build.extract

export CPATH := $(CPATH):$(DEPDIR)/include
export LIBRARY_PATH := $(LIBRARY_PATH):$(DEPDIR)/lib
export LD_RUN_PATH := $(LD_RUN_PATH):$(DEPDIR)/lib
export LD_LIBRARY_PATH := $(LD_LIBRARY_PATH):$(DEPDIR)/lib

# override in $(LIBNAME).mk env, or make invocation if not suitable
CONFIGURE ?= ./configure --prefix=$(INSTALLDIR)
BUILD ?= $(MAKE) 
INSTALL ?= $(MAKE) install

define \n


endef
define \t
	
endef
space :=
space +=
expand = $(subst :,$(space),$1)

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

define extract_src_t
%-src.extract: %-src.$(1) | $(BUILDDIR)
	tar -x$(2)f $$< -C $(BUILDDIR) --transform 's@^\(./\)\{0,1\}[^/]*$(*)[^/]*/@@'
	@touch $$@
endef

define rule_t
$(1): $(2)
	$(call format_cmd,$(4),$(3),$(5))
endef

#
# defines a build stage for milestone based builds.
#
# $1 - the milestone/build stage
# $2 - the predecessor/dependency of $1
# $3 - the name of a variable containing a command to
#      be performed for the build stage.
# $4 - a boolean toggle. If set, each line in $3 will be
#      run from BUILDDIR
#
define build_stage_t
%.$(1): %.$(2) %-src.extract | $(BUILDDIR)
	$(call format_cmd,@echo $(3): ,$($(3)),)
	@truncate -s 0 $(LOGDIR)/$(1).out
	$(call format_cmd,@$(if $(4),cd $(BUILDDIR) && ,),$($(3)), >> $(LOGDIR)/$(1).out)
	@touch $$@
endef

# TODO: is there really no better way to do this?
# workaround for the inability to dynamically build parameter lists.
call2 = $(call $1,$(word 1,$2),$(word 2,$2))
call3 = $(call $1,$(word 1,$2),$(word 2,$2),$(word 3,$2))
call4 = $(call $1,$(word 1,$2),$(word 2,$2),$(word 3,$2),$(word 4,$2))

$(info "Build type: $(if $(LOCALBUILD),local,remote)")
$(info "Library being built: $(LIBNAME)")
$(info "With the following dependencies: $(DEPENDENCIES)")
$(info "Source archive suffix: $(LIB_SRC_SUFFIX)")
$(info "Variables Exported to submake invocations:")
$(info "    CPATH=$(CPATH)")
$(info "    LIBRARY_PATH=$(LIBRARY_PATH)")
$(info "    LD_RUN_PATH=$(LD_RUN_PATH)")
$(info "    LD_LIBRARY_PATH=$(LD_LIBRARY_PATH)") 

.PRECIOUS: $(patsubst %,\%%,$(ms_suffixes))
.PHONY: $(phony_targets)
.DEFAULT_GOAL = all

all: $(phony_targets)
$(phony_targets): $(LOGDIR) 
depend: $(DEPDIR)
$(LIBNAME).package: $(LIBNAME)-build.tgz

# add timestamp dependencies for each top level phony target
#
$(foreach phony,$(phony_targets),$(eval $(phony): $(LIBNAME).$(phony)))

# use depend as a file of exclusions for packaging.
#
$(LIBNAME).depend: $(patsubst %,%-build.extract,$(DEPENDENCIES))
	find $(DEPDIR) > $@

$(foreach d,$(DIRECTORIES),$(eval $(call rule_t,$(d),,mkdir $$@)))
$(foreach dep,$(DEPENDENCIES),$(eval $(dep)-build.extract: $(dep)-build.tgz))
$(foreach dep,$(DEPENDENCIES),$(eval $(call rule_t,$(dep)-build.tgz,,s3 get $(S3_BUCKET)/$$@ filename=$$@)))

%-build.extract: %-build.tgz
	tar -xzf $< -C $(DEPDIR)
	@touch $@

# if only the makefile was included, then the sources need to be downloaded.
#
$(LIBNAME)-src$(LIB_SRC_SUFFIX):
	curl -L -o $@ $(LIB_URL)

# extract one of the various src archive formats we might have downloaded.
# should just extract the sources into the BUILDDIR.
#
$(foreach fmt,$(COMPRESSION),$(eval $(call call2,extract_src_t,$(call expand,$(fmt)))))

%.package: %-build.tgz ;
%-build.tgz : %.depend %.install
	tar -czf $@ $(INSTALLDIR) -X $< -P --transform 's@$(INSTALLDIR)/@@' > $(LOGDIR)/package.out
	@touch $*.package

%.publish: %-build.tgz 
	s3 put $(S3_BUCKET)/$< filename=$< > $(LOGDIR)/publish.out
	@touch $@

# assemble build LIFECYCLE
#
$(foreach stage,$(LIFECYCLE),$(eval $(call call4,build_stage_t,$(call expand,$(stage)) cd)))

