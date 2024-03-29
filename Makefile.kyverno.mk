KYVERNO_CLI_IMAGE  ?= ghcr.io/kyverno/kyverno-cli:v1.6.2
KYVERNO_CLI_DOCKER ?= $(DOCKER_CMD) $(DOCKER_ARGS) $(root_volume) --entrypoint=/kyverno $(KYVERNO_CLI_IMAGE)
KYVERNO_CLI_ARGS   ?= -v2

test:
	ln -sfn ../../../compiled tests/kyverno/$(instance)/compiled
	@echo
	@echo
	@echo "Testing generated Kyverno policies"
	$(KYVERNO_CLI_DOCKER) test $(KYVERNO_CLI_ARGS) tests/kyverno/$(instance)

.PHONY: gen-policy-docs
gen-policy-docs: gen-golden
	(cd tools/render; go build)
	tools/render/render . tests/golden/$(instance)/appuio-cloud/appuio-cloud docs/modules/ROOT

.PHONY: policy-docs-diff
policy-docs-diff: gen-policy-docs
	@git diff --exit-code --minimal -- docs/modules/ROOT/partials/nav-policy.adoc docs/modules/ROOT/pages/references/policies

docs-serve: gen-policy-docs
