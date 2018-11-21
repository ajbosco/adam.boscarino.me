PORT := 1337

.PHONY: run
run:
	@echo "==> Running site"
	@hugo server --port=$(PORT) --bind=0.0.0.0
