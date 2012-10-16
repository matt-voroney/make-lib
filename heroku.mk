
include $(HOME)/.build-env

ifndef LIBNAME
$(error "LIBNAME not defined!: Must be set to the name of the library to be built")
endif

#assumes this makefile is packaged in the 
S3_BUCKET := heroku-binaries
PUBLISHURL := https://s3.amazonaws.com/$(S3_BUCKET)
DEPDIR := /tmp/dep
PATH := $(PATH):$(DEPDIR)/bin:$(DEPDIR)/sbin
INSTALLDIR := /tmp/vendor
LOGDIR := /tmp/log
S3_BIN := $(DEPDIR)/bin/s3
LIB_SRC_SUFFIX := $(filter-out $(LIB_URL),$(foreach sfx,.tar.gz .tgz .bz2 .xz,$(patsubst %$(sfx),$(sfx),$(LIB_URL))))

export CPATH := $(CPATH):$(DEPDIR)/include
export LIBRARY_PATH := $(LIBRARY_PATH):$(DEPDIR)/lib
export LD_LIBRARY_PATH := $(LD_LIBRARY_PATH):$(DEPDIR)/lib

# override in $(LIBNAME).mk env, or make invocation if not suitable
CONFIGURE ?= ./configure --prefix=$(INSTALLDIR)
BUILD ?= $(MAKE) 
INSTALL ?= $(MAKE) install

$(info "Library being built: $(LIBNAME)")
$(info "With the following dependencies: $(DEPENDENCIES)")
$(info "Source archive suffix: $(LIB_SRC_SUFFIX)")
$(info "Variables Exported to submake invocations:")
$(info "    CPATH=$(CPATH)")
$(info "    LIBRARY_PATH=$(LIBRARY_PATH)")
$(info "    LD_LIBRARY_PATH=$(LD_LIBRARY_PATH)") 

.PHONY: all depend config install publish $(DEPENDENCIES)
.DEFAULT_GOAL = all

all: depend config install publish

depend config build install publish: $(LOGDIR) 
depend libs3: $(DEPDIR)

depend: $(DEPENDENCIES) 

libs3: $(DEPDIR)
	curl -o $@.tgz $(PUBLISHURL)/$@-build.tgz
	tar -xzf $@.tgz -C $(DEPDIR)
	rm -f $@.tgz
	touch $@ 

$(DEPDIR):
	-mkdir $@

$(LOGDIR):
	-mkdir $@

$(DEPENDENCIES): libs3 | $(DEPDIR)
	s3 get $(S3_BUCKET)/$@-build.tgz filename=$@.tgz
	tar -xzf $@.tgz -C $(DEPDIR)
	rm -f $@.tgz 

# if only the makefile was included, then the sources need to be downloaded.
$(LIBNAME)-src$(LIB_SRC_SUFFIX):
	curl -L -o $@ $(LIB_URL)

# extract one of the various src archive formats we might have downloaded.
# should just extract the sources into the current directory.
#
%-src: %-src.tgz
	tar -xzf $< -C . --transform 's@^$(LIBNAME)[^/]*/@@'
	echo . > $@

%-src: %-src.tar.gz
	tar -xzf $< -C . --transform 's@^$(LIBNAME)[^/]*/@@'
	echo . > $@

%-src: %-src.bz2
	tar -xjf $< -C . --transform 's@^$(LIBNAME)[^/]*/@@'
	echo . > $@

%-src: %-src.xz
	tar -xJf $< -C . --transform 's@^$(LIBNAME)[^/]*/@@'
	echo . > $@

$(LIBNAME)-build.tgz : install
	tar -czf $@ $(INSTALLDIR) -P --transform 's@$(INSTALLDIR)/@@' > $(LOGDIR)/package.out

publish: $(LIBNAME)-build.tgz libs3 
	s3 put $(S3_BUCKET)/$< filename=$< > $(LOGDIR)/publish.out

# commands can be overridden by supplying new values for the respective
# variables.
config: depend $(LIBNAME)-src
	$(CONFIGURE) > $(LOGDIR)/configure.out

build: config $(LIBNAME)-src
	$(BUILD) > $(LOGDIR)/build.out

install: build $(LIBNAME)-src
	$(INSTALL) > $(LOGDIR)/install.out
