#
# %CopyrightBegin%
#
# SPDX-License-Identifier: Apache-2.0
#
# Copyright Ericsson AB 1997-2025. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# %CopyrightEnd%
#
include $(ERL_TOP)/make/target.mk
include $(ERL_TOP)/make/$(TARGET)/otp.mk

# ----------------------------------------------------
# Target Specs
# ----------------------------------------------------

EI_MODULES= \
	ei_accept_SUITE \
	ei_connect_SUITE \
	ei_decode_SUITE \
	ei_decode_encode_SUITE \
	ei_encode_SUITE \
	ei_format_SUITE \
	ei_print_SUITE \
	ei_tmo_SUITE \
	erl_call_SUITE \
	ei_global_SUITE \
	port_call_SUITE \
	runner

ERTS_MODULES= erts_test_utils

MODULES=$(EI_MODULES) $(ERTS_MODULES)

SPEC_FILES = \
	erl_interface.spec erl_interface_smoke.spec

COVER_FILE = erl_interface.cover

ERL_FILES = $(EI_MODULES:%=%.erl) $(ERTS_MODULES:%=$(ERL_TOP)/erts/emulator/test/%.erl)

# ----------------------------------------------------
# Release directory specification
# ----------------------------------------------------
RELSYSDIR = $(RELEASE_PATH)/erl_interface_test

# ----------------------------------------------------
# Targets
# ----------------------------------------------------

tests $(TYPES):

clean:

docs:

# ----------------------------------------------------
# Release Target
# ---------------------------------------------------- 
include $(ERL_TOP)/make/otp_release_targets.mk

release_spec:

release_tests_spec: opt
	$(INSTALL_DIR) "$(RELSYSDIR)"
	$(INSTALL_DATA) $(SPEC_FILES) $(COVER_FILE) $(ERL_FILES) "$(RELSYSDIR)"
	chmod -R u+w "$(RELSYSDIR)"
	@tar cf - *_SUITE_data | (cd "$(RELSYSDIR)"; tar xf -)

release_docs_spec:
