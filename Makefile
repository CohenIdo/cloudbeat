##############################################################################
# Variables used for various build targets.
##############################################################################
CI_ELASTIC_AGENT_DOCKER_TAG?=${CLOUDBEAT_VERSION}-SNAPSHOT
CI_ELASTIC_AGENT_DOCKER_IMAGE?=704479110758.dkr.ecr.eu-west-1.amazonaws.com/elastic-agent

# Ensure the Go version in .go_version is installed and used.
GOROOT?=$(shell ./scripts/make/run_with_go_ver go env GOROOT)
GO:=$(GOROOT)/bin/go
export PATH:=$(GOROOT)/bin:$(PATH)

# By default we run tests with verbose output. This may be overridden, e.g.
# scripts may set GOTESTFLAGS=-json to format test output for processing.
GOTESTFLAGS?=-v

GOOSBUILD:=./build/$(shell $(GO) env GOOS)
APPROVALS=$(GOOSBUILD)/approvals
GENPACKAGE=$(GOOSBUILD)/genpackage
GOIMPORTS=$(GOOSBUILD)/goimports
GOLICENSER=$(GOOSBUILD)/go-licenser
GOLINT=$(GOOSBUILD)/golint
MAGE=$(GOOSBUILD)/mage
REVIEWDOG=$(GOOSBUILD)/reviewdog
STATICCHECK=$(GOOSBUILD)/staticcheck
ELASTICPACKAGE=$(GOOSBUILD)/elastic-package

PYTHON_ENV?=.
PYTHON_BIN:=$(PYTHON_ENV)/build/ve/$(shell $(GO) env GOOS)/bin
PYTHON=$(PYTHON_BIN)/python

CLOUDBEAT_VERSION=$(shell grep defaultBeatVersion version/version.go | cut -d'=' -f2 | tr -d '" ')

# Create a local config.mk file to override configuration,
# e.g. for setting "GOLINT_UPSTREAM".
-include config.mk

##############################################################################
# Getting Started.
##############################################################################

## hermit

.PHONY: hermit
hermit:
	curl -fsSL https://github.com/cashapp/hermit/releases/download/stable/install.sh | /bin/bash

.PHONY: hermit-env
hermit-env:
	./bin/hermit env --raw

.PHONY: activate-hermit
active-hermit: hermit
	. ./bin/activate-hermit

.PHONY: deactivate-hermit
deactivate-hermit:
	. ./bin/activate-hermit

##############################################################################
# Rules for building and unit-testing cloudbeat.
##############################################################################

.DEFAULT_GOAL := cloudbeat

.PHONY: cloudbeat
cloudbeat: $(MAGE)
	@$(MAGE) build

.PHONY: test
test:
	$(GO) test $(GOTESTFLAGS) ./...

.PHONY:
clean: $(MAGE)
	@$(MAGE) clean

.PHONY: PackageAgent
PackageAgent: $(MAGE)
	SNAPSHOT=TRUE PLATFORMS=linux/$(shell $(GO) env GOARCH) TYPES=tar.gz $(MAGE) -v $@

# elastic_agent_docker_image builds the Cloud Elastic Agent image
# with the local APM Server binary injected. The image will be based
# off the stack version defined in ${REPO_ROOT}/docker-compose.yml,
# unless overridden.
.PHONY: build_elastic_agent_docker_image
elastic_agent_docker_image: build_elastic_agent_docker_image
	docker push "${CI_ELASTIC_AGENT_DOCKER_IMAGE}:${CI_ELASTIC_AGENT_DOCKER_TAG}"

build_elastic_agent_docker_image:
	@env BASE_IMAGE=docker.elastic.co/beats/elastic-agent:${CI_ELASTIC_AGENT_DOCKER_TAG} GOARCH=amd64 GOOS=linux  \
		bash dev-tools/packaging/docker/elastic-agent/build.sh \
		     -t ${CI_ELASTIC_AGENT_DOCKER_IMAGE}:${CI_ELASTIC_AGENT_DOCKER_TAG}

##############################################################################
# Checks/tests.
##############################################################################

.PHONY: check-full
# check-full: update check golint staticcheck check-docker-compose
check-full: update

.PHONY: check-approvals
check-approvals: $(APPROVALS)
	@$(APPROVALS)

.PHONY: check
check: $(MAGE) check-fmt check-headers
	@$(MAGE) check

.PHONY: bench
bench:
	@$(GO) test -benchmem -run=XXX -benchtime=100ms -bench='.*' ./...

##############################################################################
# Rules for updating config files, etc.
##############################################################################

#update: go-generate add-headers build-package notice $(MAGE)
update: go-generate add-headers $(MAGE)
	@$(MAGE) update
	@go mod download all # make sure go.sum is complete

config:
	@$(MAGE) config

.PHONY: go-generate
go-generate:
	@$(GO) generate .

notice: NOTICE.txt
NOTICE.txt: $(PYTHON) go.mod utils/go.mod
	@$(PYTHON) scripts/make/generate_notice.py .

.PHONY: add-headers
add-headers: $(GOLICENSER)
ifndef CHECK_HEADERS_DISABLED
	@$(GOLICENSER)
endif

## get-version : Get cloudbeat version
.PHONY: get-version
get-version:
	@echo $(CLOUDBEAT_VERSION)

##############################################################################
# Documentation.
##############################################################################

