init:
	terraform -chdir=infra/envs/dev init

plan:
	terraform -chdir=infra/envs/dev plan

apply:
	terraform -chdir=infra/envs/dev apply

format:
	terraform fmt -recursive

destroy:
	terraform -chdir=infra/envs/dev destroy
