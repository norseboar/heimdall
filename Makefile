.PHONY: docker-image

docker-image:
	docker build -t 371589656068.dkr.ecr.us-east-1.amazonaws.com/heimdall:latest .
	docker push 371589656068.dkr.ecr.us-east-1.amazonaws.com/heimdall:latest
	@echo Latest image pushed - kill the current task to finish deploy
