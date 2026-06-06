# rtl2gds-sta-lab — wrapper around a pinned OpenROAD-flow-scripts (ORFS) tree,
# driven with a native conda toolchain (see scripts/bootstrap.sh + scripts/env.sh).
#
#   make smoke                          # gcd/sky130hd -> route (toolchain proof)
#   make <stage> CONFIG=config/foo.mk   # stage in {synth floorplan place cts route finish}
#   make sta     CONFIG=config/foo.mk   # signoff STA: top-5 setup/hold + skew (run after finish)
#   make report  CONFIG=config/foo.mk   # parse logs -> reports/<design>_<variant>_qor.md
#   make clean   CONFIG=config/foo.mk
#
# Every number this repo publishes is produced by a tool here and parsed by a
# script — nothing in reports/ is typed by hand.

SHELL := /bin/bash

CONDA_ROOT  ?= /opt/conda
OR_BIN      := $(CONDA_ROOT)/envs/or/bin
YOSYS_BIN   := $(CONDA_ROOT)/envs/yosys/bin
ORFS_ROOT   ?= /home/user/ORFS
ORFS_FLOW   := $(ORFS_ROOT)/flow
REPO_ROOT   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

export PATH               := $(OR_BIN):$(YOSYS_BIN):$(PATH)
export SSL_CERT_FILE      := /etc/ssl/certs/ca-certificates.crt
export REQUESTS_CA_BUNDLE := /etc/ssl/certs/ca-certificates.crt

OPENROAD_EXE := $(OR_BIN)/openroad
YOSYS_CMD    := $(YOSYS_BIN)/yosys
KLAYOUT_CMD  := $(shell command -v klayout 2>/dev/null || echo echo)

# Default to the ORFS-bundled GCD example (smallest end-to-end proof).
CONFIG     ?= $(ORFS_FLOW)/designs/sky130hd/gcd/config.mk
CONFIG_ABS := $(abspath $(CONFIG))

# Identity is parsed straight out of the config so we can locate ORFS outputs.
SED_VAR     = sed -nE 's/^[[:space:]]*export[[:space:]]+$(1)[[:space:]]*[:?]?=[[:space:]]*([A-Za-z0-9_]+).*/\1/p' $(CONFIG_ABS) | head -1
PLATFORM     := $(shell $(call SED_VAR,PLATFORM))
DESIGN_NAME  := $(shell $(call SED_VAR,DESIGN_NAME))
NICK         := $(shell $(call SED_VAR,DESIGN_NICKNAME))
DESIGN_NICK  := $(if $(NICK),$(NICK),$(DESIGN_NAME))
FLOW_VARIANT ?= base

RESULTS_DIR  := $(ORFS_FLOW)/results/$(PLATFORM)/$(DESIGN_NICK)/$(FLOW_VARIANT)
LOG_DIR      := $(ORFS_FLOW)/logs/$(PLATFORM)/$(DESIGN_NICK)/$(FLOW_VARIANT)
REPORTS_DIR  := $(ORFS_FLOW)/reports/$(PLATFORM)/$(DESIGN_NICK)/$(FLOW_VARIANT)
PLATFORM_DIR := $(ORFS_FLOW)/platforms/$(PLATFORM)

ORFS_MAKE = $(MAKE) --no-print-directory -C $(ORFS_FLOW) SHELL=/bin/bash \
    DESIGN_CONFIG=$(CONFIG_ABS) FLOW_VARIANT=$(FLOW_VARIANT) \
    OPENROAD_EXE=$(OPENROAD_EXE) YOSYS_CMD=$(YOSYS_CMD) KLAYOUT_CMD=$(KLAYOUT_CMD)

.PHONY: synth floorplan place cts route finish globalroute smoke sta report qor clean help
.DEFAULT_GOAL := help

synth floorplan place cts route finish:
	$(ORFS_MAKE) $@

# Stop after global routing (FastRoute): yields global-route timing + a
# congestion report without paying for the (slow) detailed route. Used by E3.
globalroute:
	$(ORFS_MAKE) results/$(PLATFORM)/$(DESIGN_NICK)/$(FLOW_VARIANT)/route.guide

smoke:
	$(ORFS_MAKE) route
	@echo "SMOKE OK -> $(RESULTS_DIR)/5_route.def"

sta:
	@mkdir -p $(REPORTS_DIR)
	RESULTS_DIR=$(RESULTS_DIR) PLATFORM_DIR=$(PLATFORM_DIR) \
	  $(OPENROAD_EXE) -no_init -exit $(REPO_ROOT)/scripts/sta/signoff_sta.tcl \
	  2>&1 | tee $(REPORTS_DIR)/signoff_sta.rpt
	@echo "wrote $(REPORTS_DIR)/signoff_sta.rpt"

report qor:
	@mkdir -p $(REPO_ROOT)/reports
	python3 $(REPO_ROOT)/scripts/parse/parse_flow.py \
	  --design $(DESIGN_NICK) --platform $(PLATFORM) --variant $(FLOW_VARIANT) \
	  --log-dir $(LOG_DIR) --results-dir $(RESULTS_DIR) --reports-dir $(REPORTS_DIR) \
	  --out $(REPO_ROOT)/reports/$(DESIGN_NICK)_$(FLOW_VARIANT)_qor.md

clean:
	$(ORFS_MAKE) clean_all || true

help:
	@echo "rtl2gds-sta-lab  (override CONFIG=config/<x>.mk ; FLOW_VARIANT=<v>)"
	@echo "  smoke                              gcd -> route, proves the toolchain"
	@echo "  synth floorplan place cts route finish   ORFS stages"
	@echo "  sta                                signoff STA: top-5 setup/hold + skew"
	@echo "  report                             parse logs -> reports/<design>_qor.md"
	@echo "  clean                              ORFS clean_all for this design"
	@echo "  current: $(PLATFORM)/$(DESIGN_NICK)/$(FLOW_VARIANT)  <- $(CONFIG_ABS)"
