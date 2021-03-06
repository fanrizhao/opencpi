# This file is protected by Copyright. Please refer to the COPYRIGHT file
# distributed with this source distribution.
#
# This file is part of OpenCPI <http://www.opencpi.org>
#
# OpenCPI is free software: you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version.
#
# OpenCPI is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
# details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

ifndef __UTIL_MK__
__UTIL_MK__=x
# The /bin/sh shell in Debian/Ubuntu is explicitly strict/stupid
override SHELL=/bin/bash
export AT
export OCPI_DEBUG_MAKE
AT=@

# RPM-based options:
-include $(OCPI_CDK_DIR)/include/autoconfig_import-$(OCPI_TARGET_PLATFORM).mk
ifneq (1,$(OCPI_AUTOCONFIG_IMPORTED))
-include $(OCPI_CDK_DIR)/include/autoconfig_import.mk
endif

# THIS IS THE make VERSION OF WHAT IS IN ocpibootstrap.sh
ifndef OCPI_PREREQUISITES_DIR
  ifneq ($(and $(OCPI_CDK_DIR),$(wildcard $(OCPI_CDK_DIR)/../prerequisites)),)
    export OCPI_PREREQUISITES_DIR:=$(abspath $(OCPI_CDK_DIR)/../prerequisites)
  else
    export OCPI_PREREQUISITES_DIR:=/opt/opencpi/prerequisites
  endif
endif
#FIXME  this registration should be somewhere else nicer
ifndef OCPI_PREREQUISITES_LIBS
  # Libraries used with ACI and our executables
  export OCPI_PREREQUISITES_LIBS:=lzma gmp
endif
ifndef OCPI_PREREQUISITES
  # All prerequisites we need to build and use
  export OCPI_PREREQUISITES:=$(OCPI_PREREQUISITES_LIBS) gtest patchelf ad9361
endif
OCPI_DEBUG_MAKE=
ifneq (,)
define OcpiDoInclude
ifndef OcpiThisFile
OcpiThisFile:=$(lastword $(MAKEFILE_LIST))
endif
OcpiSaveFile:=$(OcpiThisFile)
include $(OCPI_CDK_DIR)/include/$(1)
OcpiThisFile:=$(OcpiSaveFile)
endef
OcpiInclude=$(eval $(call OcpiDoInclude,$1))
endif

ifneq ($(OCPI_DEBUG_MAKE),)
define OcpiDbg
$(warning Debug: $(1))
endef
define OcpiDbgVar
$(call OcpiDbg,$(2)$(1) is <$(call $(1))> origin $(origin $(1)))
endef
endif

# Options we alway use and will assume everywhere (except when building framework; AV-3464)
.DELETE_ON_ERROR:
ifndef OCPI_AUTOCONFIG_IMPORTED
.SUFFIXES:
endif
.SECONDEXPANSION:

# Utilities used by many other makefile files
# Allow us to include this early by establishing the default initial target (all).
all:
.PHONY: all
Cwd:=$(realpath .)
$(call OcpiDbgVar,Cwd)
Empty:=
Space:=$(Empty) $(Empty)
# This variable is set to the character that is invalid in pathnames.
# It should be the one printable character that we will not support in pathnames.
Invalid:="
# end hanging quote above for some editors --> "
CwdDirName:=$(subst $(Invalid),$(Space),$(notdir $(subst $(Space),$(Invalid),$(Cwd))))
CwdName:=$(basename $(CwdDirName))
$(call OcpiDbgVar,CwdName)

# These need to be early since some immediate assignments use them below
#Capitalize=$(shell csh -f -c 'echo $${1:u}' $(1))
#UnCapitalize=$(shell csh -f -c 'echo $${1:l}' $(1))
Capitalize=$(shell awk -v x=$(1) 'BEGIN {print toupper(substr(x,1,1)) substr(x,2,length(x)-1) }')
UnCapitalize=$(shell awk -v x=$(1) 'BEGIN {print tolower(substr(x,1,1)) tolower(x,2,length(x)-1) }')
ToUpper=$(shell echo $(1)|tr a-z A-Z)
ToLower=$(shell echo $(1)|tr A-Z a-z)

ifndef Model
Model:=$(strip $(subst ., ,$(suffix $(CwdDirName))))
endif
$(call OcpiDbgVar,Model)
Models:=xm rcc hdl ocl assy
Language_rcc:=c
Languages_rcc:=c c++
Suffix_rcc_c:=c
Suffix_rcc_c++:=cc

Suffix_hdl_verilog:=v
Suffix_hdl_vhdl:=vhd
Language_hdl:=vhdl
Languages_hdl:=vhdl verilog

Language_ocl:=cl
Suffix_ocl_cl:=cl
Suffix_xm:=xm
# Assign here for caching
CapModels:=$(foreach m,$(Models),$(call Capitalize,$m))
UCModel=$(call ToUpper,$(Model))
CapModel=$(call Capitalize,$(Model))
HostSystem:=$(shell uname -s | tr A-Z a-z)
AT=@
RM=rm
ifneq ($(HostSystem),darwin)
TIME=/usr/bin/time -f %E
OcpiLibraryPathEnv=LD_LIBRARY_PATH
else
TIME=/usr/bin/time
OcpiLibraryPathEnv=DYLD_LIBRARY_PATH
endif
# this is to ensure support for the -n flag
ECHO=/bin/echo
#default assumes all generated files go before all authored files
CompiledSourceFiles=$(TargetSourceFiles_$(ParamConfig)) $(GeneratedSourceFiles) $(AuthoredSourceFiles)
# Just for history (thanks Andrew): this only works with tcsh, not traditional csh.  And csh isn't posix anywah
# function to add a ../ to pathnames, avoiding changing absolute ones
AdjustRelative2=$(foreach i,$(1),$(if $(filter /%,$(i)),$(i),../../$(patsubst ./%,%,$(filter-out .,$(i)))))
AdjustRelative=$(foreach i,$(1),$(if $(filter /%,$(i)),$(i),..$(patsubst %,/%,$(patsubst ./%,%,$(filter-out .,$(i))))))
HostProcessor:=$(shell uname -m | tr A-Z a-z)
# Patch darwin's notion of x86 to linux's.  Assumes 64 bit machine...
ifeq ($(HostProcessor),i386)
HostProcessor=x86_64
endif
HostTarget=$(HostSystem)-$(HostProcessor)
OcpiHostTarget=$(HostTarget)
# Physical and realpath are broken on some NFS mounts..
OcpiAbsDir=$(foreach d,$(shell cd $1; pwd -L),$d)
OcpiAbsPath=$(strip \
  $(call OcpiCacheFunctionOnPath,OcpiAbsPathX,$(or $1,.)))
OcpiAbsPathX=$(strip \
  $(foreach p,$(strip \
    $(if $(filter /%,$1),$1,\
      $(if $(filter . ./,$1),$(call OcpiAbsDir,.),\
        $(if $(filter ./%,$1),$(call OcpiAbsDir,.)$(patsubst .%,%,$1),\
          $(call OcpiAbsDir,.)/$1)))),$(abspath $p)))

# Call a function ($1) with a single path argument ($2).
# If this is the first time that function has been called with that argument,
# cache the results. Otherwise, return the cached results.
# $(call OcpiCacheFunctionOnPath,<function-to-call>,<path-argument>)
OcpiCacheFunctionOnPath=$(strip \
  $(or \
    $(foreach c,$(filter $2:%,$(OcpiCacheFunctionOnPath_$1_cache)),\
        $(word 2,$(subst :, ,$c))),\
    $(foreach c,$(call $1,$2),$(eval OcpiCacheFunctionOnPath_$1_cache:=$(OcpiCacheFunctionOnPath_$1_cache) $2:$c)$c)))

# helper function to FindRelative, recursive
# arg 1 is from-list of path components, arg 2 is to-list
#$(info frs 1 $(1) 2 $(2))
FindRelativeStep=\
    $(if $(filter $(firstword $(1)),$(firstword $(2))),\
        $(call FindRelativeStep,$(wordlist 2,$(words $(1)),$(1)),$(wordlist 2,$(words $(2)),$(2))),\
	$(if $(1),$(subst $(Space),/,$(strip $(patsubst %,..,$(1))))$(if $(2),/),$(if $(2),,.))$(subst $(Space),/,$(2)))

# helper function for FindRelative
# arg1 is absolute-from arg2 is absolute-to arg3 is original from, arg4 is original to
#$(info 1 $(1) 2 $(2) 3 $(3) 4 $(4))
FindRelativeTop=$(infoxx FRT:$1:$2:$3:$4)$(strip\
  $(foreach t,\
        $(if $(strip $1),\
            $(if $(strip $2),\
	        $(if $(filter $(firstword $(strip $(subst /, ,$1))),$(firstword $(strip $(subst /, ,$2)))),\
                    $(call FindRelativeStep,$(strip $(subst /, ,$1)), $(strip $(subst /, ,$2))),\
		    $2),\
                $(error Invalid/non-existent path: to "$4" from "$3")),\
             $(error Invalid/non-existent path: from "$3" to "$4")),\
  $(infoxx FRTr:$t:$(CURDIR))$t))

# Function: return the relative path to get from $(1) to $(2).  Useful for creating symlinks
# Note return value must be nicely stripped
#$(info findrel 1 $(1).$(abspath $1) 2 $(2).$(abspath $2))
#$(info pwd:$(shell pwd) abs:$(abspath .) real:$(realpath .))
#FindRelative=$(strip $(call FindRelativeTop,$(call OcpiAbsPath,$1),$(call OcpiAbsPath,$2),$1,$2))
FindRelative=$(strip $(infox FR:$1:$2)\
               $(foreach i,$(call FindRelativeTop,$(call OcpiAbsPath,$1),$(call OcpiAbsPath,$2),$(strip $1),$(strip $2)),$i))

# Function: retrieve the contents of a symlink
# It would be easier using csh
SymLinkContents= `X=(\`ls -l $(1)\`);echo $${X[$${\#X[*]}-1]}`

# Function:
# Make a symlink, but don't touch it if it is already correct
#  First arg is local file to point to, second arg is dir to put link in.
#  e.g. $(call MakeSymLink,foo,linkdir) makes a link: dir/$(notdir foo) link to foo
# Funky because it might be executed in a loop
MakeSymLink2=	$(infox MSL2:$1:$2:$3)SL=$(2)/$(3); SLC=$(call FindRelative,$2,$1); \
		if test -L $$SL; then \
		  OSLC="$(call SymLinkContents,$2/$3)"; \
		else \
		  OSLC=; \
		fi;\
		if test "$$OSLC" != $$SLC; then \
		  rm -f $$SL; \
		  ln -s $$SLC $$SL; \
		fi
MakeSymLink=$(call MakeSymLink2,$(1),$(2),$(notdir $(1)))


# function of that puts stuff in a temporary file and returns its name.
MakeTemp=\
$(shell export TMPDIR=$(TargetDir);\
  TF=`mktemp -t -u`;echo "$(1)" | tr " " "\n"> $$TF;echo $$TF)

# Output directory processing.  OutDir is the internal variable used everywhere.
# It is set based on the public OCPI_OUTPUT_DIR, and is created as needed
ifndef OutDir
ifdef OCPI_OUTPUT_DIR
OutDir=$(OCPI_OUTPUT_DIR)/$(CwdName)/
$(OutDir):
	$(AT)mkdir $@
endif
endif
GeneratedDir=$(OutDir)gen
$(GeneratedDir): | $(OutDir)
	$(AT)mkdir $@

# Make all target dirs
TargetDir=$(OutDir)target-$($(CapModel)Target)
#$(AT)echo Creating target directory: $@
$(OutDir)target-%: | $(OutDir)
	$(AT)mkdir $@

################################################################################
# $(call ReplaceIfDifferent,source-file-or-dir, dest-dir)
# A utility function to compare two trees that might contain binary files
# The first argument is the directory (or file) to be copied, and whose
# "tail" name should be placed in the destination directory
ifeq ($(HostSystem),darwin)
MD5=md5
else
MD5=md5sum -b -
endif
TreeHash=`(if test -f $(1); then \
             cat $(1); \
           elif test -e $(1); then \
             cd $(1); \
             find -L . -type f | sort | xargs cat; \
           fi) \
           | $(MD5)`
