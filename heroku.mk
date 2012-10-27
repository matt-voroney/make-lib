
ifndef LIBNAME
$(error LIBNAME not defined!: Must be set to the name of the library to be built)
endif
ifndef LIB_VERSION
$(error LIB_VERSION not defined!: Must be set to the version of '$(LIBNAME)' that is to be built)
endif
ifndef LIB_URL
$(error LIB_URL not defined!: Must be set to the URL where a source archive of '$(LIBNAME)' version '$(LIB_VERSION)' can be downloaded)
endif

S3_BUCKET := heroku-binaries
PUBLISHURL := https://s3.amazonaws.com/$(S3_BUCKET)
DEPDIR := /tmp/vendor
PATH := $(PATH):$(DEPDIR)/bin:$(DEPDIR)/sbin
INSTALLDIR := /tmp/vendor
LOGDIR := /tmp/log
BUILDDIR := $(LIBNAME)-src
LIB_SRC_SUFFIX ?= $(filter-out $(LIB_URL),$(foreach sfx,.tar.gz .tgz .bz2 .xz,$(patsubst %$(sfx),$(sfx),$(LIB_URL))))

# don't publish if we are only doing a local build.
#
phony_targets := depend config build install $(if $(LOCALBUILD),,publish)

export CPATH := $(CPATH):$(DEPDIR)/include
export LIBRARY_PATH := $(LIBRARY_PATH):$(DEPDIR)/lib
export LD_RUN_PATH := $(LD_RUN_PATH):$(DEPDIR)/lib
export LD_LIBRARY_PATH := $(LD_LIBRARY_PATH):$(DEPDIR)/lib

# override in $(LIBNAME).mk env, or make invocation if not suitable
CONFIGURE ?= ./configure --prefix=$(INSTALLDIR)
BUILD ?= $(MAKE) 
INSTALL ?= $(MAKE) install

define extract_src
	tar -x$(1)f $< -C $(2) --transform 's@^\(./\)\{0,1\}[^/]*$(LIBNAME)[^/]*/@@'
	@touch $@
endef

$(info "Build type: $(if $(LOCALBUILD),local,remote)")
$(info "Library being built: $(LIBNAME)")
$(info "With the following dependencies: $(DEPENDENCIES)")
$(info "Source archive suffix: $(LIB_SRC_SUFFIX)")
$(info "Variables Exported to submake invocations:")
$(info "    CPATH=$(CPATH)")
$(info "    LIBRARY_PATH=$(LIBRARY_PATH)")
$(info "    LD_RUN_PATH=$(LD_RUN_PATH)")
$(info "    LD_LIBRARY_PATH=$(LD_LIBRARY_PATH)") 

.PHONY: $(phony_targets) $(DEPENDENCIES)
.DEFAULT_GOAL = all

all: $(phony_targets) $(LIBNAME)-build.tgz
$(phony_targets): $(LOGDIR) 
depend: $(DEPDIR)

# add timestamp dependencies for each top level phony target
#
$(foreach phony,$(phony_targets),$(eval $(phony): $(LIBNAME).$(phony)))

# use depend as a file of exclusions for packaging.
#
$(LIBNAME).depend: $(DEPENDENCIES)
	find $(DEPDIR) > $@

$(DEPDIR):
	mkdir $@

$(LOGDIR):
	mkdir $@

$(BUILDDIR):
	mkdir $@

$(DEPENDENCIES): | $(DEPDIR)
	s3 get $(S3_BUCKET)/$@-build.tgz filename=$@.tgz
	tar -xzf $@.tgz -C $(DEPDIR)
	rm -f $@.tgz 

# if only the makefile was included, then the sources need to be downloaded.
#
$(LIBNAME)-src$(LIB_SRC_SUFFIX):
	curl -L -o $@ $(LIB_URL)

# extract one of the various src archive formats we might have downloaded.
# should just extract the sources into the current directory.
#
%-src.extract: %-src.tgz %-src
	$(call extract_src,z,$(word 2,$^))

%-src.extract: %-src.tar.gz %-src
	$(call extract_src,z,$(word 2,$^))

%-src.extract: %-src.bz2 %-src
	$(call extract_src,j,$(word 2,$^))

%-src.extract: %-src.xz %-src
	$(call extract_src,J$(word 2,$^))

# package all files that are not already part of the dependency packages. 
#
%-build.tgz : %.depend %.install
	tar -czf $@ $(INSTALLDIR) -X $< -P --transform 's@$(INSTALLDIR)/@@' > $(LOGDIR)/package.out

%.publish: %-build.tgz 
	s3 put $(S3_BUCKET)/$< filename=$< > $(LOGDIR)/publish.out
	@touch $@

# commands can be overridden by supplying new values for the respective
# variables: CONFIGURE, BUILD, and INSTALL.
%.config: $(BUILDDIR) %.depend %-src.extract
	@echo CONFIGURE: $(CONFIGURE) 
	@cd $< && $(CONFIGURE) > $(LOGDIR)/configure.out
	@touch $@

%.build: $(BUILDDIR) %.config %-src.extract
	@echo BUILD: $(BUILD)
	@cd $< && $(BUILD) > $(LOGDIR)/build.out
	@touch $@

%.install: $(BUILDDIR) %.build %-src.extract
	@echo INSTALL: $(INSTALL)
	@cd $< && $(INSTALL) > $(LOGDIR)/install.out
	@touch $@
