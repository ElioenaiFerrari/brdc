SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: help setup format lint dialyzer test check js-test js-vectors docs-check diagrams run fund balance

help: ## Lista os atalhos
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}'

setup: ## Baixa as dependências
	mix deps.get

format: ## Formata o código
	mix format

lint: ## Análise estática (credo, modo estrito)
	mix credo --strict

dialyzer: ## Tipos (dialyzer); a primeira vez monta o PLT e demora
	mix dialyzer

run: ## Sobe a carteira (http://localhost:4000) e o nó local de desenvolvimento (porta 4545) juntos
	mix phx.server

fund: ## BRDC de TESTE para um endereço (nó local rodando): make fund ADDR=brdc1… AMOUNT=100
	mix brdc.fund $(ADDR) $(AMOUNT)

balance: ## Saldo de um endereço no nó local: make balance ADDR=brdc1…
	mix brdc.balance $(ADDR)

reset-devnet: ## Apaga o disco da rede de teste local (net/data); pare o nó antes
	mix brdc.devnet.reset

test: ## Testes de todos os apps
	mix test

check: ## Portão de qualidade: formato, credo, testes e criptografia do navegador (o mesmo do CI)
	mix check
	node --test apps/brdc_web/assets/js/crypto/*.test.mjs 2>&1 | grep -E '^ℹ (tests|pass|fail)|✖'

js-test: ## Testa a criptografia do navegador (Node 24, mesmo crypto.subtle) contra os vetores do Elixir
	node --test apps/brdc_web/assets/js/crypto/*.test.mjs

js-vectors: ## Confere em JavaScript (Node) os mesmos vetores de cripto do Elixir
	node tools/js/verify-vectors.mjs

docs-check: ## Confere links, imagens, apps no README e idioma dos títulos
	./scripts/docs-check.sh

diagrams: ## Regenera docs/diagrams/*.png a partir de scripts/diagrams (precisa do Brave)
	python3 scripts/diagrams/generate.py