ReplaceIfDifferent=\
  TAIL=`basename $(1)`; \
  while test 1; do \
    if test -f $(1); then OLD=$(2)/$$TAIL; else OLD=$(2); fi;\
    if test -e $$NEW; then \
      NEWHASH=$(call TreeHash,$(1));\
      OLDHASH=$(call TreeHash,$$OLD);\
      if test "$$OLDHASH" = "$$NEWHASH"; then\
        echo Installation suppressed for $(1) in $(2). Destination is identical.; \
        break; \
      fi; \
      if test -e $$OLD; then \
        echo Removing previous installation for $(1) in $(2). ; \
        rm -r -f $$OLD; \
      else \
        echo No previous installation for $(1) in $(2). ;\
      fi; \
    fi; \
    if test ! -d $(2); then\
      mkdir -p $(2); \
    fi; \
    echo Installing $(1) into $(2); \
    if test -f $(1); then \
      cp -L -p $(1) $(2); \
    else \
      cp -L -R -p $(1)/* $(2); \
    fi; \
    touch $2; \
    break;\
  done
ReplaceContentsIfDifferent=\
  TAIL=`basename $(1)`; \
  while test 1; do \
    if test -e $(2); then \
      OLD=$(call TreeHash,$(1));\
      NEW=$(call TreeHash,$(2));\
      if test "$$OLD" = "$$NEW"; then\
        echo Installation suppressed for $(1). Destination is identical.; \
        break; \
      fi; \
      echo Removing previous installation for $(1) -\> $(2); \
      rm -r -f $(2); \
    fi; \
    if test ! -d $(2); then\
      mkdir -p $(2); \
    fi; \
    echo Installing $(1) -\> $(2); \
    cp -L -R -p $(1)/* $(2); \
    break;\
  done

################################################################################
# $(call Unique,words,already)
# A utility function to remove duplicates without reordering
# The second argument is just for recursion and should be blank on the call
Unique=$(infox Unique:$1)$(strip $(foreach x,$(call Unique2,$1,),$x))
Unique2=$(infox Unique2:$1:$2:)$(if $1,$(call Unique2,$(wordlist 2,$(words $1),$1),$(strip\
                               $(foreach w,$(firstword $1),$(if $(filter $w,$2),$2,$2 $w)))),$2)

# Take a list of paths, and return the list of
# paths that have unique notdir values
OcpiUniqueNotDir=\
  $(eval NotDiredList= )\
  $(foreach f,$1,\
    $(if $(filter $(notdir $f),$(NotDiredList)),,\
      $(eval NotDiredList+=$(notdir $f) )\
      $f ))

LibraryRefFile=$(call $(CapModel)LibraryRefFile,$1,$2)

################################################################################
# Tools for metadata and generated files
DateStamp := $(shell date +"%c")
ToolsDir=$(eval $(OcpiEnsureToolPlatform))$(OCPI_CDK_DIR)/bin/$(OCPI_TOOL_DIR)
ifeq ($(HostSystem),darwin)
DYN_PREFIX=DYLD_LIBRARY_PATH=$(OCPI_CDK_DIR)/lib/$(OCPI_TOOL_DIR)
else
DYN_PREFIX=LD_LIBRARY_PATH=$(OCPI_CDK_DIR)/lib/$(OCPI_TOOL_DIR)
endif
#$(info OCDK $(OCPI_CDK_DIR))
#DYN_PREFIX=
# Here are the environment variables that might be set in the "make" environment,
# that must be propagated to ocpigen.
OcpiGenEnv=\
    OCPI_PREREQUISITES_DIR="$(OCPI_PREREQUISITES_DIR)" \
    OCPI_HDL_PLATFORM_PATH="$(subst $(Space),:,$(strip \
                              $(call OcpiRelativePathsInsideProjectOrImports,.,$(subst :, ,$(OCPI_HDL_PLATFORM_PATH)))))" \
    OCPI_ALL_HDL_TARGETS="$(OCPI_ALL_HDL_TARGETS)" \
    OCPI_ALL_RCC_TARGETS="$(OCPI_ALL_RCC_TARGETS)" \
    OCPI_ALL_OCL_TARGETS="$(OCPI_ALL_OCL_TARGETS)"

OcpiGenTool=$(OcpiGenEnv) $(OCPI_VALGRIND) $(ToolsDir)/ocpigen \
  $(call OcpiFixPathArgs,$(patsubst %,-I%,$(XmlIncludeDirsInternal)) $1)
# Given a collection of arguments, fix each path in the argument
# that starts with '/' or '-I/' for use with ocpigen or compilation.
# This will prevent absolute paths whenever possible and instead compute
# paths relative to the project's top or 'imports' when possible.
# $(call OcpiFixPathArgs,"-Igen -Itarget-zynq -M target-14-zynq/generics.vh.deps /data/...")
OcpiFixPathArgs=\
  $(foreach p,$1,\
    $(if $(filter /%,$p),\
      $(call OcpiPathThroughProjectTopOrImports,.,$p),\
      $(if $(filter -I/%,$p),\
        $(patsubst %,-I"%",$(call OcpiPathThroughProjectTopOrImports,.,$(patsubst -I%,%,$p))),\
        $p)))
OcpiGenArg=$(DYN_PREFIX) $(call OcpiGenTool, $1 -M $(dir $@)$(@F).deps $2)
OcpiGen=$(call OcpiGenArg,,$1)$(infox OGA:$(call OcpiGenArg,,$1))

# Return stderr and the exit status as variables
# Return non-empty on failure, empty on success, and set var
# $(call DoShell,<command>,<status var>,<value var>)
# 2 limitations:
# - The "#" character is changed to "<pound>" in the output
# - On success, the value will be a combination of stderr and stdout
# Example:
#  $(if $(call DoShell,ls -l,Value),$(error $(Value)),$(Value))
#DoShell=$(eval X:=$(shell X=`bash -c '$1; exit $$?' 2>&1`;echo $$?; echo "$$X" | sed "s/\#/<pound>/g"))$(strip \
#
DoShell=$(eval X:=$(shell X=`bash -c '$1; exit $$?'`;echo $$?; echo "$$X" | sed "s/\#/<pound>/g"))$(strip \
	     $(call OcpiDbg,DoShell($1,$2):X:$X) \
             $(eval $2:=$(wordlist 2,$(words $X),$X))\
	     $(call OcpiDbgVar,$2) \
             $(filter-out 0,$(firstword $X)))

# Convert a space separated string (a make-list) to a python list containing '[,]'
# $(call OcpiConvertListToPythonList,<space-separated-string-list>)
OcpiConvertListToPythonList=$(strip \
  ["$(subst $(Space),"$(Comma) ",$(strip $1))"])

# Import the ocpiutil module and run the python code in $1
# Usage: $(call OcpiCallPythonUtil,ocpiutil.utility_function(arg1, arg2))
OcpiCallPythonUtil=$(infox OPYTHON:$1)\
  $(shell python -c 'import sys; \
sys.path.append("$(OCPI_CDK_DIR)/scripts/"); \
import ocpiutil; \
$1')

# Like the builtin "dir", but without the trailing slash
OcpiDir=$(foreach d,$1,$(patsubst %/,%,$(dir $1)))

# Grab the language attribute out of an XML file the hard way
OcpiGetLangScript:="s/^.*[lL]anguage= *['\"]\([^'\"]*\).*/\1/"
OcpiGetLanguage=$(strip \
    $(call ToLower,\
       $(shell grep -i 'language *= *' $1 | sed $(OcpiGetLangScript))))

# Set the language attribute from the list of xml files in $1
define OcpiSetLanguage
  OcpiLanguage:=$$(sort $$(foreach f,$1,\
		    $$(and $$(realpath $$f),$$(call OcpiGetLanguage,$$f))))
  $$(and $$(word 2,$$(OcpiLanguage)),\
     $$(error Multiple languages found in the worker xml files: $$(OcpiLanguage)))
  $$(call OcpiDbgVar,OcpiLanguage)
  ifndef OcpiLanguage
    OcpiLanguage:=$(Language_$(Model))
  endif
  ifndef Suffix_$(Model)_$$(OcpiLanguage)
    $$(error The language "$$(OcpiLanguage)" is not supported for the "$(Model)" model.)
  endif
endef

# Generate the default XML contents for $1 a worker and $2 a model
# Executed with CWD being the worker directory
OcpiDefaultSpec=$(or $(wildcard ../specs/$1_spec.xml),$(wildcard ../specs/$1-spec.xml))
OcpiDefaultOWD=$(if $(call OcpiDefaultSpec,$1),,$(error No default spec found for worker $1))$(strip \
  <$(call Capitalize,$2)Worker name='$1' \
    language='$(Language_$(Model))' \
    spec='$(notdir $(call OcpiDefaultSpec,$1))'/>)

# Function to generate target dir from target: $(call WkrTargetDir,target,config)
# FIXME: shouldn't really be named "Wkr"
WkrTargetDir=$(OutDir)target$(if $(filter 0,$2),,-$2)-$1

Comma:=,
ParamMsg=$(and $(ParamConfigurations), $(strip \
  '($(foreach n,$(WorkerParamNames),$n=$(ParamMsg_$(ParamConfig)_$n)$(eval o:=1)))'))

RmRv=$(if $(filter %_rv,$1),$(patsubst %_rv,%,$1),$1)

OcpiAdjustLibraries=$(call Unique,$(foreach l,$1,$(if $(findstring /,$l),$(call AdjustRelative,$l),$l)))

################################################################################
# This works when wildcard doesn't.
# (Note: make's wildcard function caches results so can't probe something that
# might come into existence during execution of make)
# There are strange NFS mount use cases that might not return the real path,
# so if that happens, drop to the older/slower Shell call.
OcpiExists=$(infox OEX:$1)$(foreach y,$(foreach x,$(realpath $1),$(if $(filter /%,$x),$1,$(strip $(shell if test -e $1; then echo $1; fi)))),$(infox OEX return $y)$y)

OcpiCheckLinks=$(strip \
  $(foreach d,$1,$d$(shell test -L $d -a ! -e $d && echo " (a link to non-existent/unbuilt?)")))

define OcpiComponentSearchError
The component library "$1" was not found in any of these locations: $(call OcpiCheckLinks,$2)
OCPI_COMPONENT_LIBRARY_PATH is: $(OCPI_COMPONENT_LIBRARY_PATH)
Internal Project Path is: $(OcpiGetProjectPath)
OCPI_CDK_DIR is: $(OCPI_CDK_DIR)
endef

# Given a location of a component library, return the relevant subdirectory
# This normalizes between exported libraries and source libraries
OcpiComponentLibraryExists=$(or $(call OcpiExists,$1/lib),$(call OcpiExists,$1))

# Search for a component library by name, independent of target
# This is not used for component libraries specified by location (with slashes)
# $(call OcpiSearchComponentPath,lib)
OcpiSearchComponentPath=\
  $(eval OcpiTempPlaces:=$(strip\
       $(subst :, ,$(OCPI_COMPONENT_LIBRARY_PATH)) \
       $(foreach d,$(OcpiGetProjectPath),$d/lib)))\
  $(eval OcpiTempDirs:= $(strip \
    $(foreach p,$(OcpiTempPlaces),\
       $(foreach d,$p/$1,$(call OcpiComponentLibraryExists,$d)))))\
  $(or $(OcpiTempDirs)$(infox HTD:$(OcpiTempDirs)),\
    $(if $(filter clean,$(MAKECMDGOALS)),,$(error $(call OcpiComponentSearchError,$1,$(OcpiTempPlaces)))))



