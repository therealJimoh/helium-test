IMAGE ?= helium-test:dev

.PHONY: test lint build run scan k8s-render tf-validate

test:
	cd app && go test -race -cover ./...

lint:
	cd app && test -z "$$(gofmt -l .)" && go vet ./...

build:
	docker build -f docker/Dockerfile -t $(IMAGE) --build-arg VERSION=$$(git rev-parse --short HEAD 2>/dev/null || echo dev) .

run: build
	docker run --rm -p 8080:8080 --read-only -e API_TOKEN=local-dev $(IMAGE)

scan: build
	trivy image --severity HIGH,CRITICAL --ignore-unfixed $(IMAGE)

k8s-render:
	kubectl kustomize k8s

tf-validate:
	terraform fmt -recursive -check terraform
	for d in terraform/bootstrap terraform/environments/dev; do \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate; \
	done
