.PHONY: help lint setup pre-commit

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Install dependencies (ansible, pre-commit)
	./scripts/bootstrap.sh

lint: ## Run ansible-lint on roles and playbooks
	ansible-lint ansible/

pre-commit: ## Run pre-commit on all files
	pre-commit run --all-files
