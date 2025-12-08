.PHONY: help build push install test clean

# Configuration
IMAGE_NAME := ghcr.io/arun4infra/function-eventdrivenservice
VERSION := v0.1.0
IMAGE := $(IMAGE_NAME):$(VERSION)

help: ## Show this help message
	@echo "EventDrivenService Composition Function"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

build: ## Build the function container image
	@echo "Building function image: $(IMAGE)"
	docker build -t $(IMAGE) .
	@echo "✓ Build complete"

push: ## Build and push the function image to registry (fetches credentials from AWS SSM)
	@echo "Building and pushing function image with SSM credentials..."
	@./build-and-push.sh
	@echo "✓ Build and push complete"

push-manual: build ## Push the function image (requires manual docker login)
	@echo "Pushing function image: $(IMAGE)"
	@echo "Note: Ensure you're logged in to ghcr.io (docker login ghcr.io)"
	docker push $(IMAGE)
	@echo "✓ Push complete"

install: ## Install the function in the Kubernetes cluster
	@echo "Installing function in cluster..."
	@kubectl apply -f - <<EOF
	apiVersion: pkg.crossplane.io/v1beta1
	kind: Function
	metadata:
	  name: function-eventdrivenservice
	spec:
	  package: $(IMAGE)
	EOF
	@echo "✓ Function installed"
	@echo ""
	@echo "Verify installation:"
	@echo "  kubectl get functions"
	@echo "  kubectl get pods -n crossplane-system | grep function-eventdrivenservice"

uninstall: ## Uninstall the function from the cluster
	@echo "Uninstalling function from cluster..."
	kubectl delete function function-eventdrivenservice --ignore-not-found
	@echo "✓ Function uninstalled"

status: ## Check function status in the cluster
	@echo "Function status:"
	@kubectl get function function-eventdrivenservice -o wide 2>/dev/null || echo "Function not installed"
	@echo ""
	@echo "Function pods:"
	@kubectl get pods -n crossplane-system -l pkg.crossplane.io/function=function-eventdrivenservice 2>/dev/null || echo "No pods found"

logs: ## Show function logs
	@echo "Function logs:"
	@kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-eventdrivenservice --tail=50

test: ## Run local tests
	@echo "Running tests..."
	go test -v ./...
	@echo "✓ Tests complete"

fmt: ## Format Go code
	@echo "Formatting code..."
	go fmt ./...
	@echo "✓ Format complete"

lint: ## Run linter
	@echo "Running linter..."
	golangci-lint run
	@echo "✓ Lint complete"

clean: ## Clean build artifacts
	@echo "Cleaning..."
	rm -f function
	@echo "✓ Clean complete"

dev: ## Build and install for local development
	$(MAKE) build
	$(MAKE) install
	@echo ""
	@echo "Development deployment complete!"
	@echo "Monitor logs with: make logs"

all: fmt lint test build push install ## Run all steps (format, lint, test, build, push, install)
	@echo ""
	@echo "✓ All steps complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Check function status: make status"
	@echo "  2. Monitor logs: make logs"
	@echo "  3. Test with a claim: kubectl apply -f ../../examples/full-claim.yaml"