.PHONY: docs
docs:
	@rm -rf build/html_docs
	sh script/build_cloudbeat_docs.sh cloudbeat docs/index.asciidoc build

.PHONY: update-beats-docs
update-beats-docs: $(PYTHON)
	@$(PYTHON) script/copy-docs.py

##############################################################################
# Linting, style-checking, license header checks, etc.
##############################################################################

GOLINT_TARGETS?=$(shell $(GO) list ./...)
GOLINT_UPSTREAM?=origin/main
REVIEWDOG_FLAGS?=-conf=reviewdog.yml -f=golint -diff="git diff $(GOLINT_UPSTREAM)"
GOLINT_COMMAND=$(GOLINT) ${GOLINT_TARGETS} | grep -v "should have comment" | $(REVIEWDOG) $(REVIEWDOG_FLAGS)

.PHONY: golint
golint: $(GOLINT) $(REVIEWDOG)
	@output=$$($(GOLINT_COMMAND)); test -z "$$output" || (echo $$output && exit 1)

.PHONY: staticcheck
staticcheck: $(STATICCHECK)
	$(STATICCHECK) github.com/elastic/cloudbeat/...

.PHONY: check-changelogs
check-changelogs: $(PYTHON)
	$(PYTHON) script/check_changelogs.py

.PHONY: check-headers
check-headers: $(GOLICENSER)
ifndef CHECK_HEADERS_DISABLED
	@$(GOLICENSER) -d -exclude build -exclude x-pack -exclude internal/otel_collector
	@$(GOLICENSER) -d -exclude build -license Elasticv2 x-pack
endif

.PHONY: check-docker-compose
check-docker-compose: $(PYTHON_BIN)
	@PATH=$(PYTHON_BIN):$(PATH) ./scripts/make/check_docker_compose.sh $(BEATS_VERSION)

.PHONY: check-gofmt check-autopep8 gofmt autopep8
check-fmt: check-gofmt check-autopep8
fmt: gofmt autopep8
check-gofmt: $(GOIMPORTS)
	@PATH=$(GOOSBUILD):$(PATH) sh script/check_goimports.sh
gofmt: $(GOIMPORTS) add-headers
	@echo "fmt - goimports: Formatting Go code"
	@PATH=$(GOOSBUILD):$(PATH) GOIMPORTSFLAGS=-w sh script/goimports.sh
check-autopep8: $(PYTHON_BIN)
	@PATH=$(PYTHON_BIN):$(PATH) sh script/autopep8_all.sh --diff --exit-code
autopep8: $(PYTHON_BIN)
	@echo "fmt - autopep8: Formatting Python code"
	@PATH=$(PYTHON_BIN):$(PATH) sh script/autopep8_all.sh --in-place

##############################################################################
# Rules for creating and installing build tools.
##############################################################################

BIN_MAGE=$(GOOSBUILD)/bin/mage

# BIN_MAGE is the standard "mage" binary.
$(BIN_MAGE): go.mod
	$(GO) build -o $@ github.com/magefile/mage

# MAGE is the compiled magefile.
$(MAGE): magefile.go $(BIN_MAGE)
	$(BIN_MAGE) -compile=$@

$(GOLINT): go.mod
	$(GO) build -o $@ golang.org/x/lint/golint

$(GOIMPORTS): go.mod
	$(GO) build -o $@ golang.org/x/utils/cmd/goimports

$(STATICCHECK): utils/go.mod
	$(GO) build -o $@ -modfile=$< honnef.co/go/utils/cmd/staticcheck

$(GOLICENSER): go.mod
	$(GO) build -o $@ -modfile=$< github.com/elastic/go-licenser

$(REVIEWDOG): utils/go.mod
	$(GO) build -o $@ -modfile=$< github.com/reviewdog/reviewdog/cmd/reviewdog

$(ELASTICPACKAGE): utils/go.mod
	$(GO) build -o $@ -modfile=$< -ldflags '-X github.com/elastic/elastic-package/internal/version.CommitHash=anything' github.com/elastic/elastic-package

$(PYTHON): $(PYTHON_BIN)
$(PYTHON_BIN): $(PYTHON_BIN)/activate
$(PYTHON_BIN)/activate: $(MAGE)
	@$(MAGE) pythonEnv
	@touch $@

.PHONY: $(APPROVALS)
$(APPROVALS):
	@$(GO) build -o $@ github.com/elastic/cloudbeat/approvaltest/cmd/check-approvals

##############################################################################
# Release manager.
##############################################################################

# Builds a snapshot release.
.PHONY: release-manager-snapshot
release-manager-snapshot: export SNAPSHOT=true
release-manager-snapshot: release

# Builds a release.
.PHONY: release-manager-release
release-manager-release: release

.PHONY: release

release: export PATH:=$(dir $(BIN_MAGE)):$(PATH)
release: $(MAGE) $(PYTHON) build/dependencies.csv
	$(MAGE) package

build/dependencies.csv: $(PYTHON) go.mod
ifdef SNAPSHOT
	$(PYTHON) scripts/make/generate_notice.py --csv build/dependencies-${CLOUDBEAT_VERSION}-SNAPSHOT.csv
else
	$(PYTHON) scripts/make/generate_notice.py --csv build/dependencies-${CLOUDBEAT_VERSION}.csv
endif