# Collect component libraries independent of targets.
# Normalize the list at the spec level
# No arguments
OcpiComponentLibraries=$(strip\
    $(foreach c,$(call Unique,$(ComponentLibraries) $(ComponentLibrariesInternal)),$(infox HCL:$c)\
      $(if $(findstring /,$c),\
         $(or $(call OcpiComponentLibraryExists,$c),\
              $(error Component library $c (from ComponentLibraries, in $(CURDIR)) not found.)),\
         $(call OcpiSearchComponentPath,$c))))

# Return the list of XML search directories for component libraries
# it searches the hdl subdir
# since hdl workers need to be referenced by rcc workers.
OcpiXmlComponentLibraries=$(infox HXC)\
  $(eval OcpiTempDirs:= $(strip \
    $(foreach c,$(OcpiComponentLibraries),$c/hdl $c/$(Model) $c))) \
  $(infox OcpiXmlComponentLibraries returned: $(OcpiTempDirs))\
  $(OcpiTempDirs)

# Return a colon separated default OCPI_LIBRARY_PATH. It contains arg1 (or .), the core project's exports,
# the current project's libraries underneath 'components', and the current project's hdl/assemblies
OcpiGetDefaultLibraryPath=$(infox OGDLP)$(strip \
  $(or $1,.):$(OcpiProjectRegistryDir)/ocpi.core/exports:$(subst $(Space),:,$(strip \
    $(if $(call OcpiAbsPathToContainingProject,$1),\
      $(if $(filter libraries,$(call OcpiGetDirType,$(call OcpiAbsPathToContainingProject)/components)),\
        $(wildcard $(call OcpiAbsPathToContainingProject,$1)/components/*/lib),\
        $(wildcard $(call OcpiAbsPathToContainingProject,$1)/components/lib))\
      $(call OcpiAbsPathToContainingProject,$1)/hdl/assemblies))))

# Export the library path as the default
OcpiSetDefaultLibraryPath=$(eval export OCPI_LIBRARY_PATH=$(call OcpiGetDefaultLibraryPath))

# Collect the projects in path from the different sources.
# OCPI_PROJECT_PATH comes first and is able to shadow the others.
# ProjectDependencies comes next which can be user-defined and is appended with
# the 'required' projects (e.g. core/cdk).
# If CDK is not in the resulting list of projects, add it at the end.
# Warning is suppressed during RPM builds
OcpiGetProjectPath=$(strip \
                     $(foreach p,$(subst :, ,$(OCPI_PROJECT_PATH)) $(OcpiGetProjectDependencies)\
                       $(if $(filter $(realpath $(OCPI_CDK_DIR)),$(realpath $(OcpiGetProjectDependencies))),\
                         ,$(OCPI_CDK_DIR)),\
                       $(or $(call OcpiExists,$p/exports),$(call OcpiExists,$p),$(RPM_BUILD_ROOT),\
                         $(info Warning: The path $p in Project Path does not exist.))))

# There are certain cases where we will want all projects that are 'registered' (not just the ones
# explicitly or implicitly depended on by the current project).
# For example, available platforms can be determined based on all known projects.
# Warning is suppressed during RPM builds
OcpiGetExtendedProjectPath=$(strip $(OcpiGetProjectPath) \
                             $(foreach p,$(OcpiGetImportsNotInDependencies),\
                               $(or $(call OcpiExists,$p/exports),$(call OcpiExists,$p),$(RPM_BUILD_ROOT),\
                                 $(info Warning: The path $p in Project Path does not exist.))))

# Loop through all imported projects and check for 'exports' and then try to find
# rcc/platforms. Return a list of paths to 'rcc/platforms' directories found in each
# imported project. Search the current project's rcc/platforms first. If the current
# project is in OcpiGetExtendedProjectPath, filter it out.
#
# Note: the path 'platforms' without a leading 'rcc/' is searched as well for legacy
#       compatibilty before rcc platforms were supported outside of the CDK
OcpiGetRccPlatformPaths=$(strip \
                          $(foreach p,$(or $(OCPI_PROJECT_DIR),\
                                        $(wildcard $(OcpiProjectRegistryDir)/*)),\
                            $(call OcpiExists,$p/rcc/platforms))\
                          $(foreach p,$(OcpiGetExtendedProjectPath),\
                          $(if $(filter-out $(realpath $(OCPI_PROJECT_DIR)),\
                                            $(realpath $(call OcpiAbsPathToContainingProject,$p))),\
                            $(or $(if $(call OcpiIsPathCdk,$p),\
                              $(call OcpiExists,$p/platforms),\
                              $(if $(filter $(notdir $p),exports),\
                                $(call OcpiExists,$p/lib/rcc/platforms),\
                                $(call OcpiExists,$p/rcc/platforms))),\
                                  $(info Warning: The path $p/rcc/platforms does not exist.)))))

# Search for a given platform ($1) in the list of 'rcc/platform' directories found
# by OcpiGetRccPlatformPaths.
OcpiGetRccPlatformDir=$(strip $(firstword \
		        $(foreach p,$(OcpiGetRccPlatformPaths),\
                          $(call OcpiExists,$p/$1))))

##################################################################################
# Functions for collecting Project Dependencies and imports for use with project
# path
##################################################################################
# Project Dependencies are defined by those explicitly listed in a Project.mk as well as the 'required'
# projects such as core/cdk
OcpiProjectDependenciesInternal=$(strip $(call Unique,$(ProjectDependencies) ocpi.core ocpi.cdk))
# If a project dependency is a path, use it as is. Otherwise, check for it in imports.
OcpiGetProjectDependencies=$(strip \
  $(foreach d,$(OcpiProjectDependenciesInternal),\
    $(if $(findstring /,$d),\
      $d,\
      $(call OcpiGetProjectInImports,.,$d)) ))
# These are the leftover imports that are not listed in the ProjectDependencies
OcpiGetImportsNotInDependencies=$(strip \
  $(foreach i,$(OcpiGetProjectImports),\
    $(if $(filter $(notdir $i),$(OcpiProjectDependenciesInternal)),\
      ,\
      $i) ))

###################################################################################
# Functions for collecting paths to/through/from the top level of a project
# and potentially through a project's 'imports' directory
###################################################################################
# This is the 'project registry' where symlinks
# exist to any projects created on a system.
# If inside a project, try to use its imports.
OcpiProjectRegistryDir=$(strip \
  $(or \
    $(and $(OCPI_PROJECT_DIR),$(call OcpiExists,$(call OcpiImportsDirForContainingProject,$1))),\
    $(strip $(OCPI_PROJECT_REGISTRY_DIR)),\
    $(if $(strip $(OCPI_CDK_DIR)),\
      $(OCPI_CDK_DIR)/../project-registry,\
      $(error Error: OCPI_CDK_DIR is unset))))

# Return the path to the 'imports' directory for the project containing $1
# $(call OcpiImportsDirForContainingProject,.)
OcpiImportsDirForContainingProject=$(strip $(foreach p,$(call OcpiAbsPathToContainingProject,$1),$p/imports))

# Return the list of projects that are imported by the project containing.
# Do no include the current project if it is found in imports.
# $(call OcpiGetProjectImports)
OcpiGetProjectImports=$(strip \
  $(foreach p,$(foreach i,$(if $(filter clean%,$(MAKECMDGOALS)),\
                            $(OcpiProjectRegistryDir),\
                            $(call OcpiImportsDirForContainingProject,.)),\
	        $(wildcard $i/*)),\
    $(if $(filter $(realpath $p),$(realpath $(OcpiAbsPathToContainingProject))),\
      ,\
      $p )))

# Determine if a path is in fact the CDK. If so, return the CDK's
# import alias 'ocpi.cdk'
# $(call OcpiIsPathCdk,<path>)
OcpiIsPathCdk=$(strip \
  $(if $(filter $(realpath $1),$(realpath $(OCPI_CDK_DIR))),ocpi.cdk))

# Given an 'origin' path ($1) and a path to a 'destination' project $2,
# if the 'destination' project is imported in 'origin's project,
# return the path to that import.
#
# If $2 is just a name (not a path), just check a link with that name is
# imported.
#
# If $2 is not found in imports by name, check if it is actually the CDK,
# in which case use the CDK import alias
#
# If no import with the correct name exists, make one last attempt to find
# the requested import by checking the 'realpath' of each import against $2
# $(call OcpiGetProjectInImports,<origin-path>,<destination-project>)
OcpiGetProjectInImports=$(strip \
  $(foreach i,$(if $(filter clean%,$(MAKECMDGOALS)),\
                $(call OcpiProjectRegistryDir,$1),\
                $(call OcpiImportsDirForContainingProject,$1)),\
    $(or \
      $(if $(filter $2,$(notdir $2)),\
        $(call OcpiExists,$i/$2)),\
      $(foreach a,$(call OcpiExists,$i/$(notdir $2)),\
        $(if $(filter $(realpath $a),$(realpath $2)),$a)),\
      $(call OcpiExists,$(foreach c,$(call OcpiIsPathCdk,$2),$i/$c)),\
      $(foreach a,$(wildcard $i/*),\
        $(if $(filter $(realpath $a),$(realpath $2)),$a)))))

# Given an 'origin' path ($1) and a 'destination' path $2,
# if the 'destination's project is imported in 'origin's project,
# return that import (imports/<destination-project>
# $(call OcpiGetRelevantProjectImport,<origin-path>,<destination-path>)
OcpiGetRelevantProjectImport=$(strip $(infox OGRPI:$1:$2)\
  $(foreach a,$(call OcpiAbsPathToContainingProject,$2),\
    $(foreach i,$(call OcpiGetProjectInImports,$1,$a),\
      imports/$(notdir $i))))

# Given a path, determine the relative path to the project containing it
# $(call OcpiRelPathToContainingProject,<path>)
OcpiRelPathToContainingProject=$(strip $(infox ORPTCP:$1)\
  $(call OcpiCacheFunctionOnPath,OcpiRelPathToContainingProjectX,$(call OcpiAbsPath,$(or $1,.))))
OcpiRelPathToContainingProjectX=$(strip \
  $(if $(filter project,$(call OcpiGetDirType,$1)),\
    $(or $2,.),\
    $(if $(call OcpiExists,$1),\
      $(if $(filter $(dir $1),"/"),\
        $(warning Path $1 is not inside a project.),\
        $(call OcpiRelPathToContainingProjectX,$(call OcpiDir,$1),$(or $2,.)/..)))))

# Given a path, determine the absolute path to the project containing it
# $(call OcpiAbsPathToContainingProject,<path>)
OcpiAbsPathToContainingProject=$(strip $(infox OAPTCP:$1)\
  $(call OcpiCacheFunctionOnPath,OcpiAbsPathToContainingProjectX,$(call OcpiAbsPath,$(or $1,.))))
OcpiAbsPathToContainingProjectX=$(strip \
  $(if $(filter project,$(call OcpiGetDirType,$1)),\
    $1,\
    $(if $(call OcpiExists,$1),\
      $(if $(filter $(dir $1),"/"),\
        $(warning Path $1 is not inside a project.),\
        $(call OcpiAbsPathToContainingProjectX,$(call OcpiDir,$1))))))

# If two paths are contained in the same project, return the path to the project
# Otherwise return empty
# Note: We need to get the real/abs path to ensure that they are of the same form.
#       This will allow 'filter' to correctly determine if they are the same.
#
# $(call OcpiArePathsInSameProject,<path1>,<path2>)
OcpiArePathsInSameProject=$(strip $(infox OAPISP:$1:$2)\
  $(filter $(realpath $(call OcpiAbsPathToContainingProject,$1)),$(realpath $(call OcpiAbsPathToContainingProject,$2))))

# Given a path, determine the path from the top level of the containing project.
# This path will NOT include the path TO the current project.
# E.g: /data/myproject/hdl/platforms -> hdl/platforms
# $(call OcpiGetPathFromProjectTop,<path>)
OcpiPathFromProjectTop=$(strip $(infox OPFPT:$1)\
  $(patsubst %/,%,$(call OcpiCacheFunctionOnPath,OcpiPathFromProjectTopX,$(call OcpiAbsPath,$1))))
OcpiPathFromProjectTopX=$(strip \
  $(if $(filter project,$(call OcpiGetDirType,$1)),\
    ,\
    $(if $(call OcpiExists,$1),\
      $(if $(filter $(dir $1),$1),\
        $(warning CWD is not inside a project.),\
        $(call OcpiPathFromProjectTopX,$(call OcpiDir,$1))$(notdir $1)/))))

# Given an 'origin' path ($1) and a 'destination' path $2:
# If the 'destination's project is imported in 'origin's project,
#   return the path from $1 to $2 through 'origin's imports.
# Otherwise, just return the absolute path to $2
# $(call OcpiPathToAssetOutsideProject,<origin-path>,<destination-path>)
OcpiPathToAssetOutsideProject=$(strip $(infox OPTAOP:$1:$2)\
  $(or \
  $(strip $(foreach i,$(call OcpiGetRelevantProjectImport,$1,$2),\
      $(if $i,$(call OcpiRelPathToContainingProject,$1)/$i/$(call OcpiPathFromProjectTop,$2)))),\
    $(call OcpiAbsPath,$2)))

# Given an 'origin' path ($1) and a 'destination' path $2:
# If the 'destination's project is imported in 'origin's project,
#   return the path from the top level of 'origin's project to $2
#   through 'origin's imports.
# Otherwise, just return the absolute path to $2
# $(call OcpiPathFromProjectTopToAssetOutsideProject,<origin-path>,<destination-path>)
OcpiPathFromProjectTopToAssetOutsideProject=$(strip $(infox OPFPTAOP:$1:$2)\
  $(or \
    $(strip $(foreach i,$(call OcpiGetRelevantProjectImport,$1,$2),\
      $i/$(call OcpiPathFromProjectTop,$2))),\
    $(call OcpiAbsPath,$2)))

# Given an 'origin' path ($1) and a 'destination' path $2:
# If the paths are in the same project,
#   return the path from $1 to $2 through the project top.
# Otherwise,
#   return the path through 'origin's imports or the return absolute path.
# $(call OcpiPathThroughProjectTopOrImports,<origin-path>,<destination-path>)
OcpiPathThroughProjectTopOrImports=$(strip $(infox OPTPTOI:$1:$2)\
  $(and $(call OcpiExists,$2),\
    $(if $(call OcpiArePathsInSameProject,$1,$2),\
      $(call OcpiRelPathToContainingProject,$1)/$(call OcpiPathFromProjectTop,$2),\
      $(call OcpiPathToAssetOutsideProject,$1,$2))))

# Return the paths from $1 through the project top (and possibly imports) to each
# path in $2
# $(call OcpiRelativePathsInsideProjectOrImports,<origin-path>,<destination-paths>)
OcpiRelativePathsInsideProjectOrImports=$(strip $(infox ORPIPOI:$1:$2)\
  $(foreach p,$2,$(call OcpiPathThroughProjectTopOrImports,$1,$p) ))

# Given an 'origin' path ($1) and a 'destination' path $2:
# If the paths are in the same project,
#   return the path to $2 from the project top.
# Otherwise,
#   return the path through 'origin's imports or return the absolute path
# $(call OcpiPathFromProjectTopOrImports,<origin-path>,<destination-path>)
OcpiPathFromProjectTopOrImports=$(strip $(infox OPFPTOI:$1:$2)\
  $(and $(call OcpiExists,$2),\
    $(if $(call OcpiArePathsInSameProject,$1,$2),\
      $(call OcpiPathFromProjectTop,$2),\
      $(call OcpiPathFromProjectTopToAssetOutsideProject,$1,$2))))

# Return the paths from $1's project top (and possibly through imports) to each
# path in $2
# $(call OcpiPathsFromProjectTopOrImports,<origin-path>,<destination-paths>)
OcpiPathsFromProjectTopOrImports=$(strip $(infox ORPIPOI:$1:$2)\
  $(foreach p,$2,$(call OcpiPathFromProjectTopOrImports,$1,$p) ))

###################################################################################

# Add a directory to the front of a path in the environment
# $(call OcpiPrependEnvPath,var-name,dir)
OcpiPrependEnvPath=\
  $(eval tmp:=$(wildcard $2))\
  $(infox PREPEND:$1:$2:$(tmp))\
  $(and $(tmp),$(eval export $1:=$(subst $(Space),:,$(call Unique,$(tmp) $(subst :, ,$($1))))))

############ Project related functions

# Set the given directory as the project directory, include the Project.mk file that is there
# and setting an environment variable OCPI_PROJECT_DIR to that place.
# This allows any path-related settings to be relative to the project dir
define OcpiSetProject
  # This might already be set
  $$(call OcpiDbg,Setting project to $1)
  OcpiTempProjDir:=$$(call OcpiAbsDir,$1)
  $$(infox OTPD:$1:$$(OcpiTempProjDir))
  ifdef OCPI_PROJECT_DIR
    ifneq ($$(OcpiTempProjDir),$$(OCPI_PROJECT_DIR))
      $$(error OCPI_PROJECT_DIR in environment is $$(OCPI_PROJECT_DIR), but found Project.mk in $1)
    endif
  endif
  override OCPI_PROJECT_DIR=$$(OcpiTempProjDir)
  export OCPI_PROJECT_DIR

  # Save the Package, PackagePrefix, and PackageName variables
  # so that they can be used as is later on (if set at the command
  # or in a 'Makefile' file), but so they do not interfere with
  # ProjectPackage results
  PackageSaved:=$$(Package)
  export Package:=
  PackagePrefixSaved:=$$(PackagePrefix)
  export PackagePrefix:=
  PackageNameSaved:=$$(PackageName)
  export PackageName:=

  # Include Project.mk to determine ProjectPackage
  include $1/Project.mk
  # Determine ProjectPackage as follows:
  # If it is already set, use it as-is
  # If ProjectPackage or Package is set, use that as-is
  # Otherwise, use PackagePrefix.PackageName
  # PackagePrefix defaults to 'local'
  # PackageName defaults to directory name
  ifndef ProjectPackage
    ifneq ($$(Package),)
      override ProjectPackage:=$$(Package)
    else
      ifeq ($$(PackagePrefix),)
        override PackagePrefix:=local
      endif
      ifeq ($$(PackageName),)
        override PackageName:=$$(notdir $$(call OcpiAbsDir,$1))
      endif
      override ProjectPackage:=$$(if $$(PackagePrefix),$$(patsubst %.,%,$$(PackagePrefix)).)$$(PackageName)
    endif
  endif

  # Restore the Package* variables in case they were set at the command line
  # for a library or in a library 'Makefile'
  Package:=$$(PackageSaved)
  PackagePrefix:=$$(PackagePrefixSaved)
  PackageName:=$$(PackageNameSaved)

  # A project is always added to the below-project/non-project search paths
  # I.e. where the project path looks for other projects, and their exports,
  # the current project is searched internally, not in exports
  # when looking for (non-slash) primitives, look in this project, not exports
  $$(call OcpiPrependEnvPath,OCPI_HDL_PRIMITIVE_PATH,$$(OcpiTempProjDir)/hdl/primitives/lib)
  # when looking for platforms, look in this project
  $$(call OcpiPrependEnvPath,OCPI_HDL_PLATFORM_PATH,$$(OcpiTempProjDir)/hdl/platforms)
  # when looking for XML specs and protocols, look in this project
  $$(call OcpiPrependEnvPath,OCPI_XML_INCLUDE_PATH,$$(OcpiTempProjDir)/specs)
  # when looking for component libraries, look in this project, without depending on
  # exports, and also include the hdl/devices library
  # 1. specifically add each library in the project to "componentlibraries"
  # 2. add each place in the project where libraries live to the component library search path.
  $$(foreach l,$$(wildcard $$(OcpiTempProjDir)/hdl/devices) \
    $$(if $$(filter libraries,$$(call OcpiGetDirType,$$(OcpiTempProjDir)/components)),\
      $$(foreach m,$$(wildcard $$(OcpiTempProjDir)/components/*/Makefile),$$(infox MMM:$$m)\
         $$(foreach d,$$(m:%/Makefile=%),$$(infox DDD:$$d)\
            $$(and $$(filter library,$$(call OcpiGetDirType,$$d)),$$d))),\
      $$(OcpiTempProjDir)/components),\
    $$(eval override ComponentLibrariesInternal:=$$(call Unique,$(ComponentLibrariesInternal) $$(notdir $$l))) \
    $$(call OcpiPrependEnvPath,OCPI_COMPONENT_LIBRARY_PATH,$$(patsubst %/,%,$$(dir $$l))))
endef
ifdef NEVER
  # when executing applications, look in this project
  ifndef OCPI_PROJECT_ADDED_TARGET_DIRS
    $$(warning Adding all target directories in the project to OCPI_LIBRARY_PATH)
    $$(call OcpiPrependEnvPath,OCPI_LIBRARY_PATH,\
       $$(OcpiTempProjDir)/components/lib/rcc \
       $$(OcpiTempProjDir)/components/*.test/assemblies/*/container*/target-* \
       $$(OcpiTempProjDir)/components/*/lib/rcc \
       $$(OcpiTempProjDir)/components/*/*.test/assemblies/*/container*/target-* \
       $$(OcpiTempProjDir)/hdl/assemblies/*/container*/target-*)
    $$(warning Adding all target directories in the project to OCPI_LIBRARY_PATH)
    export OCPI_PROJECT_ADDED_TARGET_DIRS:=1
  endif
endif
# Look into a directory in $1 and determine which type of directory it is by looking at the Makefile.
# Also checks Makefile.am for autotools version
# If a dirtype is not found, check if $1 is the CDK. If so, return 'project'
# Return null if there is no type to be found
OcpiGetDirType=$(strip\
  $(call OcpiCacheFunctionOnPath,OcpiGetDirTypeX,$1))
OcpiGetDirTypeX=$(strip $(infox GDT1:$1)\
  $(or \
    $(and $(wildcard $1/Makefile),\
      $(foreach d,$(shell sed -n \
                  's=^[ 	]*include[ 	]*.*OCPI_CDK_DIR.*/include/\(.*\).mk$$=\1=p' \
                  $1/Makefile | tail -1),\
      $(infox OGT1: found type: $d ($1))$(notdir $d))) \
    ,$(and $(wildcard $1/Makefile.am),\
      $(foreach d,$(shell sed -n \
                  's=^[ 	]*@AUTOGUARD@[ 	]*include[ 	]*.*OCPI_CDK_DIR.*/include/\(.*\).mk$$=\1=p' \
                  $1/Makefile.am | tail -1),\
      $(warning Found what I think is a $d in "$1", but it is not fully configured and may not work as expected.)$(notdir $d))) \
    ,$(and $(filter $(realpath $1),$(realpath $(OCPI_CDK_DIR))),project)\
  ) \
)

# Get the directory type of arg1, and return the portion after the last dash.
# E.g. in an hdl-platform directory, this will return platform
OcpiGetShortenedDirType=$(strip \
  $(foreach t,$(lastword $(subst -, ,$(call OcpiGetDirType,$1))),\
    $(if $(filter lib,$t),library,$t)))

###############################################################################
# Functions for including an asset and its parents
###############################################################################

# Recursive
OcpiIncludeProjectX=$(infox OIPX:$1:$2:$3)\
  $(if $(wildcard $1/Project.mk),\
    $(if $(wildcard $1/Makefile)$(wildcard $1/Makefile.am),\
      $(if $(filter project,$(call OcpiGetDirType,$1)),\
       $(infox found project in $1)$(eval $(call OcpiSetProject,$1)),\
       $(error no proper Makefile found in the directory where Project.mk was found ($1))),\
      $(error no Makefile found in the directory where Project.mk was found ($1))),\
    $(if $(foreach r,$(realpath $1/..),$(filter-out /,$r)),\
      $(call OcpiIncludeProjectX,$1/..,$2,$3),\
      $(call $2,$2: no Project.mk was found here ($3) or in any parent directory)))

# One arg is what to do if not found: error, warning, nothing
# FIXME: can we avoid this when cleaning?
OcpiIncludeProject=$(call OcpiIncludeProjectX,$(or $(OCPI_PROJECT_DIR),.),$1,$(call OcpiAbsDir,.))

# OcpiIncludeParentAsset_<asset-type> defines how to include an asset's parent.
# This is done on a per-asset-type basis (e.g. platform, platforms, library ...).
# If an asset-type does not define an OcpiIncludeParentAsset_<asset-type> function,
# it is assumed that the project itself is the parent.
#
# For OcpiIncludeParentAsset_* functions, arguments are as follows:
#   Arg1 = reference directory
#   Arg2 = error/warning/info mode

# So, for library, first check if this is a platform's devices library.
# If so, include the parent (../) with type Platform so it can
# find Platform.mk if it exists. Otherwise, the parent is just the project
OcpiIncludeParentAsset_library=\
  $(if $(filter %-platform,$(call OcpiGetDirType,$1/../)),\
    $(call OcpiIncludeAssetAndParentX,$1/../,$2),\
    $(call OcpiIncludeProject,$2))

# For a platform directory, we include the platforms directory in ../
# We provide it with type Platforms so it can find the Platforms.mk
# file if it exists. If the platform is not inside a platforms directory,
# then it is not in a project at all and does not have a parent.
OcpiIncludeParentAsset_platform=\
  $(if $(filter %-platforms,$(call OcpiGetDirType,$1/../)),\
    $(call OcpiIncludeAssetAndParentX,$1/../,$2))

# For asset in directory arg1, look for makefile <arg2>.mk and include it to
# extract any variables that are set.  Clear the package variables so that the
# current asset's environment is not polluted with package variables from a
# parent assets settings
#   Arg1 = reference directory
#   Arg2 = shortened directory type with capitalized first letter
#            this is the word used to find the .mk  file
#            e.g. Library, Platforms, Platform
define OcpiSetAsset
  Package:=
  unexport Package
  PackagePrefix:=
  unexport PackagePrefix
  PackageName:=
  unexport PackagePrefix
  ifneq ($$(wildcard $1/$2.mk),)
    include $1/$2.mk
  endif
endef

# First determine the shortened directory type which is the portion
# of dirtype after the last '-' (e.g. hdl-platforms -> platforms).
#   Store this value in s
# Next, save a version of this shortened dirtype with the first letter
# capitalized so that the *.mk file can be found (e.g. Library.mk)
#   Store this in c
# Note: the two outer loops will only ever have one iteration. They
#       are essentially just saying:
#         s = shortened_dir_type(<arg1>)
#         c = capitalize_first_letter(s)
#
# If the current asset's parent defines an OcpiIncludeParentAsset_<asset-type>
# function, call that to include the parent. Otherwise parent is the project,
# so include the project. Next, include the current asset by importing its
# *.mk file and determining its package via OcpiSetAndGetPackageId
#   Arg1 = reference directory
#   Arg2 = error/warning/info mode (optional)
OcpiIncludeAssetAndParentX=$(infox OIAAPX:$1:$2)$(strip \
  $(foreach s,$(call OcpiGetShortenedDirType,$1),\
    $(foreach c,$(call Capitalize,$s),\
      $(if $(filter-out undefined,$(origin OcpiIncludeParentAsset_$s)),\
        $(call OcpiIncludeParentAsset_$s,$1,$c,$2),\
        $(call OcpiIncludeProject,$2))\
      $(eval $(call OcpiSetAsset,$1,$c))\
      $(eval ParentPackage:=)\
      $(eval unexport ParentPackage)\
      $(eval override ParentPackage:=$(call OcpiSetAndGetPackageId,$1)))))

# Wrapper function for OcpiIncludeAssetAndParentX. package.mk is included here
# so that it is not included many times during recursive calls of the *X
# function above. This function assumes Arg1 should be the current directory if
# none is provided. Finally, it determines the shortened and capitalized
# directory type to be used for finding *.mk files.
#   Arg1 = reference directory
#   Arg2 = error/warning/info mode (optional)
OcpiIncludeAssetAndParent=$(strip \
  $(eval include $(OCPI_CDK_DIR)/include/package.mk)\
  $(call OcpiIncludeAssetAndParentX,$(or $1,.),$2))

###############################################################################

# Find the subdirectories that make a Makefile that includes something
OcpiFindSubdirs=$(strip \
  $(foreach a,$(wildcard */Makefile),\
    $(shell grep -q '^[ 	]*include[ 	]*.*/include/$1.mk' $a && echo $(patsubst %/,%,$(dir $a)))))

OcpiHavePrereq=$(realpath $(OCPI_PREREQUISITES_DIR)/$1)
OcpiPrereqDir=$(call OcpiHavePrereq,$1)
OcpiCheckPrereq=$(strip\
   $(if $(realpath $(OCPI_PREREQUISITES_DIR)/$1),,\
      $(error The $1 prerequisite package is not installed)) \
   $(and $2,$(foreach t,$2,$(if $(realpath $(OCPI_PREREQUISITES_DIR)/$1/$t,, \
               $(error The $1 prerequisite package is not build for target $t)))\
            $(and $3,$(if $(realpath $(OCPI_PREREQUISITES_DIR)/$1/$t/$3),,\
                         $(error For the $1 prerequisite package, $t/$3 is missing))))))

define OcpiEnsureToolPlatform
  ifndef OCPI_TOOL_HOST
    GETPLATFORM=$(OCPI_CDK_DIR)/scripts/getPlatform.sh
    vars:=$$(shell $$(GETPLATFORM))
    ifneq ($$(words $$(vars)),6)
      $$(error $$(OcpiThisFile): Could not determine the platform after running $$(GETPLATFORM)).
    endif
    export OCPI_TOOL_OS:=$$(word 1,$$(vars))
    export OCPI_TOOL_OS_VERSION:=$$(word 2,$$(vars))
    export OCPI_TOOL_ARCH:=$$(word 3,$$(vars))
    export OCPI_TOOL_HOST:=$$(word 4,$$(vars))
    export OCPI_TOOL_PLATFORM:=$$(word 5,$$(vars))
    export OCPI_TOOL_PLATFORM_DIR:=$$(word 6,$$(vars))
  endif
  # Determine OCPI_TOOL_MODE if it is not set already
  # It can be set to null to suppress these modes, and just use whatever has been
  # built without modes.
  ifeq ($$(OCPI_USE_TOOL_MODES),1)
    ifndef OCPI_TOOL_MODE
      # OCPI_TOOL_MODE not set at all, just look for one
      $$(foreach i,sd so dd do,\
        $$(if $$(OCPI_TOOL_MODE),,\
          $$(and $$(wildcard $$(OCPI_CDK_DIR)/$$(OCPI_TOOL_HOST)/$$i/ocpigen),\
            $$(eval export OCPI_TOOL_MODE=$$i)\
            $$(info "Choosing tool mode "$$i" since there are tool executables for it."))))
    endif
    ifndef OCPI_TOOL_MODE
      ifeq ($$(wildcard $$(OCPI_CDK_DIR)/bin/$$(OCPI_TOOL_HOST)/ocpigen),)
        $$(info Could not find any OpenCPI executables in $$(OCPI_CDK_DIR)/$$(OCPI_TOOL_HOST)/*)
	OCPI_TOOL_MODE:=$$(strip \
          $$(if $$(filter 1,$$(OCPI_DYNAMIC)),d,s)$$(if $$(filter 1,$$(OCPI_DEBUG)),d,o))
        $$(info Assuming you are building OpenCPI from scratch:  tool mode will be "$$(OCPI_TOOL_MODE)".)
      endif
      export OCPI_TOOL_MODE=
    endif
  endif
  export OCPI_TOOL_DIR:=$$(OCPI_TOOL_HOST)$$(and $$(OCPI_TOOL_MODE),/$$(OCPI_TOOL_MODE))
endef
# First arg is a list of exported variables/patterns that must be present.
# Second arg is a list of exported variables/patterns that may be present.
# This arg is the command to execute
OcpiShellWithEnv=$(shell $(foreach e,$1,\
                           $(if $(filter $e,$(.VARIABLES)),\
                             $(foreach v,$(filter $e,$(.VARIABLES)),$v=$($v)),\
                             $(error for OcpiShellWithEnv, variable $v not set))) \
                          $(foreach e,$2,\
                            $(foreach v,$(filter $e,$(.VARIABLES)),$v=$($v))) \
                         $3)

$(call OcpiDbg,End of util.mk)

# Set up the standard set of places to look for xml files.
define OcpiSetXmlIncludes
# Here we add access to:
# 0. The current directory
# 1. The generated directory
# 2. What is locally set in the worker's Makefile (perhaps to override specs/protocols)
# 3. What was passed from the library Makefile above (perhaps to override specs/protocols)
# 4. The library's export directory to find other (slave or emulated) workers
# 5. The library's specs directory
# 6. Any other component library's XML dirs
# 6. The standard component library for specs
# 7. The standard component library's exports for proxy slaves
$(eval override XmlIncludeDirsInternal:=\
  $(call Unique,\
    . $(GeneratedDir) \
    $(XmlIncludeDirs) \
    $(XmlIncludeDirsInternal) \
    $(Models:%=../lib/%)\
    ../specs \
    $(OcpiXmlComponentLibraries) \
    $(foreach d,$(subst :, ,$(OCPI_XML_INCLUDE_PATH)),$(wildcard $d)) \
    $(foreach d,$(OcpiGetProjectPath),$(wildcard $d/specs)) \
    $(OCPI_CDK_DIR)/lib/components/hdl\
    $(OCPI_CDK_DIR)/lib/components/$(Model)\
    $(OCPI_CDK_DIR)/lib/components \
    $(OCPI_CDK_DIR)/specs \
   ))
endef

# Used wherever test goals are processed.  runtests is for compatibility
# These are goals that *only* apply to testing.
# .test directories also support more generic targets, in particular "clean" and "cleanrun"
OcpiTestGoals=test cleantest runtest verifytest cleansim runtests runonlytest cleanrun
# Used globally when building executables
OcpiPrereqLibs=lzma gmp

OcpiCheckVars=$(and $($1),$(error The "$1" variable is set in both the Makefile and the *-build.xml file.))

OcpiBuildFile=$(or $(call OcpiExists,$(Worker).build),$(call OcpiExists,$(Worker)-build.xml))

# What to do early in each top level Makefile to process build files.
ParamShell=\
  if [ -n "$(OcpiBuildFile)" -a -r "$(OcpiBuildFile)" ] ; then \
    (mkdir -p $(GeneratedDir) &&\
    $(call MakeSymLink2,$(OcpiBuildFile),$(GeneratedDir),$(Worker)-build.xml); \
    $(call OcpiGenTool, -D $(GeneratedDir) $(and $(Package),-p $(Package))\
      $(and $(Platform),-P $(Platform)) \
      $(and $(PlatformDir), -F $(PlatformDir)) \
      $(HdlVhdlLibraries) \
      $(and $(Assembly),-S $(Assembly)) \
      -b $(Worker_$(Worker)_xml))) || echo 1;\
  else \
    (mkdir -p $(GeneratedDir) &&\
    $(MakeRawParams) |\
    $(call OcpiGenTool, -D $(GeneratedDir) $(and $(Package),-p $(Package))\
      $(and $(Platform),-P $(Platform)) \
      $(and $(PlatformDir), -F $(PlatformDir)) \
      $(HdlVhdlLibraries) \
      $(and $(Assembly),-S $(Assembly)) \
      -r $(Worker_$(Worker)_xml))) || echo 1;\
  fi

# Create the internal, transient XML document to convey property values in the Makefile
# to the tool which will generate a build file, and an internal Makefile which will
# then be included
# 1. The core syntax is from our textual encoding of data types.
# 2. "Make" pretty much allows anything but # and newline in an assignment - both can
#    be escaped using backslash, so in fact there are three special characters
#    #, \, and <newline>, but newlines will never be included.
# 3. When we output the file as XML, we need to deal with XML quoting conventions.
#    But XML textual data has only two things to protect: < and &.
#    But our format also has backslash encoding too.
# 4. The Values string has slashes to separate values
# 5. We need a shell command to produce the output.
#    Metacharacters for the shell are: | & ; ( ) < > space tab
#    Backslash protects everything
#    Single quotes can't protect single quotes
#    Double quotes don't protect $ ` \ !
# Since XML already has a mechanism to encode single quotes (&apos;), using single quotes is best.
MakeRawParams= \
  (echo "<parameters>"; \
   $(foreach i,$(RawParamVariables),\
     echo "<parameter name='$(call RawParamName,$i)'$(strip \
                      )$(if $(filter ParamValues_%,$i), values='true')>";\
     echo '$(subst <,&lt;,$(subst ',&apos;,$(subst &,&amp;,$($i))))';\
     echo "</parameter>";) \
   echo "</parameters>")

# This must be done early to allow the make file fragment that is generated from the -build.xml
# file to be processed as if it was a user-written Makefile, before most other processing
define OcpiProcessBuildFiles

ifeq ($(filter clean,$(MAKECMDGOALS)),)

# PreProcess any parameters defined in the Makefile itself, for use by MakeRawParams
RawParamVariables:=$$(filter Param_%,$$(.VARIABLES)) $$(filter ParamValues_%,$$(.VARIABLES))
RawParamName=$$(if $$(filter Param_%,$$1),$$(1:Param_%=%),$$(1:ParamValues_%=%))
RawParamNames:=$$(foreach v,$$(RawParamVariables),$$(call RawParamName,$$v))
ifneq ($$(words $$(RawParamNames)),$$(words $$(sort $$(RawParamNames))))
  $$(error Both Param_ and ParamValues_ used for same parameter.)
endif

# These are included to know the universe of possible platforms, which is required when
# the build files are processed
# FIXME: make a narrower rcc-targets.mk
# FIXME: make this generated by the list of known models
include $(OCPI_CDK_DIR)/include/hdl/hdl-targets.mk
include $(OCPI_CDK_DIR)/include/rcc/rcc-make.mk

# This is called here since some xml include dirs may be set in the original Makefile
# But if some are set in the build file, they will be processed internally in ocpigen
# when it is parsed before reading the OWD
$$(call OcpiDbgVar,XmlIncludeDirsInternal)
$$(call OcpiSetXmlIncludes)
$$(call OcpiDbgVar,XmlIncludeDirsInternal)

# Process the build file one of two ways:
# 1. If there is no build file, create one in gen/, based on what is found in the Makefile
#    which uses MakeRawParams to feed the parameter in the Makefile into ocpigen -r
# 2. If there is a build file, process it.
# In both cases, a gen/<wkr>.mk file is created and then included

$$(call OcpiDbgVar,ParamShell)
X:=$$(shell $$(ParamShell))
$$(and $$X,$$(error Failed to process initial parameters for this worker: $$X))
include $(GeneratedDir)/$(Worker).mk
WorkerParamNames:=\
    $$(foreach p, \
      $$(filter ParamMsg_$$(firstword $$(ParamConfigurations))_%,$$(.VARIABLES)),\
      $$(p:ParamMsg_$$(firstword $$(ParamConfigurations))_%=%))
$$(call OcpiDbgVar,WorkerParamNames)
$$(call OcpiDbgVar,ParamConfigurations)

endif # if not cleaning

endef # OcpiProcessBuildFiles

endif # ifndef __UTIL_MK__
