KYVERNO_CLI_IMAGE  ?= ghcr.io/kyverno/kyverno-cli:latest
KYVERNO_CLI_DOCKER ?= $(DOCKER_CMD) $(DOCKER_ARGS) $(root_volume) --entrypoint=/kyverno $(KYVERNO_CLI_IMAGE)
KYVERNO_CLI_ARGS   ?= -v2

test:
	ln -sfn ../../../compiled tests/kyverno/$(instance)/compiled
	@echo
	@echo
	@echo "Testing generated Kyverno policies"
	$(KYVERNO_CLI_DOCKER) test $(KYVERNO_CLI_ARGS) tests/kyverno/$(instance)